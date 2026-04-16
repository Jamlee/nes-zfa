const std = @import("std");
const mapper_mod = @import("./mapper.zig");
const Mapper = mapper_mod.Mapper;
const Cart = @import("../cart.zig").Cart;
const CPU = @import("../cpu.zig").CPU;
const PPU = @import("../ppu/ppu.zig").PPU;

/// Mapper 4 — MMC3 / TxROM
/// The most common mapper for later NES games.
/// Supports: 8KB PRG bank switching (2 switchable + 2 fixed),
///           1KB CHR bank switching (8 banks),
///           dynamic mirroring,
///           scanline-based IRQ counter.
/// Used by: Super Mario Bros. 3, Kirby's Adventure, Mega Man 3-6,
///          Castlevania III, The Legend of Zelda (some versions), etc.
const Self = @This();

const PrgBankSize: usize = 0x2000; // 8KB
const ChrBankSize: usize = 0x0400; // 1KB

cart: *Cart,
ppu: *PPU,
cpu: *CPU,
mapper: Mapper,

// Internal registers
register: u8 = 0, // bank select register
registers: [8]u8 = .{0} ** 8,
prg_mode: u8 = 0,
chr_mode: u8 = 0,

// Bank offsets (pre-computed for fast access)
prg_offsets: [4]usize = .{0} ** 4,
chr_offsets: [8]usize = .{0} ** 8,

// IRQ
reload: u8 = 0,
counter: u8 = 0,
irq_enable: bool = false,

has_chr_ram: bool,

fn prgBankOffset(cart: *Cart, index: i32) usize {
    var i = index;
    const bank_count: i32 = @as(i32, @intCast(cart.prg_rom.len / PrgBankSize));
    if (i >= 0x80) i -= 0x100;
    i = @mod(i, bank_count);
    var offset: i32 = i * @as(i32, @intCast(PrgBankSize));
    if (offset < 0) offset += @intCast(cart.prg_rom.len);
    return @intCast(offset);
}

fn chrBankOffset(cart: *Cart, index: i32) usize {
    var i = index;
    const bank_count: i32 = @as(i32, @intCast(cart.chr_rom.len / ChrBankSize));
    if (i >= 0x80) i -= 0x100;
    i = @mod(i, bank_count);
    var offset: i32 = i * @as(i32, @intCast(ChrBankSize));
    if (offset < 0) offset += @intCast(cart.chr_rom.len);
    return @intCast(offset);
}

fn updateOffsets(self: *Self) void {
    switch (self.prg_mode) {
        0 => {
            self.prg_offsets[0] = prgBankOffset(self.cart, self.registers[6]);
            self.prg_offsets[1] = prgBankOffset(self.cart, self.registers[7]);
            self.prg_offsets[2] = prgBankOffset(self.cart, -2);
            self.prg_offsets[3] = prgBankOffset(self.cart, -1);
        },
        1 => {
            self.prg_offsets[0] = prgBankOffset(self.cart, -2);
            self.prg_offsets[1] = prgBankOffset(self.cart, self.registers[7]);
            self.prg_offsets[2] = prgBankOffset(self.cart, self.registers[6]);
            self.prg_offsets[3] = prgBankOffset(self.cart, -1);
        },
        else => {},
    }

    if (self.has_chr_ram) return; // CHR RAM: no bank switching

    switch (self.chr_mode) {
        0 => {
            self.chr_offsets[0] = chrBankOffset(self.cart, self.registers[0] & 0xFE);
            self.chr_offsets[1] = chrBankOffset(self.cart, self.registers[0] | 0x01);
            self.chr_offsets[2] = chrBankOffset(self.cart, self.registers[1] & 0xFE);
            self.chr_offsets[3] = chrBankOffset(self.cart, self.registers[1] | 0x01);
            self.chr_offsets[4] = chrBankOffset(self.cart, self.registers[2]);
            self.chr_offsets[5] = chrBankOffset(self.cart, self.registers[3]);
            self.chr_offsets[6] = chrBankOffset(self.cart, self.registers[4]);
            self.chr_offsets[7] = chrBankOffset(self.cart, self.registers[5]);
        },
        1 => {
            self.chr_offsets[0] = chrBankOffset(self.cart, self.registers[2]);
            self.chr_offsets[1] = chrBankOffset(self.cart, self.registers[3]);
            self.chr_offsets[2] = chrBankOffset(self.cart, self.registers[4]);
            self.chr_offsets[3] = chrBankOffset(self.cart, self.registers[5]);
            self.chr_offsets[4] = chrBankOffset(self.cart, self.registers[0] & 0xFE);
            self.chr_offsets[5] = chrBankOffset(self.cart, self.registers[0] | 0x01);
            self.chr_offsets[6] = chrBankOffset(self.cart, self.registers[1] & 0xFE);
            self.chr_offsets[7] = chrBankOffset(self.cart, self.registers[1] | 0x01);
        },
        else => {},
    }
}

