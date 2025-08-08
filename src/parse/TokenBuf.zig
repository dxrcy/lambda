const Self = @This();

const Span = @import("../Span.zig");

const Tokenizer = @import("Tokenizer.zig");
const Token = @import("Token.zig");

tokenizer: Tokenizer,
peeked: ?Token,

pub fn new(text: []const u8, stmt: Span) Self {
    return .{
        .tokenizer = Tokenizer.new(text, stmt),
        .peeked = null,
    };
}

pub fn next(self: *Self) ?Token {
    if (self.peeked) |peeked| {
        self.peeked = null;
        return peeked;
    }
    return self.tokenizer.next();
}

pub fn peek(self: *Self) ?Token {
    if (self.peeked) |peeked| {
        return peeked;
    }
    self.peeked = self.tokenizer.next();
    return self.peeked;
}

pub fn isEnd(self: *Self) bool {
    return self.peek() == null;
}
