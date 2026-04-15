using System;
using System.Runtime.InteropServices;

namespace NezAvalonia.Core;

/// <summary>
/// P/Invoke bindings to the native Zig NES emulator library (libnez_emu).
/// Matches the actual Zig FFI exports in nez/src/ffi.zig exactly.
/// </summary>
public static class NezBindings
{
    // Button index constants
    public const int ButtonA      = 0;
    public const int ButtonB      = 1;
    public const int ButtonSelect = 2;
    public const int ButtonStart  = 3;
    public const int ButtonUp     = 4;
    public const int ButtonDown   = 5;
    public const int ButtonLeft   = 6;
    public const int ButtonRight  = 7;

    private const string LibName = "nez_emu";

    // --- Screen info (no parameters — global constants in Zig) ---

    [DllImport(LibName, EntryPoint = "nez_screen_width")]
    public static extern uint ScreenWidth();

    [DllImport(LibName, EntryPoint = "nez_screen_height")]
    public static extern uint ScreenHeight();

    [DllImport(LibName, EntryPoint = "nez_framebuffer_size")]
    public static extern uint FramebufferSize();

    // --- Lifecycle ---

    // nez_create(path) -> creates console, loads ROM from path, powers on; returns console ptr
    [DllImport(LibName, EntryPoint = "nez_create")]
    public static extern IntPtr Create([MarshalAs(UnmanagedType.LPUTF8Str)] string path);

    [DllImport(LibName, EntryPoint = "nez_destroy")]
    public static extern void Destroy(IntPtr console);

    // nez_load_rom(console, path) -> bool (reload a different ROM into existing console)
    [DllImport(LibName, EntryPoint = "nez_load_rom")]
    [return: MarshalAs(UnmanagedType.I1)]
    public static extern bool LoadRom(IntPtr console, [MarshalAs(UnmanagedType.LPUTF8Str)] string path);

    [DllImport(LibName, EntryPoint = "nez_power_on")]
    public static extern void PowerOn(IntPtr console);

    // --- Emulation ---

    // nez_update(console, dt_ms: u64) -> u64
    [DllImport(LibName, EntryPoint = "nez_update")]
    public static extern ulong Update(IntPtr console, ulong dtMs);

    // --- Framebuffer ---

    [DllImport(LibName, EntryPoint = "nez_framebuffer_get")]
    public static extern IntPtr FramebufferGet(IntPtr console);

    // --- Audio ---

    [DllImport(LibName, EntryPoint = "nez_audio_queue_pop")]
    public static extern short AudioQueuePop(IntPtr console);

    [DllImport(LibName, EntryPoint = "nez_audio_queue_len")]
    public static extern uint AudioQueueLen(IntPtr console);

    [DllImport(LibName, EntryPoint = "nez_audio_queue_drain")]
    public static extern uint AudioQueueDrain(IntPtr console, IntPtr outBuffer, uint maxSamples);

    // --- Input ---

    [DllImport(LibName, EntryPoint = "nez_input_set_buttons")]
    public static extern void InputSetButtons(IntPtr console, byte bitmask);

    [DllImport(LibName, EntryPoint = "nez_input_set_button")]
    public static extern void InputSetButton(IntPtr console, byte index,
        [MarshalAs(UnmanagedType.I1)] bool pressed);

    // --- Pause ---

    [DllImport(LibName, EntryPoint = "nez_is_paused")]
    [return: MarshalAs(UnmanagedType.I1)]
    public static extern bool IsPaused(IntPtr console);

    [DllImport(LibName, EntryPoint = "nez_set_pause")]
    public static extern void SetPause(IntPtr console, [MarshalAs(UnmanagedType.I1)] bool paused);

    // --- Debug ---

    [DllImport(LibName, EntryPoint = "nez_cpu_get_pc")]
    public static extern ushort CpuGetPc(IntPtr console);

    [DllImport(LibName, EntryPoint = "nez_cpu_get_registers")]
    public static extern CpuRegisters CpuGetRegisters(IntPtr console);
}

// Matches Zig: extern struct { a: u8, x: u8, y: u8, s: u8, pc: u16, p: u8 }
[StructLayout(LayoutKind.Sequential)]
public struct CpuRegisters
{
    public byte A;
    public byte X;
    public byte Y;
    public byte S;
    public ushort PC;
    public byte P;
}
