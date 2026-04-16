const std = @import("std");
const mapper_mod = @import("./mapper.zig");
const Mapper = mapper_mod.Mapper;
const noopStep = mapper_mod.noopStep;
const Cart = @import("../cart.zig").Cart;
const PPU = @import("../ppu/ppu.zig").PPU;

/// Mapper 225 — 74x161x162xROM
/// Address-line controlled bank switching (no data bus used for bank selection).
/// Write $8000-$FFFF: the address itself encodes all bank info.
/// Used by some multi-cart boards.
/// Ref: https://wiki.nesdev.org/w/index.php/INES_Mapper_225
const Self = @This();

cart: *Cart,
ppu: *PPU,
mapper: Mapper,
has_chr_ram: bool,
chr_bank: usize = 0,
prg_bank1: usize = 0,
prg_bank2: usize = 0,
prg_banks: usize = 0,

fn read(m: *Mapper, addr: u16) u8 {
    const self: *Self = @fieldParentPtr("mapper", m);
    return switch (addr) {
        0x6000...0x7FFF => self.cart.prg_ram[addr - 0x6000],
        0x8000...0xBFFF => self.cart.prg_rom[self.prg_bank1 + (addr - 0x8000)],
        0xC000...0xFFFF => self.cart.prg_rom[self.prg_bank2 + (addr - 0xC000)],
        else => 0,
    };
}

fn write(m: *Mapper, addr: u16, value: u8) void {
    const self: *Self = @fieldParentPtr("mapper", m);
    switch (addr) {
        0x6000...0x7FFF => self.cart.prg_ram[addr - 0x6000] = value,
        0x8000...0xFFFF => {
            const a: usize = addr;
            const bank: usize = (a >> 14) & 1;
            self.chr_bank = ((a & 0x3F) | (bank << 6)) * 0x2000;
            const prg: usize = ((a >> 6) & 0x3F) | (bank << 6);
            const mode: usize = (a >> 12) & 1;
            if (mode == 1) {
                // 32KB mode
                self.prg_bank1 = (prg * 2) * 0x4000;
                self.prg_bank2 = self.prg_bank1 + 0x4000;
            } else {
                // 16KB mode
                self.prg_bank1 = prg * 0x4000;
                self.prg_bank2 = (prg + 1) * 0x4000;
            }
            // Mirroring
            const mirr: usize = (a >> 13) & 1;
            self.mapper.ppu_mirror_mode = if (mirr == 1) .horizontal else .vertical;
        },
        else => {},
    }
}

fn ppuRead(m: *Mapper, addr: u16) u8 {
    const self: *Self = @fieldParentPtr("mapper", m);
    if (addr < 0x2000) {
        const chr = if (self.has_chr_ram) self.cart.chr_ram else self.cart.chr_rom;
        const idx = self.chr_bank + addr;
        if (idx < chr.len) return chr[idx];
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
    const prg_banks: usize = cart.header.prg_rom_banks;
    var self = Self{
        .cart = cart,
        .ppu = ppu,
        .mapper = Mapper.init(read, write, ppuRead, ppuWrite, noopStep),
        .has_chr_ram = cart.header.chr_rom_count == 0,
        .prg_banks = prg_banks,
        .prg_bank2 = if (prg_banks >= 2) (prg_banks - 1) * 0x4000 else 0,
    };

    self.mapper.ppu_mirror_mode = if (cart.header.flags_6.mirroring_is_vertical)
        .vertical
    else
        .horizontal;

    return self;
}
