const Self = @This();

codepoint: u21,

pub const Kind = enum {
    Atomic,
    Combining,
    Whitespace,
    Control,
};

pub fn from(codepoint: u21) Self {
    return .{ .codepoint = codepoint };
}

pub fn kind(self: *const Self) Kind {
    return switch (self.codepoint) {
        ' ', '\t'...'\r' => .Whitespace,
        0x00...0x08, 0x0e...0x1f, 0x7f => .Control,
        '\\', '.', ',', ';', '(', ')', '[', ']', '{', '}' => .Atomic,
        else => .Combining,
    };
}

pub fn isWhitespace(self: *const Self) bool {
    return self.kind() == .Whitespace;
}
pub fn isAtomic(self: *const Self) bool {
    return self.kind() == .Atomic;
}
pub fn isLinebreak(self: *const Self) bool {
    return self.codepoint == '\n';
}
