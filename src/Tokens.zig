const Self = @This();

const std = @import("std");
const assert = std.debug.assert;

const Char = @import("Char.zig");
const Span = @import("Span.zig");
const Token = @import("Token.zig");

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

pub fn expectIdentOrEmpty(self: *Self) !?Token {
    const token = self.next() orelse return null;
    if (token.kind != .Ident) {
        return error.UnexpectedToken;
    }
    return token;
}

pub fn expectEquals(self: *Self) !void {
    const token = try self.expectNext();
    if (token.kind != .Equals) {
        return error.UnexpectedToken;
    }
}

fn expectNext(self: *Self) !Token {
    return self.next() orelse return error.UnexpectedEol;
}

// TODO(refactor): Make private
// TODO(refactor): Rename
pub fn next(self: *Self) ?Token {
    while (true) {
        const span = self.nextTokenAny() orelse return null;
        if (std.mem.eql(u8, span.in(self.text), "--")) {
            self.advanceUntilLinebreak();
            continue;
        }
        return Token.new(self.text, span);
    }
}

fn nextTokenAny(self: *Self) ?Span {
    self.advanceUntilNonwhitespace();
    if (self.isEnd()) {
        return null;
    }
    if (self.tryNextAtomic()) |span| {
        return span;
    }
    return self.nextNormalToken();
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

fn tryNextAtomic(self: *Self) ?Span {
    if (!self.nextTokenChar().isAtomic()) {
        return null;
    }
    self.index += 1;
    return Span.new(self.index - 1, 1).withOffset(self.statement.offset);
}

// TODO(refactor): Rename
fn nextNormalToken(self: *Self) Span {
    const start = self.index;
    self.index += 1;

    while (self.peekChar()) |ch| {
        if (ch.isWhitespace() or
            ch.isAtomic())
        {
            break;
        }
        self.index += 1;
    }

    return Span.fromBounds(start, self.index).withOffset(self.statement.offset);
}

fn nextTokenChar(self: *const Self) Char {
    assert(!self.isEnd());
    const first = self.peekChar() orelse unreachable;
    assert(!first.isWhitespace());
    return first;
}

fn peekChar(self: *const Self) ?Char {
    if (self.isEnd()) {
        return null;
    }
    return Char.new(self.text[self.statement.offset + self.index]);
}

fn isEnd(self: *const Self) bool {
    return self.index >= self.statement.length;
}
