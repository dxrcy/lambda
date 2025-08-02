const Self = @This();

const std = @import("std");

const Span = @import("Span.zig");
const Tokenizer = @import("Tokenizer.zig");
const Token = @import("Token.zig");

text: []const u8,
tokens: Tokenizer,
peeked: ?Token,

pub fn new(text: []const u8, stmt: Span) !Self {
    return .{
        .text = text,
        .tokens = Tokenizer.new(text, stmt),
        .peeked = null,
    };
}

pub fn next(self: *Self) ?Token {
    if (self.peeked) |peeked| {
        self.peeked = null;
        return peeked;
    }
    return self.tokens.next();
}

pub fn peek(self: *Self) ?Token {
    if (self.peeked) |peeked| {
        return peeked;
    }
    self.peeked = self.tokens.next();
    return self.peeked;
}

pub fn isEnd(self: *Self) bool {
    if (self.peeked != null) {
        return false;
    }
    self.peeked = self.tokens.next();
    return self.peeked == null;
}
