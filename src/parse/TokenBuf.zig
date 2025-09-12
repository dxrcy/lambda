const Self = @This();

const std = @import("std");
const assert = std.debug.assert;

const Context = @import("../Context.zig");
const Span = @import("../Span.zig");

const Tokenizer = @import("Tokenizer.zig");
const Token = @import("Token.zig");

const PEEK_BUFFER_SIZE = 2;

tokenizer: Tokenizer,
peeked_tokens: [PEEK_BUFFER_SIZE]Token,
peeked_count: usize,

pub fn new(tokenizer: Tokenizer) Self {
    return .{
        .tokenizer = tokenizer,
        .peeked_tokens = undefined,
        .peeked_count = 0,
    };
}

pub fn next(self: *Self) ?Token {
    assert(self.peeked_count <= PEEK_BUFFER_SIZE);

    if (self.peeked_count == 0) {
        return self.tokenizer.next();
    }

    const token = self.peeked_tokens[0];
    // Shift items back
    self.peeked_count -= 1;
    for (0..self.peeked_count) |i| {
        self.peeked_tokens[i] = self.peeked_tokens[i + 1];
    }
    return token;
}

pub fn peek(self: *Self) ?Token {
    return self.peekBy(1);
}

pub fn peekBy(self: *Self, count: usize) ?Token {
    assert(count > 0);
    assert(count <= PEEK_BUFFER_SIZE);
    assert(self.peeked_count <= PEEK_BUFFER_SIZE);

    if (self.peeked_count < count) {
        for (self.peeked_count..count) |i| {
            self.peeked_tokens[i] = self.tokenizer.next() orelse {
                return null;
            };
        }
    }
    self.peeked_count = count;
    return self.peeked_tokens[count - 1];
}

pub fn isEnd(self: *Self) bool {
    return self.peek() == null;
}
