using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Diagnostics;
using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Net.WebSockets;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;

namespace NezAvalonia.Core;

/// <summary>
/// HTTP + WebSocket server that serves the web gamepad HTML page,
/// and receives controller input via WebSocket.
/// Mirror mode uses the incremental delta protocol over WebSocket.
/// </summary>
public sealed class GamepadServer : IDisposable
{
    private INezEngine? _engine;
    private DeltaEncoder _deltaEncoder;
    private HttpListener? _listener;
    private CancellationTokenSource? _cts;
    private Task? _listenerTask;
    private readonly ConcurrentBag<WebSocket> _sockets = new();

    // Track which sockets want mirror (delta) frames
    private readonly ConcurrentDictionary<WebSocket, bool> _mirrorClients = new();

    public int Port { get; private set; } = 8080;
    public bool IsRunning => _listener?.IsListening == true;
    public INezEngine? Engine => _engine;

    /// Create without an engine — engine will be set when gameplay starts.
    public GamepadServer() : this(null!) { }

    public GamepadServer(INezEngine engine)
    {
        _engine = engine;
        if (_engine != null) {
            _deltaEncoder = new DeltaEncoder(_engine.ScreenWidth, _engine.ScreenHeight, blockSize: 8);
        } else {
            // Placeholder: will be re-initialized when engine is set
            _deltaEncoder = new DeltaEncoder(256, 240, blockSize: 8);
        }
    }

    /// Update the active game engine (called when entering/exiting gameplay).
    public void SetEngine(INezEngine? engine)
    {
        _engine = engine;
        if (_engine != null)
            _deltaEncoder = new DeltaEncoder(_engine.ScreenWidth, _engine.ScreenHeight, blockSize: 8);
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
        _deltaCts?.Cancel();
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
        _mirrorClients.Clear();
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

        // Start delta broadcast if this is the first mirror client
        EnsureDeltaBroadcast(ct);

        var buf = new byte[1024];
        try
        {
            while (ws.State == WebSocketState.Open && !ct.IsCancellationRequested)
            {
                var result = await ws.ReceiveAsync(new ArraySegment<byte>(buf), ct);
                if (result.MessageType == WebSocketMessageType.Close) break;
                if (result.MessageType != WebSocketMessageType.Text) continue;

                var json = Encoding.UTF8.GetString(buf, 0, result.Count);
                ProcessMessage(ws, json);
            }
        }
        catch { /* disconnected */ }
        finally
        {
            _mirrorClients.TryRemove(ws, out _);
            try
            {
                if (ws.State == WebSocketState.Open)
                    await ws.CloseAsync(WebSocketCloseStatus.NormalClosure, "", CancellationToken.None);
            }
            catch { /* ignore */ }
            ws.Dispose();
        }
    }

    // ---- Delta frame broadcast ----

    private Task? _deltaBroadcastTask;
    private CancellationTokenSource? _deltaCts;

    private void EnsureDeltaBroadcast(CancellationToken ct)
    {
        // Already running
        if (_deltaBroadcastTask != null && !_deltaBroadcastTask.IsCompleted) return;

        _deltaCts = CancellationTokenSource.CreateLinkedTokenSource(ct);
        _deltaBroadcastTask = Task.Run(() => DeltaBroadcastLoop(_deltaCts.Token), _deltaCts.Token);
    }

    private async Task DeltaBroadcastLoop(CancellationToken ct)
    {
        var sw = Stopwatch.StartNew();
        double nextFrame = 0;
        const double frameInterval = 1000.0 / 30.0; // 30 fps delta stream

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

                // Only broadcast if there are mirror clients
                if (_mirrorClients.IsEmpty) continue;

                var buffer = _engine.GetBackBuffer();
                if (buffer == null) continue;

                // Encode delta
                byte[] payload;
                try
                {
                    payload = _deltaEncoder.Encode(buffer);
                }
                catch
                {
                    continue;
                }

                // Send to all mirror clients
                var segment = new ArraySegment<byte>(payload);
                var deadSockets = new List<WebSocket>();

                foreach (var kvp in _mirrorClients)
                {
                    var ws = kvp.Key;
                    try
                    {
                        if (ws.State == WebSocketState.Open)
                            await ws.SendAsync(segment, WebSocketMessageType.Binary, true, ct);
                        else
                            deadSockets.Add(ws);
                    }
                    catch
                    {
                        deadSockets.Add(ws);
                    }
                }

                // Cleanup dead sockets
                foreach (var ws in deadSockets)
                {
                    _mirrorClients.TryRemove(ws, out _);
                }
            }
        }
        catch (OperationCanceledException) { }
        catch { /* ignore */ }
    }

    private void ProcessMessage(WebSocket ws, string json)
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
            else if (type == "mirror")
            {
                bool active = root.GetProperty("active").GetBoolean();
                if (active)
                {
                    _mirrorClients[ws] = true;
                    // Force a full frame for new mirror client
                    _deltaEncoder.Reset();
                }
                else
                {
                    _mirrorClients.TryRemove(ws, out _);
                }
            }
            else if (type == "keyframe")
            {
                // Client requests a full keyframe (e.g. after reconnect or frame skip)
                _deltaEncoder.Reset();
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
