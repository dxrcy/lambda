const Self = @This();
const std = @import("std");

const Char = @import("Char.zig");

slice: []const u8,
/// Byte index.
index: usize,

pub fn new(slice: []const u8) Self {
    return .{
        .slice = slice,
        .index = 0,
    };
}

pub fn next(self: *Self) ?Char {
    const char = self.peek() orelse return null;
    self.index += char.length;
    return char;
}

pub fn peek(self: *const Self) ?Char {
    if (self.isEnd()) {
        return null;
    }
    // TODO(feat): Handle gracefully
    const char = Char.fromSliceStart(self.slice) catch |err| {
        std.debug.panic("utf8 error: {}", .{err});
    };
    return char;
}

pub fn isEnd(self: *const Self) bool {
    return self.index >= self.slice.len;
}
