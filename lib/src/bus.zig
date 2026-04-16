const Cart = @import("./cart.zig").Cart;
const mapper_mod = @import("./mappers/mapper.zig");
const NROM = @import("./mappers/nrom.zig").NROM;
const MMC1 = @import("./mappers/mmc1.zig").MMC1;
const UxROM = @import("./mappers/UxROM.zig");
const CNROM = @import("./mappers/cnrom.zig");
const MMC3 = @import("./mappers/mmc3.zig");
const AxROM = @import("./mappers/axrom.zig");
const Mapper40 = @import("./mappers/mapper40.zig");
const Mapper225 = @import("./mappers/mapper225.zig");
const std = @import("std");
const Gamepad = @import("./gamepad.zig");

const PPU = @import("./ppu/ppu.zig").PPU;
const CPU = @import("./cpu.zig").CPU;
const MapperKind = mapper_mod.MapperKind;
const Mapper = mapper_mod.Mapper;
const Allocator = std.mem.Allocator;
const APU = @import("./apu/apu.zig");

pub const Bus = struct {
    const Self = @This();

    readFn: *const fn (*Self, u16) u8,
    writeFn: *const fn (*Self, u16, u8) void,

    pub inline fn read(self: *Self, addr: u16) u8 {
        return self.readFn(self, addr);
    }

    pub inline fn write(self: *Self, addr: u16, val: u8) void {
        return self.writeFn(self, addr, val);
    }
};

/// A dummy bus used for testing with the ProcessorTests test suite.
pub const TestBus = struct {
    const Self = @This();
    mem: [std.math.maxInt(u16) + 1]u8 = .{0} ** (std.math.maxInt(u16) + 1),
    bus: Bus,

    fn write(i_bus: *Bus, addr: u16, val: u8) void {
        const self: *Self = @fieldParentPtr("bus", i_bus);
        self.mem[addr] = val;
    }

    fn read(i_bus: *Bus, addr: u16) u8 {
        const self: *Self = @fieldParentPtr("bus", i_bus);
        return self.mem[addr];
    }

    pub fn new() TestBus {
        return .{
            .bus = .{
                .readFn = read,
                .writeFn = write,
            },
        };
    }
};

