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
            self.advanceUntilLinebreak();
            continue;
        }
        return Token.new(span, self.context);
    }
}

fn getIndex(self: *const Self) usize {
    return self.char_iter.i;
}

fn isEnd(self: *Self) bool {
    return self.char_iter.peek(1).len < 1;
}

fn peekChar(self: *Self) ?TokenChar {
    const chars = self.char_iter.peek(1);
    assert(chars.len <= 1);
    if (chars.len == 0) {
        return null;
    }
    return TokenChar.from(chars[0]);
}

fn nextChar(self: *Self) ?TokenChar {
    const codepoint = self.char_iter.nextCodepoint() orelse return null;
    return TokenChar.from(codepoint);
}

fn expectNonWhitespace(self: *Self) TokenChar {
    assert(!self.isEnd());
    const first = self.peekChar() orelse unreachable;
    assert(!first.isWhitespace());
    return first;
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
