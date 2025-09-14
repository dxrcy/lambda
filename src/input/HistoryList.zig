const Self = @This();

const std = @import("std");
const assert = std.debug.assert;

const Span = @import("../Span.zig");

const HISTORY_SIZE = 32;

// PERF: Use ring buffer

items: [HISTORY_SIZE]Span,
length: usize,

pub fn new() Self {
    return Self{
        .items = undefined,
        .length = 0,
    };
}

pub fn get(self: *const Self, index: usize) []const u8 {
    assert(index < self.length);
    assert(self.length <= HISTORY_SIZE);
    return self.items[index].string();
}

pub fn append(self: *Self, span: Span) void {
    if (self.length < HISTORY_SIZE) {
        self.items[self.length] = span;
        self.length += 1;
    }

    // Shift items down
    for (0..self.length - 1) |i| {
        self.items[i] = self.items[i + 1];
    }
    self.items[self.length - 1] = span;
}
