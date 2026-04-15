# Nez

NES emulator with Zig core and multiple UI frontends.

<div style="display: flex; gap: 10px;">
    <img src="./lib/screens/megaman_gameplay.gif" alt="Megaman" width="256px"/>
    <img src="./lib/screens/tetris.gif" alt="Tetris" width="256px"/>
</div>

```
├── lib/          Zig emulator core (CPU, PPU, APU, mappers)
├── flutter/      Flutter UI (macOS, Android)
├── avalonia/     Avalonia UI (macOS, Windows, Linux, Android)
├── roms/         ROM files (place .nes here)
├── build.sh      Build script
└── design.html   Interactive design mockup
```

## Quick Start

```bash
./build.sh flutter       # Flutter macOS
./build.sh avalonia       # Avalonia macOS
./build.sh apk            # Flutter Android APK
./build.sh apk-avalonia   # Avalonia Android APK
./build.sh lib            # Zig shared library only
./build.sh clean          # Clean all
```

## Prerequisites

| Frontend | Requirements |
|----------|-------------|
| All | [Zig](https://ziglang.org) 0.14+ |
| Flutter | [Flutter](https://flutter.dev) 3.x, Xcode (macOS) |
| Avalonia | [.NET](https://dotnet.microsoft.com) 10+ |
| Android | Android SDK + NDK |

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
Virtual joystick + A/B + Turbo A/B buttons. Landscape mode: joystick left, game center, buttons right.

### Desktop

| Action | Key |
|--------|-----|
| Move | W A S D |
| A / B | J / K |
| Turbo A / B | U / I |
| Start / Select | Enter / X |
| Pause | Space |
| Record GIF | ⌘R |
| Debug | ⌘D |
| Back | Esc |

## Features

- GIF recording (toolbar button or ⌘R)
- ROM library with persistence
- Virtual gamepad with turbo buttons
- Debug panel (CPU registers, PPU status)
- Audio output (macOS)
- Adaptive layout (portrait/landscape)

## Emulator Roadmap

- [x] CPU: Ricoh 2A03 (cycle-accurate 6502)
- [x] PPU: Ricoh 2C02 (scanline renderer)
- [x] Vertical scrolling
- [x] Horizontal scrolling
- [x] Split scrolling
- [x] Sprite zero hit
- [x] Controller input
- [ ] APU: Full audio support (2/5 channels implemented)
- [ ] Sprite overflow detection
- **Mappers:**
  - [x] NROM (Mapper 0)
  - [x] MMC1 (Mapper 1) — some minor bugs remain
  - [x] UxROM (Mapper 2)
  - [ ] CNROM (Mapper 3)
  - [ ] MMC3 (Mapper 4)
  - [ ] MMC5 (Mapper 5)

## Supported Games

- **NROM** — Donkey Kong, Pac-Man, Super Mario Bros
- **MMC1** — Mega Man, Legend of Zelda
- **UxROM** — Contra, Castlevania, Jackal

## Credits

Emulator core based on [nez](https://github.com/) — a Zig NES emulator by the original author.
UI frontends and FFI bridge by this project.

## License

MIT
