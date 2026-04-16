const std = @import("std");
const mapper_mod = @import("./mapper.zig");
const Mapper = mapper_mod.Mapper;
const Cart = @import("../cart.zig").Cart;
const CPU = @import("../cpu.zig").CPU;
const PPU = @import("../ppu/ppu.zig").PPU;

/// Mapper 40 — SMB2j (Super Mario Bros. 2 Japanese FDS port)
/// PRG layout: $6000=bank6, $8000=bank4, $A000=bank5, $C000=switchable, $E000=bank7
/// IRQ: cycle-based, fires every 4096*3 CPU cycles.
/// Write $8000: disable IRQ, $A000: enable IRQ, $E000: select bank at $C000.
const Self = @This();

cart: *Cart,
ppu: *PPU,
cpu: *CPU,
mapper: Mapper,
bank: u8 = 0,
cycles: i32 = -1,
has_chr_ram: bool,

fn read(m: *Mapper, addr: u16) u8 {
    const self: *Self = @fieldParentPtr("mapper", m);
    if (addr < 0x2000) {
        const chr = if (self.has_chr_ram) self.cart.chr_ram else self.cart.chr_rom;
        if (addr < chr.len) return chr[addr];
        return 0;
    }
    return switch (addr) {
        0x6000...0x7FFF => self.cart.prg_rom[0x2000 * 6 + (addr - 0x6000)],
        0x8000...0x9FFF => self.cart.prg_rom[0x2000 * 4 + (addr - 0x8000)],
        0xA000...0xBFFF => self.cart.prg_rom[0x2000 * 5 + (addr - 0xA000)],
        0xC000...0xDFFF => self.cart.prg_rom[@as(usize, self.bank) * 0x2000 + (addr - 0xC000)],
        0xE000...0xFFFF => self.cart.prg_rom[0x2000 * 7 + (addr - 0xE000)],
        else => 0,
    };
}

fn write(m: *Mapper, addr: u16, value: u8) void {
    const self: *Self = @fieldParentPtr("mapper", m);
    if (addr < 0x2000) {
        if (self.has_chr_ram) self.cart.chr_ram[addr] = value;
        return;
    }
    switch (addr) {
        0x8000...0x9FFF => {
            self.cycles = -1; // disable IRQ
        },
        0xA000...0xBFFF => {
            self.cycles = 0; // enable IRQ
        },
        0xE000...0xFFFF => {
            self.bank = value;
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

fn step(m: *Mapper) void {
    const self: *Self = @fieldParentPtr("mapper", m);
    if (self.cycles < 0) return;
    self.cycles += 1;
    if (self.cycles == 4096 * 3) {
        self.cycles = 0;
        self.cpu.interrupt_pending = .irq;
    }
}

pub fn init(cart: *Cart, ppu: *PPU, cpu: *CPU) Self {
    var self = Self{
        .cart = cart,
        .ppu = ppu,
        .cpu = cpu,
        .mapper = Mapper.init(read, write, ppuRead, ppuWrite, step),
        .has_chr_ram = cart.header.chr_rom_count == 0,
    };
    self.mapper.ppu_mirror_mode = if (cart.header.flags_6.mirroring_is_vertical)
        .vertical
    else
        .horizontal;
    return self;
}
