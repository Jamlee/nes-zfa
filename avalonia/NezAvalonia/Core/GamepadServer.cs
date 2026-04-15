using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Net.WebSockets;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using SixLabors.ImageSharp;
using SixLabors.ImageSharp.Formats.Jpeg;
using SixLabors.ImageSharp.PixelFormats;

namespace NezAvalonia.Core;

/// <summary>
/// HTTP + WebSocket server that serves the web gamepad HTML page,
/// an MJPEG video stream, and receives controller input via WebSocket.
/// </summary>
public sealed class GamepadServer : IDisposable
{
    private readonly NezEngine _engine;
    private HttpListener? _listener;
    private CancellationTokenSource? _cts;
    private Task? _listenerTask;
    private readonly ConcurrentBag<WebSocket> _sockets = new();

    public int Port { get; private set; } = 8080;
    public bool IsRunning => _listener?.IsListening == true;

    public GamepadServer(NezEngine engine)
    {
        _engine = engine;
    }

    /// <summary>
    /// Get the local network IP address for QR code generation.
    /// </summary>
    public static string GetLocalIp()
    {
        // Method 1: UDP socket trick (most reliable cross-platform)
        try
        {
            using var socket = new System.Net.Sockets.Socket(
                AddressFamily.InterNetwork, System.Net.Sockets.SocketType.Dgram, 0);
            socket.Connect("8.8.8.8", 80);
            if (socket.LocalEndPoint is System.Net.IPEndPoint ep
                && ep.Address.ToString() != "127.0.0.1"
                && ep.Address.ToString() != "0.0.0.0")
                return ep.Address.ToString();
        }
        catch { }

        // Method 2: DNS hostname resolution
        try
        {
            var host = System.Net.Dns.GetHostEntry(System.Net.Dns.GetHostName());
            foreach (var addr in host.AddressList)
            {
                if (addr.AddressFamily == AddressFamily.InterNetwork
                    && !IPAddress.IsLoopback(addr)
                    && !addr.ToString().StartsWith("169.254"))
                    return addr.ToString();
            }
        }
        catch { }

        // Method 3: Enumerate network interfaces
        try
        {
            foreach (var ni in NetworkInterface.GetAllNetworkInterfaces())
            {
                if (ni.OperationalStatus != OperationalStatus.Up) continue;
                if (ni.NetworkInterfaceType is NetworkInterfaceType.Loopback
                    or NetworkInterfaceType.Tunnel) continue;

                foreach (var addr in ni.GetIPProperties().UnicastAddresses)
                {
                    if (addr.Address.AddressFamily == AddressFamily.InterNetwork
                        && !IPAddress.IsLoopback(addr.Address)
                        && !addr.Address.ToString().StartsWith("169.254")
                        && addr.Address.ToString() != "127.0.0.1")
                    {
                        return addr.Address.ToString();
                    }
                }
            }
        }
        catch { }

#if ANDROID
        // Method 4: Android WifiManager
        try
        {
            var context = Android.App.Application.Context;
            var wifiManager = (Android.Net.Wifi.WifiManager?)context.GetSystemService(Android.Content.Context.WifiService);
            if (wifiManager?.ConnectionInfo?.IpAddress is int ip && ip != 0)
            {
                return $"{ip & 0xFF}.{(ip >> 8) & 0xFF}.{(ip >> 16) & 0xFF}.{(ip >> 24) & 0xFF}";
            }
        }
        catch { }
#endif

        return "0.0.0.0"; // Signal that no IP was found
    }

    public void Start()
    {
        if (_listener != null) return;

        _cts = new CancellationTokenSource();
        _listener = new HttpListener();

        // Try multiple prefix styles for cross-platform compat
        try
        {
            _listener.Prefixes.Add($"http://*:{Port}/");
            _listener.Start();
        }
        catch
        {
            // macOS without admin rights: fall back to localhost + 0.0.0.0 via separate listener
            _listener = new HttpListener();
            try
            {
                _listener.Prefixes.Add($"http://+:{Port}/");
                _listener.Start();
            }
            catch
            {
                _listener = new HttpListener();
                _listener.Prefixes.Add($"http://localhost:{Port}/");
                _listener.Start();
            }
        }

        _listenerTask = Task.Run(() => AcceptLoop(_cts.Token));
    }

    public void Stop()
    {
        _cts?.Cancel();
        try { _listener?.Stop(); } catch { /* ignore */ }
        _listener?.Close();
        _listener = null;

        // Close all websockets
        foreach (var ws in _sockets)
        {
            try
            {
                if (ws.State == WebSocketState.Open)
                    ws.CloseAsync(WebSocketCloseStatus.NormalClosure, "Server stopping",
                        CancellationToken.None).Wait(500);
            }
            catch { /* ignore */ }
            ws.Dispose();
        }
        _sockets.Clear();
    }

    private async Task AcceptLoop(CancellationToken ct)
    {
        while (!ct.IsCancellationRequested && _listener?.IsListening == true)
        {
            try
            {
                var ctx = await _listener.GetContextAsync().ConfigureAwait(false);
                _ = Task.Run(() => HandleRequest(ctx, ct), ct);
            }
            catch (ObjectDisposedException) { break; }
            catch (HttpListenerException) { break; }
            catch { /* continue */ }
        }
    }

