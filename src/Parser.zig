const Self = @This();

const std = @import("std");

const Span = @import("Span.zig");
const TokenBuf = @import("TokenBuf.zig");
const Token = @import("Token.zig");

const model = @import("model.zig");
const Decl = model.Decl;
const TermIndex = model.TermIndex;
const TermStore = model.TermStore;
const Term = model.Term;

const NewTermError = AnyTokenError || std.mem.Allocator.Error;
const AnyTokenError = error{
    UnexpectedToken,
    UnexpectedEnd,
};

tokens: TokenBuf,

pub fn new(text: []const u8, stmt: Span) Self {
    return .{ .tokens = TokenBuf.new(text, stmt) };
}

pub fn tryDeclaration(self: *Self, store: *TermStore) NewTermError!?Decl {
    const name = try self.expectIdentOrEnd() orelse {
        return null;
    };
    _ = try self.expectTokenKind(.Equals);
    const index = try self.expectTermGreedy(store);
    try self.expectEnd();

    return Decl{
        .name = name,
        .term = index,
    };
}

fn expectTermGreedy(self: *Self, store: *TermStore) NewTermError!TermIndex {
    const left = try self.tryTermSingle(store) orelse {
        return error.UnexpectedEnd;
    };
    const left_span = store.get(left).getSpan();

    // Keep taking following terms until [end of group or statement]
    var parent = left;
    while (!self.peekIsTokenKind(.ParenRight)) {
        const right = try self.tryTermSingle(store) orelse {
            break;
        };
        parent = try store.append(Term{
            .application = .{
                .span = left_span.join(store.get(right).getSpan()),
                .left = parent,
                .right = right,
            },
        });
    }
    return parent;
}

fn tryTermSingle(self: *Self, store: *TermStore) NewTermError!?TermIndex {
    const left = self.tryNext() orelse return null;

    switch (left.kind) {
        .Ident => {
            return try store.append(Term{
                .unresolved = left.span,
            });
        },

        .Backslash => {
            const variable = try self.expectTokenKind(.Ident);
            _ = try self.expectTokenKind(.Dot);

            const right = try self.expectTermGreedy(store);

            return try store.append(Term{
                .abstraction = .{
                    .span = left.span.join(store.get(right).getSpan()),
                    .variable = variable,
                    .right = right,
                },
            });
        },

        .ParenLeft => {
            const inner = try self.expectTermGreedy(store);
            const right_paren = try self.expectTokenKind(.ParenRight);

            return try store.append(Term{
                .group = .{
                    .span = left.span.join(right_paren),
                    .inner = inner,
                },
            });
        },

        .ParenRight, .Equals, .Dot, .Invalid => {
            return error.UnexpectedToken;
        },
    }
}

fn expectEnd(self: *Self) error{UnexpectedToken}!void {
    if (!self.tokens.isEnd()) {
        return error.UnexpectedToken;
    }
}

fn expectIdentOrEnd(self: *Self) error{UnexpectedToken}!?Span {
    const token = self.tryNext() orelse return null;
    if (token.kind != .Ident) {
        return error.UnexpectedToken;
    }
    return token.span;
}

fn expectTokenKind(self: *Self, kind: Token.Kind) AnyTokenError!Span {
    const token = try self.expectNext();
    if (token.kind != kind) {
        return error.UnexpectedToken;
    }
    return token.span;
}

fn peekIsTokenKind(self: *Self, kind: Token.Kind) bool {
    if (self.peek()) |token| {
        if (token.kind == kind) {
            return true;
        }
    }
    return false;
}

fn peek(self: *Self) ?Token {
    return self.tokens.peek();
}
fn tryNext(self: *Self) ?Token {
    return self.tokens.next();
}
fn expectNext(self: *Self) error{UnexpectedEnd}!Token {
    return self.tryNext() orelse {
        return error.UnexpectedEnd;
    };
}
