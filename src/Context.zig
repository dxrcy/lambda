const Self = @This();

const std = @import("std");
const assert = std.debug.assert;

const Span = @import("Span.zig");

filepath: []const u8,
text: []const u8,

pub fn startingLineOf(self: *const Self, span: Span) usize {
    assert(span.offset + span.length < self.text.len);

    var line: usize = 1;
    for (self.text, 0..) |char, i| {
        if (char == '\n') {
            line += 1;
        }
        if (i >= span.offset) {
            break;
        }
    }
    return line;
}

pub fn isMultiline(self: *const Self, span: Span) bool {
    assert(span.offset + span.length < self.text.len);
    for (0..span.length) |i| {
        if (self.text[span.offset + i] == '\n') {
            return true;
        }
    }
    return false;
}

pub fn getLeftCharacters(self: *const Self, span: Span) Span {
    assert(span.offset + span.length < self.text.len);

    var start = span.offset;
    while (start > 0) : (start -= 1) {
        if (self.text[start - 1] == '\n') {
            break;
        }
    }
    while (start < span.offset) : (start += 1) {
        if (!std.ascii.isWhitespace(self.text[start])) {
            break;
        }
    }

    return Span.fromBounds(start, span.offset);
}

pub fn getRightCharacters(self: *const Self, span: Span) Span {
    assert(span.offset + span.length < self.text.len);

    const span_end = span.offset + span.length;
    var end = span_end;
    while (end < self.text.len) : (end += 1) {
        if (self.text[end] == '\n') {
            break;
        }
    }
    while (end > span_end) : (end -= 1) {
        if (!std.ascii.isWhitespace(self.text[end])) {
            break;
        }
    }

    return Span.fromBounds(span_end, end);
}
