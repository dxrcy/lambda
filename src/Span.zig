const Self = @This();

const std = @import("std");
const assert = std.debug.assert;

offset: usize,
length: usize,

pub fn new(offset: usize, length: usize) Self {
    return .{
        .offset = offset,
        .length = length,
    };
}

pub fn fromBounds(start: usize, end: usize) Self {
    return .{
        .offset = start,
        .length = end - start,
    };
}

pub fn withOffset(self: Self, offset: usize) Self {
    return .{
        .offset = self.offset + offset,
        .length = self.length,
    };
}

/// Spans must be in-order and non-overlapping.
pub fn join(self: Self, other: Self) Self {
    // TODO(fix): This maybe should be `<=`
    assert(self.offset + self.length < other.offset);
    return .{
        .offset = self.offset,
        .length = other.offset - self.offset + other.length,
    };
}

pub fn in(self: *const Self, text: []const u8) []const u8 {
    return text[self.offset..][0..self.length];
}
