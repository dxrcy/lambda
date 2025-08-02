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
    const index = try self.expectTerm(store, true);
    try self.expectEnd();

    return Decl{
        .name = name,
        .term = index,
    };
}

fn expectTerm(self: *Self, store: *TermStore, comptime is_greedy: bool) NewTermError!TermIndex {
    return try self.tryTerm(store, is_greedy) orelse {
        return error.UnexpectedEnd;
    };
}

fn tryTerm(self: *Self, store: *TermStore, comptime is_greedy: bool) NewTermError!?TermIndex {
    const first = self.tryNext() orelse {
        return null;
    };

    switch (first.kind) {
        .Ident => {
            var index = try store.append(Term{
                .variable = first.span,
            });

            if (!is_greedy) {
                return index;
            }

            while (!self.peekIsTokenKind(.ParenRight)) {
                const right_index = try self.tryTerm(store, false) orelse {
                    break;
                };
                const right_span = store.get(right_index).getSpan();

                index = try store.append(Term{
                    .application = .{
                        .span = first.span.join(right_span),
                        .left = index,
                        .right = right_index,
                    },
                });
            }
            return index;
        },

        .Backslash => {
            const variable = try self.expectTokenKind(.Ident);
            _ = try self.expectTokenKind(.Dot);

            const right_index = try self.expectTerm(store, true);
            const right_span = store.get(right_index).getSpan();

            return try store.append(Term{
                .abstraction = .{
                    .span = first.span.join(right_span),
                    .variable = variable,
                    .right = right_index,
                },
            });
        },

        .ParenLeft => {
            const inner = try self.expectTerm(store, true);
            const right_span = try self.expectTokenKind(.ParenRight);

            return try store.append(Term{
                .group = .{
                    .span = first.span.join(right_span),
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
    return self.tryNext() orelse return error.UnexpectedEnd;
}
