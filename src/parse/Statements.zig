const Self = @This();

const std = @import("std");
const assert = std.debug.assert;

const Span = @import("../Span.zig");

// TODO(refactor): Use `Context`
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
    if (self.peekChar() == null) {
        return null;
    }

    const start = self.index;
    self.advanceUntilNextLine();
    // Include all following lines which are empty or begin with whitespace
    while (self.peekChar()) |char| {
        if (isLinebreak(char)) {
            self.index += 1;
            continue;
        }
        if (isWhitespace(char)) {
            self.index += 1;
            self.advanceUntilNextLine();
            continue;
        }
        break; // New statement
    }

    var end = self.index - 1;
    while (end > 0 and isWhitespace(self.text[end - 1])) {
        end -= 1;
    }
    assert(end > 0);

    return Span.fromBounds(start, end);
}

fn peekChar(self: *const Self) ?u8 {
    if (self.index >= self.text.len) {
        return null;
    }
    return self.text[self.index];
}

fn advanceUntilNonwhitespace(self: *Self) void {
    while (self.peekChar()) |char| {
        if (!isWhitespace(char)) {
            break;
        }
        self.index += 1;
    }
}

fn advanceUntilNextLine(self: *Self) void {
    while (self.peekChar()) |char| {
        self.index += 1;
        if (isLinebreak(char)) {
            break;
        }
    }
}

fn isLinebreak(char: u8) bool {
    return char == '\n';
}

fn isWhitespace(char: u8) bool {
    return switch (char) {
        ' ', '\t'...'\r' => true,
        else => false,
    };
}
