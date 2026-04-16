/// Web stub — provides [NesButton] constants without FFI/IO dependency.
/// Used when dart:io is unavailable (web compilation).
///
/// The actual FFI bindings live in [nez_bindings.dart] which requires dart:io/dart:ffi.

/// NES button indices (matches Zig Gamepad.Button enum order).
class NesButton {
  static const int a = 0;
  static const int b = 1;
  static const int select = 2;
  static const int start = 3;
  static const int up = 4;
  static const int down = 5;
  static const int left = 6;
  static const int right = 7;
}