    private async Task HandleRequest(HttpListenerContext ctx, CancellationToken ct)
    {
        try
        {
            var path = ctx.Request.Url?.AbsolutePath ?? "/";

            if (ctx.Request.IsWebSocketRequest && path == "/ws")
            {
                await HandleWebSocket(ctx, ct);
                return;
            }

            switch (path)
            {
                case "/":
                    ServeHtml(ctx);
                    break;
                case "/stream":
                    await ServeMjpeg(ctx, ct);
                    break;
                default:
                    ctx.Response.StatusCode = 404;
                    ctx.Response.Close();
                    break;
            }
        }
        catch
        {
            try { ctx.Response.Close(); } catch { /* ignore */ }
        }
    }

    private void ServeHtml(HttpListenerContext ctx)
    {
        var html = Encoding.UTF8.GetBytes(WebGamepadHtml.Html);
        ctx.Response.ContentType = "text/html; charset=utf-8";
        ctx.Response.ContentLength64 = html.Length;
        ctx.Response.OutputStream.Write(html, 0, html.Length);
        ctx.Response.Close();
    }

    private async Task ServeMjpeg(HttpListenerContext ctx, CancellationToken ct)
    {
        const string boundary = "--nezframe";
        ctx.Response.ContentType = $"multipart/x-mixed-replace; boundary={boundary}";
        ctx.Response.Headers.Add("Cache-Control", "no-cache");
        ctx.Response.Headers.Add("Connection", "keep-alive");

        var stream = ctx.Response.OutputStream;
        var encoder = new JpegEncoder { Quality = 50 };
        int w = _engine.ScreenWidth;
        int h = _engine.ScreenHeight;

        var sw = Stopwatch.StartNew();
        double nextFrame = 0;
        const double frameInterval = 1000.0 / 20.0; // 20 fps

        try
        {
            while (!ct.IsCancellationRequested)
            {
                double now = sw.Elapsed.TotalMilliseconds;
                if (now < nextFrame)
                {
                    await Task.Delay(Math.Max(1, (int)(nextFrame - now)), ct);
                }
                nextFrame = Math.Max(nextFrame + frameInterval, sw.Elapsed.TotalMilliseconds);

                var buffer = _engine.GetBackBuffer();
                if (buffer == null) continue;

                using var image = Image.LoadPixelData<Bgra32>(buffer, w, h);
                using var ms = new MemoryStream();
                image.Save(ms, encoder);
                var jpeg = ms.ToArray();

                var header = Encoding.ASCII.GetBytes(
                    $"\r\n{boundary}\r\nContent-Type: image/jpeg\r\nContent-Length: {jpeg.Length}\r\n\r\n");

                await stream.WriteAsync(header, 0, header.Length, ct);
                await stream.WriteAsync(jpeg, 0, jpeg.Length, ct);
                await stream.FlushAsync(ct);
            }
        }
        catch (OperationCanceledException) { }
        catch { /* client disconnected */ }
        finally
        {
            try { ctx.Response.Close(); } catch { /* ignore */ }
        }
    }

    private async Task HandleWebSocket(HttpListenerContext ctx, CancellationToken ct)
    {
        WebSocketContext wsCtx;
        try
        {
            wsCtx = await ctx.AcceptWebSocketAsync(null);
        }
        catch
        {
            ctx.Response.StatusCode = 500;
            ctx.Response.Close();
            return;
        }

        var ws = wsCtx.WebSocket;
        _sockets.Add(ws);

        var buf = new byte[1024];
        try
        {
            while (ws.State == WebSocketState.Open && !ct.IsCancellationRequested)
            {
                var result = await ws.ReceiveAsync(new ArraySegment<byte>(buf), ct);
                if (result.MessageType == WebSocketMessageType.Close) break;
                if (result.MessageType != WebSocketMessageType.Text) continue;

                var json = Encoding.UTF8.GetString(buf, 0, result.Count);
                ProcessMessage(json);
            }
        }
        catch { /* disconnected */ }
        finally
        {
            try
            {
                if (ws.State == WebSocketState.Open)
                    await ws.CloseAsync(WebSocketCloseStatus.NormalClosure, "", CancellationToken.None);
            }
            catch { /* ignore */ }
            ws.Dispose();
        }
    }

    private void ProcessMessage(string json)
    {
        try
        {
            using var doc = JsonDocument.Parse(json);
            var root = doc.RootElement;
            var type = root.GetProperty("type").GetString();

            if (type == "btn")
            {
                int player = root.GetProperty("player").GetInt32();
                int btn = root.GetProperty("btn").GetInt32();
                bool pressed = root.GetProperty("pressed").GetBoolean();

                if (player == 1)
                    _engine.SetButton(btn, pressed);
                else if (player == 2)
                    _engine.SetButtonP2(btn, pressed);
            }
            else if (type == "turbo")
            {
                int player = root.GetProperty("player").GetInt32();
                string? btn = root.GetProperty("btn").GetString();
                bool active = root.GetProperty("active").GetBoolean();

                // Turbo only for P1 for now (matching existing engine API)
                if (player == 1)
                {
                    if (btn == "a") _engine.SetTurboA(active);
                    else if (btn == "b") _engine.SetTurboB(active);
                }
            }
        }
        catch
        {
            // Ignore malformed messages
        }
    }

    public void Dispose()
    {
        Stop();
        _cts?.Dispose();
    }
}
