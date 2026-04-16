//! FFI Bridge for WASM/Web targets
//! 
//! This file is used when compiling for wasm32-freestanding.
//! It only includes functions that work without a filesystem.
//! ROM loading is done from memory (nez_create_from_memory) instead of files.

const std = @import("std");
const nes = @import("nes.zig");
const PPU = @import("./ppu/ppu.zig").PPU;
const Cart = @import("cart.zig").Cart;

// ============================================================================
// TYPES & CONSTANTS
// ============================================================================

pub const NezConsole = opaque {};

pub const CpuRegisters = extern struct {
    a: u8,
    x: u8,
    y: u8,
    s: u8,
    pc: u16,
    p: u8,
};

// ============================================================================
// SCREEN INFO
// ============================================================================

export fn nez_screen_width() callconv(.c) u32 {
    return PPU.ScreenWidth;
}

export fn nez_screen_height() callconv(.c) u32 {
    return PPU.ScreenHeight;
}

export fn nez_framebuffer_size() callconv(.c) u32 {
    return PPU.ScreenWidth * PPU.ScreenHeight * 3;
}

// ============================================================================
// GLOBAL STATE
// ============================================================================

var console: ?*nes.Console = null;

// Use page_allocator for WASM — simple and works on freestanding
fn getAllocator() std.mem.Allocator {
    return std.heap.page_allocator;
}

// ============================================================================
// LIFECYCLE FUNCTIONS
// ============================================================================

export fn nez_create(path: [*:0]const u8) callconv(.c) ?*NezConsole {
    // WASM: cannot read files from filesystem, use nez_create_from_memory instead
    _ = path;
    return null;
}

export fn nez_destroy(console_ptr: ?*NezConsole) callconv(.c) void {
    if (console_ptr) |ptr| {
        const cons: *nes.Console = @ptrCast(@alignCast(ptr));
        const alloc = getAllocator();
        cons.deinit();
        alloc.destroy(cons);
        console = null;
    }
}

// ============================================================================
// EMULATION CONTROL
// ============================================================================

export fn nez_load_rom(console_ptr: ?*NezConsole, path: [*:0]const u8) callconv(.c) bool {
    _ = console_ptr;
    _ = path;
    return false;
}

export fn nez_power_on(console_ptr: ?*NezConsole) callconv(.c) void {
    if (console_ptr) |ptr| {
        const cons: *nes.Console = @ptrCast(@alignCast(ptr));
        cons.powerOn();
    }
}

export fn nez_update(console_ptr: ?*NezConsole, dt_ms: u64) callconv(.c) u64 {
    if (console_ptr) |ptr| {
        const cons: *nes.Console = @ptrCast(@alignCast(ptr));
        return cons.update(dt_ms) catch 0;
    }
    return 0;
}

// ============================================================================
// WASM ROM LOADING (from memory buffer)
// ============================================================================

/// Allocate memory for ROM data. Returns pointer to allocated buffer.
/// JS side: const ptr = nez_alloc_rom(size); then copy bytes into WASM memory.
export fn nez_alloc_rom(size: u32) callconv(.c) ?[*]u8 {
    const alloc = getAllocator();
    const buf = alloc.alloc(u8, size) catch return null;
    return buf.ptr;
}

/// Free a previously allocated ROM buffer.
export fn nez_free_rom(ptr: [*]u8, size: u32) callconv(.c) void {
    const alloc = getAllocator();
    alloc.free(ptr[0..size]);
}

/// Create console from ROM data in memory (for WASM / web use).
/// `data`: pointer to ROM bytes (previously allocated via nez_alloc_rom).
/// `size`: length of ROM data in bytes.
export fn nez_create_from_memory(data: [*]const u8, size: u32) callconv(.c) ?*NezConsole {
    const alloc = getAllocator();
    const rom_data = data[0..size];
    console = alloc.create(nes.Console) catch return null;
    errdefer alloc.destroy(console.?);

    console.?.* = nes.Console.fromROMData(alloc, rom_data) catch return null;
    console.?.powerOn();
    return @ptrCast(@alignCast(console.?));
}

/// Load ROM from memory buffer into existing console (WASM).
export fn nez_load_rom_from_memory(console_ptr: ?*NezConsole, data: [*]const u8, size: u32) callconv(.c) bool {
    if (console_ptr) |ptr| {
        const cons: *nes.Console = @ptrCast(@alignCast(ptr));
        const alloc = getAllocator();
        const rom_data = data[0..size];
        cons.* = nes.Console.fromROMData(alloc, rom_data) catch return false;
        cons.powerOn();
        return true;
    }
    return false;
}

// ============================================================================
// FRAME BUFFER ACCESS
// ============================================================================

export fn nez_framebuffer_get(console_ptr: ?*NezConsole) callconv(.c) [*]const u8 {
    if (console_ptr) |ptr| {
        const cons: *nes.Console = @ptrCast(@alignCast(ptr));
        return cons.ppu.render_buffer[0..].ptr;
    }
    return undefined;
}

// ============================================================================
// AUDIO QUEUE
// ============================================================================

export fn nez_audio_queue_pop(console_ptr: ?*NezConsole) callconv(.c) i16 {
    if (console_ptr) |ptr| {
        const cons: *nes.Console = @ptrCast(@alignCast(ptr));
        return cons.audio_sample_queue.pop() catch 0;
    }
    return 0;
}

