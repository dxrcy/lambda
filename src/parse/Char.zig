const Self = @This();

const std = @import("std");

value: u8,

pub const Kind = enum {
    Atomic,
    Combining,
    Whitespace,
    Control,
    NonAscii,
};

pub fn new(value: u8) Self {
    std.debug.assert(value != '_');
    return .{ .value = value };
}

pub fn kind(self: *const Self) Kind {
    return switch (self.value) {
        ' ', '\t'...'\r' => .Whitespace,
        0x00...0x08, 0x0e...0x1f, 0x7f => .Control,
        '\\', '.', ',', ';', '(', ')', '[', ']', '{', '}' => .Atomic,
        else => |char| if (char > 0x80) .NonAscii else .Combining,
    };
}

pub fn isWhitespace(self: *const Self) bool {
    return self.kind() == .Whitespace;
}
pub fn isAtomic(self: *const Self) bool {
    return self.kind() == .Atomic;
}
pub fn isLinebreak(self: *const Self) bool {
    return self.value == '\n';
}
