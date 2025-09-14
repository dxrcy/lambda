const Self = @This();

const std = @import("std");
const assert = std.debug.assert;

const MAX_LENGTH = 256;

buffer: [MAX_LENGTH]u8,
length: usize,

pub fn new() Self {
    return Self{
        .buffer = undefined,
        .length = 0,
    };
}

pub fn get(self: *const Self) []const u8 {
    return self.buffer[0..self.length];
}

pub fn clear(self: *Self) void {
    self.length = 0;
}

pub fn insert(self: *Self, byte: u8, position: usize) void {
    if (position >= MAX_LENGTH) {
        return;
    }

    // Shift characters up
    if (self.length > 0) {
        var i: usize = if (self.length >= MAX_LENGTH)
            MAX_LENGTH - 1
        else
            self.length;
        while (i > position) : (i -= 1) {
            self.buffer[i] = self.buffer[i - 1];
        }
    }

    self.buffer[position] = byte;
    // Cut off any overflowing characters
    if (self.length + 1 <= MAX_LENGTH) {
        self.length += 1;
    }
}

pub fn remove(self: *Self, position: usize) void {
    if (self.length == 0 or position == 0) {
        return;
    }

    // Shift characters down
    if (position < self.length) {
        for (position..self.length) |i| {
            self.buffer[i - 1] = self.buffer[i];
        }
    }

    self.length -= 1;
}

pub fn copyFrom(self: *Self, string: []const u8) void {
    for (string, 0..) |byte, i| {
        self.buffer[i] = byte;
    }
    self.length = string.len;
}
