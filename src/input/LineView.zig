const Self = @This();

const std = @import("std");
const assert = std.debug.assert;

const LineBuffer = @import("LineBuffer.zig");

cursor: usize,
data: union(enum) {
    slice: []const u8,
    buffer: *LineBuffer,
},

pub fn fromSlice(slice: []const u8) Self {
    return Self{
        .data = .{ .slice = slice },
        .cursor = slice.len,
    };
}

pub fn fromBuffer(line: *LineBuffer) Self {
    return Self{
        .data = .{ .buffer = line },
        .cursor = line.length,
    };
}

pub fn seek(self: *Self, direction: enum { left, right }) void {
    switch (direction) {
        .left => if (self.cursor > 0) {
            self.cursor -= 1;
        },
        .right => if (self.cursor < self.length()) {
            self.cursor += 1;
        },
    }
}

pub fn seekTo(self: *Self, position: usize) void {
    assert(position <= self.length());
    self.cursor = position;
}

pub fn clear(self: *Self) void {
    self.unwrapBuffer().clear();
    self.cursor = 0;
}

pub fn insert(self: *Self, byte: u8) void {
    if (self.unwrapBuffer().insert(byte, self.cursor)) {
        self.cursor += 1;
    }
}

pub fn remove(self: *Self) void {
    self.unwrapBuffer().remove(self.cursor);
    self.cursor -|= 1;
}

pub fn get(self: *const Self) []const u8 {
    return switch (self.data) {
        .slice => |slice| slice,
        .buffer => |buffer| buffer.buffer[0..buffer.length],
    };
}

fn length(self: *const Self) usize {
    return switch (self.data) {
        .slice => |slice| slice.len,
        .buffer => |buffer| buffer.length,
    };
}

pub fn isBuffer(self: *const Self) bool {
    return switch (self.data) {
        .buffer => true,
        .slice => false,
    };
}

/// Assumes `self.data` is kind `buffer`.
fn unwrapBuffer(self: *Self) *LineBuffer {
    return switch (self.data) {
        .buffer => |buffer| buffer,
        .slice => unreachable,
    };
}
