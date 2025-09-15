const Self = @This();

const std = @import("std");
const assert = std.debug.assert;

const Span = @import("../Span.zig");

const TextStore = @import("../TextStore.zig");
const Source = TextStore.Source;
const SourceSpan = TextStore.SourceSpan;

index: usize,
source: Source,
text: *const TextStore,

pub fn new(source: Source, text: *const TextStore) Self {
    return .{
        .index = 0,
        .source = source,
        .text = text,
    };
}

pub fn next(self: *Self) ?SourceSpan {
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
    while (end > 0 and isWhitespace(self.text.get(self.source, end - 1))) {
        end -= 1;
    }
    assert(end > 0);

    return SourceSpan.fromBounds(start, end, self.source);
}

fn peekChar(self: *const Self) ?u8 {
    if (self.index >= self.text.getSourceText(self.source).len) {
        return null;
    }
    return self.text.get(self.source, self.index);
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
