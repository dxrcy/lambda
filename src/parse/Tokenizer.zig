const Self = @This();

const std = @import("std");
const assert = std.debug.assert;
const ArrayList = std.ArrayList;

const Span = @import("../Span.zig");

const model = @import("../model.zig");
const Term = model.Term;

const Char = @import("Char.zig");
const Token = @import("Token.zig");

// TODO(refactor): Use `Context`
text: []const u8,
statement: Span,
index: usize,

pub fn new(text: []const u8, stmt: Span) Self {
    return .{
        .text = text,
        .statement = stmt,
        .index = 0,
    };
}

pub fn next(self: *Self) ?Token {
    while (true) {
        const span = self.nextTokenSpan() orelse return null;
        // TODO(fix): Include anything BEGINNING with `--`
        if (std.mem.eql(u8, span.in(self.text), "--")) {
            self.advanceUntilLinebreak();
            continue;
        }
        return Token.new(self.text, span);
    }
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
    self.index += 1;
    return Span.new(self.index - 1, 1).withOffset(self.statement.offset);
}

fn expectCombination(self: *Self) Span {
    assert(!self.peekChar().?.isWhitespace());

    const start = self.index;
    self.index += 1;
    while (self.peekChar()) |ch| {
        if (ch.isWhitespace() or ch.isAtomic()) {
            break;
        }
        self.index += 1;
    }
    return Span.fromBounds(start, self.index).withOffset(self.statement.offset);
}

fn advanceUntilNonwhitespace(self: *Self) void {
    while (self.peekChar()) |ch| {
        if (!ch.isWhitespace()) {
            break;
        }
        self.index += 1;
    }
}

fn advanceUntilLinebreak(self: *Self) void {
    while (self.peekChar()) |char| {
        self.index += 1;
        if (char.isLinebreak()) {
            break;
        }
    }
}

fn peekChar(self: *const Self) ?Char {
    if (self.isEnd()) {
        return null;
    }
    return Char.new(self.text[self.statement.offset + self.index]);
}

fn expectNonWhitespace(self: *const Self) Char {
    assert(!self.isEnd());
    const first = self.peekChar() orelse unreachable;
    assert(!first.isWhitespace());
    return first;
}

fn isEnd(self: *const Self) bool {
    return self.index >= self.statement.length;
}
