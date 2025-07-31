const Self = @This();

const std = @import("std");
const assert = std.debug.assert;

const Char = @import("Char.zig");
const Span = @import("Span.zig");

text: []const u8,
index: usize,

pub fn new(text: []const u8) Self {
    return .{
        .text = text,
        .index = 0,
    };
}

const Token = struct {
    span: Span,
    // kind: Kind,
    //
    // const Kind = union(enum) {
    //     Integer,
    //     String,
    //     Symbol,
    //     Identifier,
    // };
};

pub fn next(self: *Self) ?Token {
    while (true) {
        const token = self.nextTokenAny() orelse return null;
        if (std.mem.eql(u8, token.span.in(self.text), "--")) {
            self.advanceUntilLinebreak();
            continue;
        }
        return token;
    }
}

fn nextTokenAny(self: *Self) ?Token {
    self.advanceUntilNonwhitespace();
    if (self.isEnd()) {
        return null;
    }
    if (self.tryNextAtomic()) |span| {
        return .{ .span = span };
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
    return Span.new(self.index - 1, 1);
}

// TODO(refactor): Rename
fn nextNormalToken(self: *Self) Token {
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

    const span = Span.fromBounds(start, self.index);
    return .{ .span = span };
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
    return Char.new(self.text[self.index]);
}

fn isEnd(self: *const Self) bool {
    return self.index >= self.text.len;
}
