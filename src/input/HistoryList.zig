const Self = @This();

const std = @import("std");
const assert = std.debug.assert;

const TextStore = @import("../TextStore.zig");
const SourceSpan = TextStore.SourceSpan;

const HISTORY_SIZE = 32;

// PERF: Use ring buffer

items: [HISTORY_SIZE]SourceSpan,
length: usize,

pub fn new() Self {
    return Self{
        .items = undefined,
        .length = 0,
    };
}

pub fn get(self: *const Self, back_index: usize) SourceSpan {
    assert(back_index < self.length);
    assert(self.length <= HISTORY_SIZE);
    const index = self.length - back_index - 1;
    return self.items[index];
}

pub fn append(self: *Self, span: SourceSpan) void {
    if (self.length < HISTORY_SIZE) {
        self.items[self.length] = span;
        self.length += 1;
        return;
    }

    // Shift items down
    for (0..self.length - 1) |i| {
        self.items[i] = self.items[i + 1];
    }
    self.items[self.length - 1] = span;
}
