const Self = @This();

const std = @import("std");
const assert = std.debug.assert;

const Span = @import("../Span.zig");

// TODO: Increase history size
const HISTORY_SIZE = 4;

items: [HISTORY_SIZE]Span,
index: usize,
length: usize,

pub fn new() Self {
    return Self{
        .items = undefined,
        .index = 0,
        .length = 0,
    };
}

pub fn append(self: *Self, span: Span) void {
    // TODO: Shift items back when array full
    assert(self.length < HISTORY_SIZE);

    self.items[self.length] = span;
    self.index = self.length;
    self.length += 1;
    // `index` is irrelevant here, it should be reassigned before next use
}

/// Assumes `self.index` is valid.
pub fn getActive(self: *const Self) []const u8 {
    assert(self.index < self.length);
    assert(self.length <= HISTORY_SIZE);
    return self.items[self.index].string();
}
