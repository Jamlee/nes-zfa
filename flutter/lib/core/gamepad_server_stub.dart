/// Web stub — provides [GamepadServer] that is a no-op.
/// On native platforms, [gamepad_server.dart] provides the real HTTP/WebSocket server.

import 'package:flutter/foundation.dart';
import 'nez_engine_stub.dart';

/// No-op gamepad server for web. Remote controller not supported in browser context.
class GamepadServer {
  final NezEngine _engine;
  bool _running = false;

  GamepadServer(this._engine);

  bool get isRunning => _running;
  String? get localIp => null;
  String get p1Url => '';
  String get p2Url => '';
  String get p1MirrorUrl => '';
  String get p2MirrorUrl => '';

  Future<void> start() async {
    debugPrint('NEZ GamepadServer: remote gamepad not supported on web');
    _running = true;
  }

  Future<void> stop() async {
    _running = false;
  }
}
