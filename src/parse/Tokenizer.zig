const Self = @This();

const std = @import("std");
const assert = std.debug.assert;
const ArrayList = std.ArrayList;

const Context = @import("../Context.zig");
const Span = @import("../Span.zig");

const model = @import("../model.zig");
const Term = model.Term;

const TokenChar = @import("TokenChar.zig");
const CharIter = @import("CharIter.zig");
const Token = @import("Token.zig");

context: *const Context,
statement: Span,
char_iter: CharIter,

pub fn new(statement: Span, context: *const Context) Self {
    return .{
        .context = context,
        .statement = statement,
        .char_iter = CharIter.new(statement.in(context)),
    };
}

pub fn next(self: *Self) ?Token {
    while (true) {
        const span = self.nextTokenSpan() orelse return null;
        if (std.mem.startsWith(u8, span.in(self.context), "--")) {
            self.advanceUntilLinebreak();
            continue;
        }
        return Token.new(span, self.context);
    }
}

fn peekChar(self: *const Self) ?TokenChar {
    const char = self.char_iter.peek() orelse return null;
    return TokenChar.from(char);
}

fn nextChar(self: *Self) ?TokenChar {
    const char = self.char_iter.next() orelse return null;
    return TokenChar.from(char);
}

fn getIndex(self: *const Self) usize {
    return self.char_iter.index;
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
    if (!self.expectNonWhitespace().isAtomic()) {
        return null;
    }
    // self.index += 1;
    return Span.new(self.getIndex() - 1, 1).withOffset(self.statement.offset);
}

fn expectCombination(self: *Self) Span {
    assert(!self.peekChar().?.isWhitespace());

    const start = self.getIndex();
    // self.index += 1;
    while (self.peekChar()) |ch| {
        if (ch.isWhitespace() or ch.isAtomic()) {
            break;
        }
        // self.index += 1;
    }
    return Span.fromBounds(start, self.getIndex()).withOffset(self.statement.offset);
}

fn advanceUntilNonwhitespace(self: *Self) void {
    while (self.peekChar()) |ch| {
        if (!ch.isWhitespace()) {
            break;
        }
        // self.index += 1;
    }
}

fn advanceUntilLinebreak(self: *Self) void {
    while (self.peekChar()) |char| {
        // self.index += 1;
        if (char.isLinebreak()) {
            break;
        }
    }
}

fn expectNonWhitespace(self: *const Self) TokenChar {
    assert(!self.isEnd());
    const first = self.peekChar() orelse unreachable;
    assert(!first.isWhitespace());
    return first;
}

fn isEnd(self: *const Self) bool {
    return self.char_iter.isEnd();
}
