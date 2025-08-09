const Self = @This();

const std = @import("std");
const assert = std.debug.assert;

const Context = @import("Context.zig");

offset: usize,
length: usize,

pub fn new(offset: usize, length: usize) Self {
    return .{
        .offset = offset,
        .length = length,
    };
}

pub fn fromBounds(start: usize, span_end: usize) Self {
    return .{
        .offset = start,
        .length = span_end - start,
    };
}

/// Spans must be in-order and non-overlapping.
pub fn between(left: Self, right: Self) Self {
    assert(left.end() <= right.offset);
    return .{
        .offset = left.end(),
        .length = right.offset - left.end(),
    };
}

/// Spans must be in-order and non-overlapping.
pub fn join(left: Self, right: Self) Self {
    assert(left.end() <= right.offset);
    return .{
        .offset = left.offset,
        .length = right.end() - left.offset,
    };
}

pub fn end(self: Self) usize {
    return self.offset + self.length;
}

// TODO(refactor): Rename `addOffset`
pub fn withOffset(self: Self, offset: usize) Self {
    return .{
        .offset = self.offset + offset,
        .length = self.length,
    };
}

pub fn in(self: *const Self, context: *const Context) []const u8 {
    return context.text[self.offset..][0..self.length];
}
