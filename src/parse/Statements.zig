const Self = @This();

const std = @import("std");
const assert = std.debug.assert;

const Span = @import("../Span.zig");

text: []const u8,
index: usize,

pub fn new(text: []const u8) Self {
    return .{
        .text = text,
        .index = 0,
    };
}

pub fn next(self: *Self) ?Span {
    self.advanceUntilNonwhitespace();
    if (self.isEmpty()) {
        return null;
    }

    const start = self.index;
    self.advanceUntilLinebreak();
    // Include all following lines which are empty or begin with whitespace
    while (self.peekChar()) |char| {
        if (isLinebreak(char)) {
            self.index += 1;
            continue;
        }
        if (isAnyWhitespace(char)) {
            self.index += 1;
            self.advanceUntilLinebreak();
            continue;
        }
        break; // New statement
    }

    var end = self.index - 1;
    while (end > 0 and isAnyWhitespace(self.text[end - 1])) {
        end -= 1;
    }
    assert(end > 0);

    return Span.fromBounds(start, end);

    // return trimWhitespaceRight(self.text[start..self.index]);
}

fn advanceUntilNonwhitespace(self: *Self) void {
    while (self.peekChar()) |char| {
        if (!isAnyWhitespace(char)) {
            break;
        }
        self.index += 1;
    }
}

fn advanceUntilLinebreak(self: *Self) void {
    while (self.peekChar()) |char| {
        self.index += 1;
        if (isLinebreak(char)) {
            break;
        }
    }
}

fn trimWhitespaceRight(slice: []const u8) []const u8 {
    assert(slice.len > 0);
    assert(!isAnyWhitespace(slice[0]));
    var end = slice.len - 1;
    while (end > 0 and isAnyWhitespace(slice[end - 1])) {
        end -= 1;
    }
    assert(end > 0);
    return slice[0..end];
}

fn peekChar(self: *const Self) ?u8 {
    if (self.isEmpty()) {
        return null;
    }
    return self.text[self.index];
}

fn isEmpty(self: *const Self) bool {
    return self.index >= self.text.len;
}

fn isLinebreak(char: u8) bool {
    return char == '\n';
}

fn isAnyWhitespace(char: u8) bool {
    return switch (char) {
        ' ', '\t'...'\r' => true,
        else => false,
    };
}