pub const NESBus = struct {
    const Self = @This();
    const w_ram_size = 0x800;
    bus: Bus,
    mapper: *Mapper,
    apu: *APU,
    ppu: *PPU,
    cpu: *CPU,
    cart: *Cart,
    allocator: Allocator,
    controller: *Gamepad,
    controller2: *Gamepad,

    // holds a reference to the CPU's 0x800 bytes of RAM.
    ram: [w_ram_size]u8 = .{0} ** w_ram_size,

    fn busRead(i_bus: *Bus, addr: u16) u8 {
        var self: *Self = @fieldParentPtr("bus", i_bus);

        return switch (addr) {
            0...0x1FFF => self.ram[addr % w_ram_size],
            0x2000...0x3FFF => self.ppu.readRegister(addr),
            0x4000...0x4015 => 0, // TODO
            0x4016 => self.controller.read(),
            0x4017 => self.controller2.read(),
            0x4018...0x401F => 0, // TODO
            else => self.mapper.read(addr),
        };
    }

    fn busWrite(i_bus: *Bus, addr: u16, val: u8) void {
        var self: *Self = @fieldParentPtr("bus", i_bus);
        switch (addr) {
            // CPU RAM
            0...0x1FFF => self.ram[addr % w_ram_size] = val,

            // PPU Registers
            0x2000...0x3FFF => self.ppu.writeRegister(addr, val),

            // APU Pulse Channel #1
            0x4000 => self.apu.pulse_1.writeControlReg(@bitCast(val)),
            0x4001 => self.apu.pulse_1.sweep.config = (@bitCast(val)),
            0x4002 => self.apu.pulse_1.writeTimerLo(val),
            0x4003 => self.apu.pulse_1.writeTimerHi(val),

            // APU Pulse Channel #2
            0x4004 => self.apu.pulse_2.writeControlReg(@bitCast(val)),
            0x4005 => self.apu.pulse_2.sweep.config = (@bitCast(val)),
            0x4006 => self.apu.pulse_2.writeTimerLo(val),
            0x4007 => self.apu.pulse_2.writeTimerHi(val),

            // TODO: triangle, noise, and DMC channels.
            0x4008 => {},
            0x4009 => {},
            0x400A => {},
            0x400B => {},
            0x400C => {},
            0x400D => {},
            0x400E => {},
            0x400F => {},
            0x4010 => {},
            0x4011 => {},
            0x4012 => {},
            0x4013 => {},
            0x4014 => self.ppu.writeOAMDMA(val),
            0x4015 => {},
            0x4016 => {
                self.controller.write(val);
                self.controller2.write(val);
            },
            0x4017 => self.apu.writeFrameCounter(val),
            0x4018...0x401F => {}, // TODO
            else => self.mapper.write(addr, val),
        }
    }

    /// Create a mapper based on the cart's configuration.
    fn createMapper(allocator: Allocator, cart: *Cart, ppu: *PPU, cpu: *CPU) !*Mapper {
        const kind = cart.header.getMapper();
        switch (kind) {
            .nrom => {
                var nrom = try allocator.create(NROM);
                nrom.* = NROM.init(cart, ppu);
                return &nrom.mapper;
            },

            .mmc1 => {
                var mmc1 = try allocator.create(MMC1);
                mmc1.* = MMC1.init(cart, ppu);
                return &mmc1.mapper;
            },

            .UxROM => {
                var uxROM = try allocator.create(UxROM);
                uxROM.* = UxROM.init(cart, ppu);
                return &uxROM.mapper;
            },

            .cnrom => {
                var cnrom = try allocator.create(CNROM);
                cnrom.* = CNROM.init(cart, ppu);
                return &cnrom.mapper;
            },

            .mmc3 => {
                var mmc3 = try allocator.create(MMC3);
                mmc3.* = MMC3.init(cart, ppu, cpu);
                return &mmc3.mapper;
            },

            .axrom => {
                var axrom = try allocator.create(AxROM);
                axrom.* = AxROM.init(cart, ppu);
                return &axrom.mapper;
            },

            .mapper40 => {
                var m40 = try allocator.create(Mapper40);
                m40.* = Mapper40.init(cart, ppu, cpu);
                return &m40.mapper;
            },

            .mapper225 => {
                var m225 = try allocator.create(Mapper225);
                m225.* = Mapper225.init(cart, ppu);
                return &m225.mapper;
            },
        }
    }

    /// Create a new Bus.
    /// Both `cart` and `ppu` are non-owning pointers.
    pub fn init(allocator: Allocator, cart: *Cart, apu: *APU, ppu: *PPU, cpu: *CPU, controller: *Gamepad, controller2: *Gamepad) !Self {
        return .{
            .allocator = allocator,
            .cart = cart,
            .ppu = ppu,
            .apu = apu,
            .cpu = cpu,
            .bus = .{
                .readFn = busRead,
                .writeFn = busWrite,
            },
            .mapper = try createMapper(allocator, cart, ppu, cpu),
            .controller = controller,
            .controller2 = controller2,
        };
    }

    pub fn deinit(self: *Self) void {
        switch (self.cart.header.getMapper()) {
            .nrom => {
                const nrom: *NROM = @fieldParentPtr("mapper", self.mapper);
                self.allocator.destroy(nrom);
            },

            .mmc1 => {
                const mmc1: *MMC1 = @fieldParentPtr("mapper", self.mapper);
                self.allocator.destroy(mmc1);
            },

            .UxROM => {
                const uxROM: *UxROM = @fieldParentPtr("mapper", self.mapper);
                self.allocator.destroy(uxROM);
            },

            .cnrom => {
                const cnrom: *CNROM = @fieldParentPtr("mapper", self.mapper);
                self.allocator.destroy(cnrom);
            },

            .mmc3 => {
                const mmc3: *MMC3 = @fieldParentPtr("mapper", self.mapper);
                self.allocator.destroy(mmc3);
            },

            .axrom => {
                const axrom: *AxROM = @fieldParentPtr("mapper", self.mapper);
                self.allocator.destroy(axrom);
            },

            .mapper40 => {
                const m40: *Mapper40 = @fieldParentPtr("mapper", self.mapper);
                self.allocator.destroy(m40);
            },

            .mapper225 => {
                const m225: *Mapper225 = @fieldParentPtr("mapper", self.mapper);
                self.allocator.destroy(m225);
            },
        }
    }
};
