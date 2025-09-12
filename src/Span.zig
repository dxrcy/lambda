const Self = @This();

const std = @import("std");
const assert = std.debug.assert;

const Context = @import("Context.zig");

// TODO: Rename `Span`... `Source` ?

offset: usize,
length: usize,
context: *const Context,

pub fn new(offset: usize, length: usize, context: *const Context) Self {
    return .{
        .offset = offset,
        .length = length,
        .context = context,
    };
}

pub fn fromBounds(start: usize, span_end: usize, context: *const Context) Self {
    return .{
        .offset = start,
        .length = span_end - start,
        .context = context,
    };
}

/// Spans must be in-order and non-overlapping.
pub fn between(left: Self, right: Self) Self {
    assert(left.context == right.context);
    assert(left.end() <= right.offset);
    return .{
        .offset = left.end(),
        .length = right.offset - left.end(),
        .context = left.context,
    };
}

/// Spans must be in-order and non-overlapping.
pub fn join(left: Self, right: Self) Self {
    assert(left.context == right.context);
    assert(left.end() <= right.offset);
    return .{
        .offset = left.offset,
        .length = right.end() - left.offset,
        .context = left.context,
    };
}

pub fn end(self: Self) usize {
    return self.offset + self.length;
}

pub fn addOffset(self: Self, offset: usize) Self {
    return .{
        .offset = self.offset + offset,
        .length = self.length,
        .context = self.context,
    };
}

pub fn string(self: *const Self) []const u8 {
    return self.context.text[self.offset..][0..self.length];
}
