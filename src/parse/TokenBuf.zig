const Self = @This();

const Context = @import("../Context.zig");
const Span = @import("../Span.zig");

const Tokenizer = @import("Tokenizer.zig");
const Token = @import("Token.zig");

tokenizer: Tokenizer,
peeked: ?Token,

pub fn new(stmt: Span, context: *const Context) Self {
    return .{
        .tokenizer = Tokenizer.new(stmt, context),
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
