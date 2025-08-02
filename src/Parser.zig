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

pub fn tryDeclaration(self: *Self, terms: *TermStore) NewTermError!?Decl {
    const name = try self.expectIdentOrEnd() orelse {
        return null;
    };
    _ = try self.expectTokenKind(.Equals);
    const index = try self.expectTermGreedy(terms);
    try self.expectEnd();

    return Decl{
        .name = name,
        .term = index,
    };
}

fn expectTermGreedy(self: *Self, terms: *TermStore) NewTermError!TermIndex {
    const left = try self.tryTermSingle(terms) orelse {
        return error.UnexpectedEnd;
    };
    const left_span = terms.get(left).span;

    // Keep taking following terms until [end of group or statement]
    var parent = left;
    while (!self.peekIsTokenKind(.ParenRight)) {
        const right = try self.tryTermSingle(terms) orelse {
            break;
        };
        parent = try terms.append(Term{
            .span = left_span.join(terms.get(right).span),
            .value = .{
                .application = .{
                    .function = parent,
                    .argument = right,
                },
            },
        });
    }
    return parent;
}

fn tryTermSingle(self: *Self, terms: *TermStore) NewTermError!?TermIndex {
    const left = self.tryNext() orelse return null;

    switch (left.kind) {
        .Ident => {
            return try terms.append(Term{
                .span = left.span,
                .value = .{
                    .unresolved = {},
                },
            });
        },

        .Backslash => {
            const parameter = try self.expectTokenKind(.Ident);
            _ = try self.expectTokenKind(.Dot);

            const right = try self.expectTermGreedy(terms);

            return try terms.append(Term{
                .span = left.span.join(terms.get(right).span),
                .value = .{
                    .abstraction = .{
                        .parameter = parameter,
                        .body = right,
                    },
                },
            });
        },

        .ParenLeft => {
            const inner = try self.expectTermGreedy(terms);
            const right_paren = try self.expectTokenKind(.ParenRight);

            return try terms.append(Term{
                .span = left.span.join(right_paren),
                .value = .{
                    .group = inner,
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
