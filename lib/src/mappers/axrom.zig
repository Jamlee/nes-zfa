const std = @import("std");
const mapper_mod = @import("./mapper.zig");
const Mapper = mapper_mod.Mapper;
const Cart = @import("../cart.zig").Cart;
const CPU = @import("../cpu.zig").CPU;
const PPU = @import("../ppu/ppu.zig").PPU;

/// Mapper 7 — AxROM
/// 32KB PRG bank switching + single-screen mirroring.
/// Write $8000-$FFFF: bit 0-2 = PRG bank, bit 4 = mirror (Single0/Single1).
/// Used by games like Battletoads, Marble Madness, Solar Jetman, etc.
const Self = @This();

cart: *Cart,
ppu: *PPU,
mapper: Mapper,
has_chr_ram: bool,
prg_bank: u8 = 0,

fn read(m: *Mapper, addr: u16) u8 {
    const self: *Self = @fieldParentPtr("mapper", m);
    return switch (addr) {
        0x6000...0x7FFF => self.cart.prg_ram[addr - 0x6000],
        0x8000...0xFFFF => {
            const offset: usize = @as(usize, self.prg_bank) * 0x8000;
            return self.cart.prg_rom[offset + (addr - 0x8000)];
        },
        else => 0,
    };
}

fn write(m: *Mapper, addr: u16, value: u8) void {
    const self: *Self = @fieldParentPtr("mapper", m);
    switch (addr) {
        0x6000...0x7FFF => self.cart.prg_ram[addr - 0x6000] = value,
        0x8000...0xFFFF => {
            self.prg_bank = value & 0x07;
            if (value & 0x10 != 0) {
                self.mapper.ppu_mirror_mode = .one_screen_upper;
            } else {
                self.mapper.ppu_mirror_mode = .one_screen_lower;
            }
        },
        else => {},
    }
}

fn ppuRead(m: *Mapper, addr: u16) u8 {
    const self: *Self = @fieldParentPtr("mapper", m);
    if (addr < 0x2000) {
        const chr = if (self.has_chr_ram) self.cart.chr_ram else self.cart.chr_rom;
        if (addr < chr.len) return chr[addr];
        return 0;
    }
    if (addr < 0x3000) return self.ppu.readRAM(m.unmirror_nametable(addr));
    return self.ppu.readRAM(addr);
}

fn ppuWrite(m: *Mapper, addr: u16, value: u8) void {
    const self: *Self = @fieldParentPtr("mapper", m);
    if (addr < 0x2000) {
        if (self.has_chr_ram) self.cart.chr_ram[addr] = value;
        return;
    }
    if (addr < 0x3000) {
        self.ppu.writeRAM(m.unmirror_nametable(addr), value);
    } else {
        self.ppu.writeRAM(addr, value);
    }
}

pub fn init(cart: *Cart, ppu: *PPU) Self {
    var self = Self{
        .cart = cart,
        .ppu = ppu,
        .mapper = Mapper.init(read, write, ppuRead, ppuWrite, mapper_mod.noopStep),
        .has_chr_ram = cart.header.chr_rom_count == 0,
    };
    // AxROM defaults to single-screen lower
    self.mapper.ppu_mirror_mode = .one_screen_lower;
    return self;
}
