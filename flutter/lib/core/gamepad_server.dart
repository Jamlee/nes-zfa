import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'delta_encoder.dart';
import 'nez_engine.dart';
import 'web_gamepad_html.dart';

/// HTTP + WebSocket server for remote gamepad control and frame streaming.
/// Mirror mode uses the incremental delta protocol over WebSocket binary frames.
class GamepadServer {
  HttpServer? _server;
  final NezEngine _engine;
  final DeltaEncoder _deltaEncoder;
  final List<_WsClient> _clients = [];
  Timer? _frameTimer;
  String? _localIp;

  static const int port = 8080;
  static const int _frameIntervalMs = 33; // ~30fps delta stream

  GamepadServer(this._engine)
      : _deltaEncoder = DeltaEncoder(
          width: _engine.screenWidth,
          height: _engine.screenHeight,
          blockSize: 8,
          pixelFormat: DeltaEncoder.pixelFormatRgba32,
        );

  bool get isRunning => _server != null;
  String? get localIp => _localIp;
  String get p1Url => 'http://$_localIp:$port/?player=1';
  String get p2Url => 'http://$_localIp:$port/?player=2';
  String get p1MirrorUrl => 'http://$_localIp:$port/?player=1&mirror=true';
  String get p2MirrorUrl => 'http://$_localIp:$port/?player=2&mirror=true';

  Future<void> start() async {
    if (_server != null) return;

    _localIp = await _getLocalIp();
    if (_localIp == null) {
      debugPrint('NEZ GamepadServer: Could not determine local IP');
      _localIp = '127.0.0.1';
    }

    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
      debugPrint('NEZ GamepadServer: listening on $_localIp:$port');

      _server!.listen(_handleRequest, onError: (e) {
        debugPrint('NEZ GamepadServer error: $e');
      });

      // Push frames to mirror clients via WebSocket binary
      _frameTimer = Timer.periodic(
        const Duration(milliseconds: _frameIntervalMs),
        (_) => _pushFrames(),
      );
    } catch (e) {
      debugPrint('NEZ GamepadServer: failed to start: $e');
      _server = null;
    }
  }

  Future<void> stop() async {
    _frameTimer?.cancel();
    _frameTimer = null;

    for (final c in _clients) {
      c.ws.close();
    }
    _clients.clear();

    await _server?.close(force: true);
    _server = null;
    debugPrint('NEZ GamepadServer: stopped');
  }

  void _handleRequest(HttpRequest request) async {
    final path = request.uri.path;

    if (path == '/ws') {
      _handleWebSocket(request);
    } else {
      // Serve HTML for everything else
      request.response
        ..statusCode = 200
        ..headers.contentType = ContentType.html
        ..write(webGamepadHtml)
        ..close();
    }
  }

  void _handleWebSocket(HttpRequest request) async {
    try {
      final ws = await WebSocketTransformer.upgrade(request);
      final client = _WsClient(ws, wantsMirror: false);
      _clients.add(client);
      debugPrint('NEZ GamepadServer: WS client connected (${_clients.length})');

      ws.listen(
        (data) {
          if (data is String) {
            _processMessage(data, client);
          }
        },
        onDone: () {
          _clients.remove(client);
          debugPrint('NEZ GamepadServer: WS client disconnected');
        },
        onError: (e) {
          _clients.remove(client);
        },
      );
    } catch (e) {
      debugPrint('NEZ GamepadServer: WS upgrade failed: $e');
      request.response
        ..statusCode = 500
        ..close();
    }
  }

  void _processMessage(String data, _WsClient client) {
    try {
      final msg = jsonDecode(data) as Map<String, dynamic>;
      final type = msg['type'] as String?;
      final player = msg['player'] as int? ?? 1;

      if (type == 'btn') {
        final btn = msg['btn'] as int;
        final pressed = msg['pressed'] as bool;
        if (player == 1) {
          _engine.setButton(btn, pressed);
        } else {
          _engine.setButtonP2(btn, pressed);
        }
      } else if (type == 'turbo') {
        final btnName = msg['btn'] as String;
        final active = msg['active'] as bool;
        if (player == 1) {
          if (btnName == 'a') {
            _engine.setTurboA(active);
            _engine.setButton(0, active); // Also press A
          }
          if (btnName == 'b') {
            _engine.setTurboB(active);
            _engine.setButton(1, active); // Also press B
          }
        } else {
          // P2: just press the button (no turbo support yet)
          if (btnName == 'a') _engine.setButtonP2(0, active);
          if (btnName == 'b') _engine.setButtonP2(1, active);
        }
      } else if (type == 'reset') {
        _engine.togglePause();
        Future.delayed(const Duration(milliseconds: 100), () {
          _engine.togglePause();
        });
      } else if (type == 'mirror') {
        // Client requests frame streaming
        client.wantsMirror = msg['active'] as bool? ?? true;
        if (client.wantsMirror) {
          // Force a full keyframe for new mirror client
          _deltaEncoder.reset();
        }
        debugPrint('NEZ GamepadServer: client mirror=${client.wantsMirror}');
      } else if (type == 'keyframe') {
        // Client requests a full keyframe (e.g. after reconnect)
        _deltaEncoder.reset();
      }
    } catch (e) {
      debugPrint('NEZ GamepadServer: bad message: $e');
    }
  }

  void _pushFrames() {
    final hasMirrorClients = _clients.any((c) => c.wantsMirror);
    if (!hasMirrorClients) return;

    final rgba = _engine.lastRgbaFrame;
    if (rgba == null) return;

    // Encode delta (synchronous, fast — no JPEG encoding)
    Uint8List payload;
    try {
      payload = _deltaEncoder.encode(rgba);
    } catch (_) {
      return;
    }

    final toRemove = <_WsClient>[];
    for (final c in _clients) {
      if (!c.wantsMirror) continue;
      try {
        c.ws.add(payload);
      } catch (_) {
        toRemove.add(c);
      }
    }
    for (final c in toRemove) {
      _clients.remove(c);
      try { c.ws.close(); } catch (_) {}
    }
  }

  static Future<String?> _getLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      // Prefer WiFi interfaces (wlan, en0, etc.)
      for (final iface in interfaces) {
        final name = iface.name.toLowerCase();
        if (name.contains('wlan') || name.contains('en0') || name.contains('wifi')) {
          for (final addr in iface.addresses) {
            if (!addr.isLoopback && !addr.address.startsWith('169.254')) {
              return addr.address;
            }
          }
        }
      }
      // Fallback: any non-loopback IPv4
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback && !addr.address.startsWith('169.254')) {
            return addr.address;
          }
        }
      }
    } catch (e) {
      debugPrint('NEZ GamepadServer: IP detection error: $e');
    }

    // Last resort: UDP socket trick
    try {
      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.close();
      // Try connecting to get local address
      final s = await Socket.connect('8.8.8.8', 80, timeout: const Duration(seconds: 2));
      final ip = s.address.address;
      s.destroy();
      if (ip != '127.0.0.1' && ip != '0.0.0.0') return ip;
    } catch (_) {}

    return null;
  }
}

class _WsClient {
  final WebSocket ws;
  bool wantsMirror;
  _WsClient(this.ws, {required this.wantsMirror});
}