fn read(m: *Mapper, addr: u16) u8 {
    const self: *Self = @fieldParentPtr("mapper", m);
    return switch (addr) {
        0x6000...0x7FFF => self.cart.prg_ram[addr - 0x6000],
        0x8000...0xFFFF => {
            const rel = addr - 0x8000;
            const bank: usize = rel / PrgBankSize;
            const offset: usize = rel % PrgBankSize;
            const abs_idx = self.prg_offsets[bank] + offset;
            if (abs_idx < self.cart.prg_rom.len) return self.cart.prg_rom[abs_idx];
            return 0;
        },
        else => 0,
    };
}

fn write(m: *Mapper, addr: u16, value: u8) void {
    const self: *Self = @fieldParentPtr("mapper", m);
    switch (addr) {
        0x6000...0x7FFF => self.cart.prg_ram[addr - 0x6000] = value,
        0x8000...0x9FFF => {
            if (addr % 2 == 0) {
                // Bank select
                self.prg_mode = (value >> 6) & 1;
                self.chr_mode = (value >> 7) & 1;
                self.register = value & 7;
                self.updateOffsets();
            } else {
                // Bank data
                self.registers[self.register] = value;
                self.updateOffsets();
            }
        },
        0xA000...0xBFFF => {
            if (addr % 2 == 0) {
                // Mirror
                self.mapper.ppu_mirror_mode = if (value & 1 != 0) .horizontal else .vertical;
            }
            // else: PRG RAM protect (ignored for now)
        },
        0xC000...0xDFFF => {
            if (addr % 2 == 0) {
                self.reload = value;
            } else {
                // IRQ reload: clear counter
                self.counter = 0;
            }
        },
        0xE000...0xFFFF => {
            if (addr % 2 == 0) {
                self.irq_enable = false;
            } else {
                self.irq_enable = true;
            }
        },
        else => {},
    }
}

fn ppuRead(m: *Mapper, addr: u16) u8 {
    const self: *Self = @fieldParentPtr("mapper", m);
    if (addr < 0x2000) {
        if (self.has_chr_ram) {
            if (addr < self.cart.chr_ram.len) return self.cart.chr_ram[addr];
            return 0;
        }
        const bank: usize = addr / ChrBankSize;
        const offset: usize = addr % ChrBankSize;
        const abs_idx = self.chr_offsets[bank] + offset;
        if (abs_idx < self.cart.chr_rom.len) return self.cart.chr_rom[abs_idx];
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

/// Scanline-based IRQ: called every CPU cycle.
/// The MMC3 IRQ counter is clocked at PPU cycle 280 of each visible scanline.
fn step(m: *Mapper) void {
    const self: *Self = @fieldParentPtr("mapper", m);
    const ppu = self.ppu;

    // Only clock on PPU cycle 280
    if (ppu.cycle != 280) return;
    if (ppu.scanline > 239 and ppu.scanline < 261) return;
    // Skip if rendering is off
    if (!ppu.ppu_mask.draw_bg and !ppu.ppu_mask.draw_sprites) return;

    // Handle scanline IRQ
    if (self.counter == 0) {
        self.counter = self.reload;
    } else {
        self.counter -= 1;
        if (self.counter == 0 and self.irq_enable) {
            self.cpu.interrupt_pending = .irq;
        }
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

    // Initialize default bank offsets
    self.prg_offsets[0] = prgBankOffset(cart, 0);
    self.prg_offsets[1] = prgBankOffset(cart, 1);
    self.prg_offsets[2] = prgBankOffset(cart, -2);
    self.prg_offsets[3] = prgBankOffset(cart, -1);

    return self;
}
