const Self = @This();

const std = @import("std");
const assert = std.debug.assert;
const unicode = std.unicode;

const TextStore = @import("../text/TextStore.zig");
const Source = TextStore.Source;
const SourceSpan = TextStore.SourceSpan;

const model = @import("../model.zig");
const Term = model.Term;

const TokenChar = @import("TokenChar.zig");
const Token = @import("Token.zig");

char_iter: unicode.Utf8Iterator,
statement: SourceSpan,
text: *const TextStore,

pub fn new(statement: SourceSpan, text: *const TextStore) Self {
    // Text should have already been checked as valid UTF-8
    // TODO: Panic on error
    const view = unicode.Utf8View.init(statement.in(text)) catch unreachable;
    return .{
        .char_iter = view.iterator(),
        .statement = statement,
        .text = text,
    };
}

pub fn next(self: *Self) ?Token {
    while (true) {
        const span = self.nextTokenSpan() orelse
            return null;
        if (std.mem.startsWith(u8, span.in(self.text), "--")) {
            self.advanceUntilNextLine();
            continue;
        }
        return Token.new(span, self.text);
    }
}

/// Byte index *within statement*.
fn getIndex(self: *const Self) usize {
    return self.char_iter.i;
}

fn isEnd(self: *Self) bool {
    return self.char_iter.i >= self.char_iter.bytes.len;
}

fn peekChar(self: *Self) ?TokenChar {
    if (self.isEnd()) {
        return null;
    }

    const bytes = self.char_iter.peek(1);
    assert(bytes.len > 0 and bytes.len <= 4);

    const codepoint = unicode.utf8Decode(bytes) catch unreachable;
    return TokenChar.from(codepoint);
}

fn nextChar(self: *Self) ?TokenChar {
    const codepoint = self.char_iter.nextCodepoint() orelse return null;
    return TokenChar.from(codepoint);
}

/// Treats comment symbol (anything beginning with `--`) as a normal token.
fn nextTokenSpan(self: *Self) ?SourceSpan {
    self.advanceUntilNonwhitespace();
    if (self.isEnd()) {
        return null;
    }
    return self.tryAtomic() orelse self.expectCombination();
}

fn tryAtomic(self: *Self) ?SourceSpan {
    assert(!self.isEnd());

    const char = self.peekChar() orelse unreachable;
    assert(!char.isWhitespace());
    if (!char.isAtomic()) {
        return null;
    }

    const start = self.getIndex();
    _ = self.nextChar();

    return SourceSpan.fromBounds(start, self.getIndex(), self.statement.source)
        .addOffset(self.statement.free.offset);
}

fn expectCombination(self: *Self) SourceSpan {
    assert(!self.isEnd());

    const start = self.getIndex();
    const first = self.nextChar() orelse unreachable;
    assert(!first.isWhitespace());

    while (self.peekChar()) |char| {
        if (char.isWhitespace() or char.isAtomic()) {
            break;
        }
        _ = self.nextChar();
    }

    return SourceSpan.fromBounds(start, self.getIndex(), self.statement.source)
        .addOffset(self.statement.free.offset);
}

fn advanceUntilNonwhitespace(self: *Self) void {
    while (self.peekChar()) |char| {
        if (!char.isWhitespace()) {
            break;
        }
        _ = self.nextChar();
    }
}

fn advanceUntilNextLine(self: *Self) void {
    while (self.nextChar()) |char| {
        if (char.isLinebreak()) {
            break;
        }
    }
}
