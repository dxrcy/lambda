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

pub fn fromBounds(start: usize, span_end: usize) Self {
    // FIXME: Should this be `<`?
    assert(start <= span_end);
    return .{
        .offset = start,
        .length = span_end - start,
    };
}

pub fn end(self: Self) usize {
    return self.offset + self.length;
}

pub fn addOffset(self: Self, offset: usize) Self {
    return .{
        .offset = self.offset + offset,
        .length = self.length,
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

/// Spans must be in-order and non-overlapping.
pub fn between(left: Self, right: Self) Self {
    assert(left.end() <= right.offset);
    return .{
        .offset = left.end(),
        .length = right.offset - left.end(),
    };
}

pub fn in(self: Self, text: []const u8) []const u8 {
    assert(self.offset < text.len);
    assert(self.offset + self.length <= text.len);
    return text[self.offset..][0..self.length];
}
