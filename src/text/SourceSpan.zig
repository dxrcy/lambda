const Self = @This();

const std = @import("std");
const assert = std.debug.assert;

const TextStore = @import("TextStore.zig");
const Source = TextStore.Source;
const FreeSpan = TextStore.FreeSpan;

free: FreeSpan,
source: Source,

pub fn new(offset: usize, length: usize, source: Source) Self {
    return .{
        .free = FreeSpan.new(offset, length),
        .source = source,
    };
}

pub fn fromBounds(start: usize, span_end: usize, source: Source) Self {
    return .{
        .free = FreeSpan.fromBounds(start, span_end),
        .source = source,
    };
}

pub fn addOffset(self: Self, offset: usize) Self {
    return .{
        .free = self.free.addOffset(offset),
        .source = self.source,
    };
}

/// Spans must be in-order, non-overlapping, and from the same source.
pub fn join(left: Self, right: Self) Self {
    assert(left.source.equals(right.source));
    return .{
        .free = left.free.join(right.free),
        .source = left.source,
    };
}

/// Spans must be in-order, non-overlapping, and from the same source.
pub fn between(left: Self, right: Self) Self {
    assert(left.source.equals(right.source));
    return .{
        .free = left.free.between(right.free),
        .source = left.source,
    };
}

pub fn in(self: Self, text: *const TextStore) []const u8 {
    return self.free.in(text.getSourceText(self.source));
}
