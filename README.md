# Nez

NES emulator with Zig core and multiple UI frontends.

```
nezf/
├── lib/          Zig emulator core (CPU, PPU, APU, mappers)
├── flutter/      Flutter UI (macOS, Android)
├── avalonia/     Avalonia UI (macOS, Windows, Linux)
├── build.sh      Build script
└── design.html   Interactive design mockup
```

## Quick Start

```bash
# Flutter (macOS)
./build.sh flutter

# Avalonia (macOS/Windows/Linux)
./build.sh avalonia

# Android APK
./build.sh apk
```

## Prerequisites

| Frontend | Requirements |
|----------|-------------|
| All | [Zig](https://ziglang.org) 0.14+ |
| Flutter | [Flutter](https://flutter.dev) 3.x, Xcode (macOS) |
| Avalonia | [.NET](https://dotnet.microsoft.com) 10+ |
| Android | Android SDK + NDK |

## Build Commands

```bash
./build.sh flutter      # Build lib + run Flutter macOS
./build.sh avalonia      # Build lib + run Avalonia
./build.sh android       # Build lib + run Flutter Android
./build.sh apk           # Build Android APK
./build.sh apk --release # Release APK
./build.sh lib           # Build Zig shared library only
./build.sh clean         # Clean all artifacts
./build.sh check         # Check toolchain
```

## Architecture

```
┌─────────────────────────────────┐
│  UI (Flutter / Avalonia)        │
│  Library · Gameplay · Settings  │
├─────────────────────────────────┤
│  FFI Bridge (dart:ffi / P/Invoke)│
├─────────────────────────────────┤
│  Zig Emulator Core (C ABI)      │
│  CPU 6502 · PPU 2C02 · APU     │
│  Bus · Mappers (NROM/MMC1/UxROM)│
└─────────────────────────────────┘
```

The Zig core compiles to `libnez_emu.dylib` / `.so` / `.dll`, exposing C functions via `lib/src/ffi.zig`. Both Flutter and Avalonia call the same shared library.

## Controls

### Mobile
Virtual joystick + A/B + Turbo A/B buttons.

### Desktop

| Action | Key |
|--------|-----|
| Move | W A S D |
| A / B | J / K |
| Turbo A / B | U / I |
| Start / Select | Enter / X |
| Pause | Space |
| Debug | ⌘D |
| Back | Esc |

## Supported Mappers

- **NROM** — Donkey Kong, Pac-Man, Super Mario Bros
- **MMC1** — Mega Man, Zelda
- **UxROM** — Contra, Castlevania, Jackal

## License

MIT