export fn nez_audio_queue_len(console_ptr: ?*NezConsole) callconv(.c) u32 {
    if (console_ptr) |ptr| {
        const cons: *nes.Console = @ptrCast(@alignCast(ptr));
        return @intCast(cons.audio_sample_queue.len());
    }
    return 0;
}

export fn nez_audio_queue_drain(
    console_ptr: ?*NezConsole,
    out_buffer: [*]i16,
    max_samples: u32,
) callconv(.c) u32 {
    if (console_ptr) |ptr| {
        const cons: *nes.Console = @ptrCast(@alignCast(ptr));
        var count: u32 = 0;
        while (count < max_samples) {
            if (cons.audio_sample_queue.pop() catch null) |sample| {
                out_buffer[count] = sample;
                count += 1;
            } else {
                break;
            }
        }
        return count;
    }
    return 0;
}

// ============================================================================
// INPUT HANDLING
// ============================================================================

export fn nez_input_set_buttons(console_ptr: ?*NezConsole, button_state: u8) callconv(.c) void {
    if (console_ptr) |ptr| {
        const cons: *nes.Console = @ptrCast(@alignCast(ptr));
        var buttons: [8]bool = undefined;
        for (0..8) |i| {
            buttons[i] = (button_state & (@as(u8, 1) << @intCast(i))) != 0;
        }
        cons.controller.setInputs(buttons);
    }
}

export fn nez_input_set_buttons_p2(console_ptr: ?*NezConsole, button_state: u8) callconv(.c) void {
    if (console_ptr) |ptr| {
        const cons: *nes.Console = @ptrCast(@alignCast(ptr));
        var buttons: [8]bool = undefined;
        for (0..8) |i| {
            buttons[i] = (button_state & (@as(u8, 1) << @intCast(i))) != 0;
        }
        cons.controller2.setInputs(buttons);
    }
}

export fn nez_input_set_button(
    console_ptr: ?*NezConsole,
    button_index: u8,
    pressed: bool,
) callconv(.c) void {
    if (console_ptr) |ptr| {
        const cons: *nes.Console = @ptrCast(@alignCast(ptr));
        if (button_index < 8) {
            cons.controller.buttons[button_index] = pressed;
        }
    }
}

export fn nez_input_set_button_p2(
    console_ptr: ?*NezConsole,
    button_index: u8,
    pressed: bool,
) callconv(.c) void {
    if (console_ptr) |ptr| {
        const cons: *nes.Console = @ptrCast(@alignCast(ptr));
        if (button_index < 8) {
            cons.controller2.buttons[button_index] = pressed;
        }
    }
}

export fn nez_input_get_button(console_ptr: ?*NezConsole, button_index: u8) callconv(.c) bool {
    if (console_ptr) |ptr| {
        const cons: *nes.Console = @ptrCast(@alignCast(ptr));
        if (button_index < 8) {
            return cons.controller.buttons[button_index];
        }
    }
    return false;
}

// ============================================================================
// PAUSE/RESUME
// ============================================================================

export fn nez_is_paused(console_ptr: ?*NezConsole) callconv(.c) bool {
    if (console_ptr) |ptr| {
        const cons: *nes.Console = @ptrCast(@alignCast(ptr));
        return cons.is_paused;
    }
    return false;
}

export fn nez_set_pause(console_ptr: ?*NezConsole, paused: bool) callconv(.c) void {
    if (console_ptr) |ptr| {
        const cons: *nes.Console = @ptrCast(@alignCast(ptr));
        cons.is_paused = paused;
    }
}

// ============================================================================
// DEBUG UTILITIES
// ============================================================================

export fn nez_cpu_get_pc(console_ptr: ?*NezConsole) callconv(.c) u16 {
    if (console_ptr) |ptr| {
        const cons: *nes.Console = @ptrCast(@alignCast(ptr));
        return cons.cpu.PC;
    }
    return 0;
}

export fn nez_cpu_get_registers(console_ptr: ?*NezConsole) callconv(.c) CpuRegisters {
    if (console_ptr) |ptr| {
        const cons: *nes.Console = @ptrCast(@alignCast(ptr));
        return .{
            .a = cons.cpu.A,
            .x = cons.cpu.X,
            .y = cons.cpu.Y,
            .s = cons.cpu.S,
            .pc = cons.cpu.PC,
            .p = @bitCast(cons.cpu.StatusRegister),
        };
    }
    return .{ .a = 0, .x = 0, .y = 0, .s = 0, .pc = 0, .p = 0 };
}

export fn nez_debug_oam(console_ptr: ?*NezConsole) callconv(.c) [*]const u8 {
    if (console_ptr) |ptr| {
        const cons: *nes.Console = @ptrCast(@alignCast(ptr));
        return &cons.ppu.oam;
    }
    return undefined;
}

export fn nez_debug_sprite_size(console_ptr: ?*NezConsole) callconv(.c) u8 {
    if (console_ptr) |ptr| {
        const cons: *nes.Console = @ptrCast(@alignCast(ptr));
        return if (cons.ppu.ppu_ctrl.sprite_is_8x16) 16 else 8;
    }
    return 8;
}
