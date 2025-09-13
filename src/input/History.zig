const Self = @This();

const std = @import("std");
const assert = std.debug.assert;

const Span = @import("../Span.zig");

const HISTORY_SIZE = 32;

// PERF: Use ring buffer
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
    if (self.length >= HISTORY_SIZE) {
        // Shift items down
        for (0..self.length - 1) |i| {
            self.items[i] = self.items[i + 1];
        }
        self.items[self.length - 1] = span;
    } else {
        self.items[self.length] = span;
        self.length += 1;
    }

    self.index = self.length - 1;
}

/// Assumes `self.index` is valid.
pub fn getActive(self: *const Self) []const u8 {
    assert(self.index < self.length);
    assert(self.length <= HISTORY_SIZE);
    return self.items[self.index].string();
}

pub fn getLatest(self: *const Self) ?[]const u8 {
    assert(self.length <= HISTORY_SIZE);
    if (self.length == 0) {
        return null;
    }
    return self.items[self.length - 1].string();
}
