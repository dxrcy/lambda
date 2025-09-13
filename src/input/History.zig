const Self = @This();

const std = @import("std");
const assert = std.debug.assert;

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const Span = @import("../Span.zig");

// TODO: Used fixed array
items: ArrayList(Span),
index: usize,
allocator: Allocator,

pub fn new(allocator: Allocator) Self {
    return Self{
        .items = ArrayList(Span).empty,
        .index = 0,
        .allocator = allocator,
    };
}

pub fn append(self: *Self, span: Span) Allocator.Error!void {
    try self.items.append(self.allocator, span);
}

/// Assumes `self.index` is valid.
pub fn getActive(self: *const Self) []const u8 {
    assert(self.index < self.items.items.len);
    return self.items.items[self.index].string();
}
