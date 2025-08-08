const Self = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;

const Context = @import("Context.zig");
const Span = @import("Span.zig");
const Reporter = @import("Reporter.zig");
const TokenBuf = @import("TokenBuf.zig");
const Token = @import("Token.zig");

const model = @import("model.zig");
const Decl = model.Decl;
const TermIndex = model.TermIndex;
const TermStore = model.TermStore;
const Term = model.Term;

context: *const Context,
tokens: TokenBuf,

pub fn new(stmt: Span, context: *const Context) Self {
    return .{
        .tokens = TokenBuf.new(context.text, stmt),
        .context = context,
    };
}

pub fn tryDeclaration(self: *Self, terms: *TermStore) Allocator.Error!?Decl {
    const name = self.expectIdentOrEnd() orelse {
        return null;
    };
    _ = self.expectTokenKind(.Equals) orelse return null;
    const index = try self.expectTermGreedy(terms) orelse return null;
    self.expectEnd() orelse return null;

    return Decl{
        .name = name,
        .term = index,
    };
}

fn getStatement(self: *const Self) Span {
    return self.tokens.tokens.statement;
}

fn expectTermGreedy(self: *Self, terms: *TermStore) Allocator.Error!?TermIndex {
    const left = try self.tryTermSingle(terms) orelse {
        Reporter.report(
            "unexpected end of statement",
            "expected term",
            .{},
            .{ .statement_end = self.getStatement() },
            self.context,
        );
        return null;
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

fn tryTermSingle(self: *Self, terms: *TermStore) Allocator.Error!?TermIndex {
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
            const parameter = self.expectTokenKind(.Ident) orelse return null;
            _ = self.expectTokenKind(.Dot) orelse return null;

            const right = try self.expectTermGreedy(terms) orelse return null;

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
            const inner = try self.expectTermGreedy(terms) orelse return null;
            const right_paren = self.expectTokenKind(.ParenRight) orelse return null;

            return try terms.append(Term{
                .span = left.span.join(right_paren),
                .value = .{
                    .group = inner,
                },
            });
        },

        .ParenRight, .Equals, .Dot, .Invalid => {
            // TODO(feat): Show what was expected
            Reporter.report(
                "unexpected token",
                "expected <something else>",
                .{},
                .{ .statement_token = .{
                    .statement = self.getStatement(),
                    .token = left.span,
                } },
                self.context,
            );
            return null;
        },
    }
}

fn expectEnd(self: *Self) ?void {
    if (!self.tokens.isEnd()) {
        // TODO(feat): Show what was found
        Reporter.report(
            "unexpected token (todo)",
            "expected end of statement, found <something else>",
            .{},
            .{ .statement = self.getStatement() },
            self.context,
        );
        return null;
    }
}

fn expectIdentOrEnd(self: *Self) ?Span {
    const token = self.tryNext() orelse return null;
    if (token.kind != .Ident) {
        Reporter.report(
            "unexpected token",
            "expected {s} or end of statement, found {s}",
            .{ Token.Kind.Ident.display(), token.kind.display() },
            .{ .statement_token = .{
                .statement = self.getStatement(),
                .token = token.span,
            } },
            self.context,
        );
        return null;
    }
    return token.span;
}

fn expectTokenKind(self: *Self, kind: Token.Kind) ?Span {
    const token = self.expectNext() orelse return null;
    if (token.kind != kind) {
        Reporter.report(
            "unexpected token",
            "expected {s}, found {s}",
            .{ kind.display(), token.kind.display() },
            .{ .statement_token = .{
                .statement = self.getStatement(),
                .token = token.span,
            } },
            self.context,
        );
        return null;
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
fn expectNext(self: *Self) ?Token {
    return self.tryNext() orelse {
        // TODO(feat): Show what was expected
        Reporter.report(
            "unexpected end of statement",
            "expected <something else>",
            .{},
            .{ .statement_end = self.getStatement() },
            self.context,
        );
        return null;
    };
}
