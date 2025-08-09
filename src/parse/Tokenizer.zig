const Self = @This();

const std = @import("std");
const assert = std.debug.assert;
const ArrayList = std.ArrayList;
const Utf8Iterator = std.unicode.Utf8Iterator;
const Utf8View = std.unicode.Utf8View;

const Context = @import("../Context.zig");
const Span = @import("../Span.zig");

const model = @import("../model.zig");
const Term = model.Term;

const TokenChar = @import("TokenChar.zig");
const Token = @import("Token.zig");

context: *const Context,
statement: Span,

char_iter: Utf8Iterator,

pub fn new(statement: Span, context: *const Context) Self {
    const view = Utf8View.init(statement.in(context)) catch {
        std.debug.panic("invalid utf8", .{});
    };
    return .{
        .context = context,
        .statement = statement,
        .char_iter = view.iterator(),
    };
}

pub fn next(self: *Self) ?Token {
    while (true) {
        const span = self.nextTokenSpan() orelse return null;
        if (std.mem.startsWith(u8, span.in(self.context), "--")) {
            self.advanceUntilNextLine();
            continue;
        }
        return Token.new(span, self.context);
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

    const codepoint = std.unicode.utf8Decode(bytes) catch unreachable;
    return TokenChar.from(codepoint);
}

fn nextChar(self: *Self) ?TokenChar {
    const codepoint = self.char_iter.nextCodepoint() orelse return null;
    return TokenChar.from(codepoint);
}

/// Treats comment symbol (anything beginning with `--`) as a normal token.
fn nextTokenSpan(self: *Self) ?Span {
    self.advanceUntilNonwhitespace();
    if (self.isEnd()) {
        return null;
    }
    return self.tryAtomic() orelse self.expectCombination();
}

fn tryAtomic(self: *Self) ?Span {
    assert(!self.isEnd());

    const char = self.peekChar() orelse unreachable;
    assert(!char.isWhitespace());
    if (!char.isAtomic()) {
        return null;
    }

    const start = self.getIndex();
    _ = self.nextChar();

    return Span.fromBounds(start, self.getIndex())
        .withOffset(self.statement.offset);
}

fn expectCombination(self: *Self) Span {
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

    return Span.fromBounds(start, self.getIndex())
        .withOffset(self.statement.offset);
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
