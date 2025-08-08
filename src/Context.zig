const Self = @This();

const std = @import("std");
const assert = std.debug.assert;

const Span = @import("Span.zig");

filepath: []const u8,
text: []const u8,

pub fn startingLineOf(self: *const Self, span: Span) usize {
    assert(span.end() < self.text.len);

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
    assert(span.end() < self.text.len);
    for (span.offset..span.end()) |i| {
        if (self.text[i] == '\n') {
            return true;
        }
    }
    return false;
}

pub fn getSingleLine(self: *const Self, index: usize) Span {
    return self.getLeftCharacters(index).join(self.getRightCharacters(index));
}

pub fn getLeftCharacters(self: *const Self, index: usize) Span {
    assert(index < self.text.len);

    var start = index;
    while (start > 0) : (start -= 1) {
        if (self.text[start - 1] == '\n') {
            break;
        }
    }
    while (start < index) : (start += 1) {
        if (!std.ascii.isWhitespace(self.text[start])) {
            break;
        }
    }

    return Span.fromBounds(start, index);
}

pub fn getRightCharacters(self: *const Self, index: usize) Span {
    assert(index < self.text.len);

    var end = index;
    while (end < self.text.len) : (end += 1) {
        if (self.text[end] == '\n') {
            break;
        }
    }
    while (end > index) : (end -= 1) {
        if (!std.ascii.isWhitespace(self.text[end - 1])) {
            break;
        }
    }

    return Span.fromBounds(index, end);
}
