const Self = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const Span = @import("Span.zig");
const Tokenizer = @import("Tokenizer.zig");
const Token = @import("Token.zig");

const model = @import("model.zig");
const Decl = model.Decl;
const Term = model.Term;
const TermStore = model.TermStore;
const Index = model.Index;

text: []const u8,
tokens: ArrayList(Token),
index: usize,

pub fn new(text: []const u8, stmt: Span, allocator: Allocator) !Self {
    var tokens = ArrayList(Token).init(allocator);
    var tokenizer = Tokenizer.new(text, stmt);
    while (tokenizer.next()) |token| {
        try tokens.append(token);
    }
    return .{
        .text = text,
        .tokens = tokens,
        .index = 0,
    };
}

pub fn deinit(self: *const Self) void {
    self.tokens.deinit();
}

fn peek(self: *Self) ?Token {
    if (self.index >= self.tokens.items.len) {
        return null;
    }
    return self.tokens.items[self.index];
}

fn tryNext(self: *Self) ?Token {
    if (self.index >= self.tokens.items.len) {
        return null;
    }
    const token = self.tokens.items[self.index];
    self.index += 1;
    return token;
}

fn expectNext(self: *Self) !Token {
    return self.tryNext() orelse return error.UnexpectedEol;
}

pub fn expectIdent(self: *Self) !Span {
    const token = try self.expectNext();
    if (token.kind != .Ident) {
        return error.UnexpectedToken;
    }
    return token.span;
}

pub fn tryIdent(self: *Self) !?Span {
    const token = self.tryNext() orelse return null;
    if (token.kind != .Ident) {
        return null;
    }
    return token.span;
}

pub fn expectIdentOrEol(self: *Self) !?Span {
    const token = self.tryNext() orelse return null;
    if (token.kind != .Ident) {
        return error.UnexpectedToken;
    }
    return token.span;
}

// TODO(refactor): Use `End` instead of `Eol`
pub fn expectEol(self: *Self) !void {
    if (self.index < self.tokens.items.len) {
        return error.UnexpectedToken;
    }
}

pub fn expectEquals(self: *Self) !void {
    const token = try self.expectNext();
    if (token.kind != .Equals) {
        return error.UnexpectedToken;
    }
}
pub fn expectDot(self: *Self) !void {
    const token = try self.expectNext();
    if (token.kind != .Dot) {
        return error.UnexpectedToken;
    }
}
pub fn expectParenRight(self: *Self) !Span {
    const token = try self.expectNext();
    if (token.kind != .ParenRight) {
        return error.UnexpectedToken;
    }
    return token.span;
}

const TermError = error{ UnexpectedToken, UnexpectedEol, OutOfMemory };

pub fn tryDeclaration(self: *Self, store: *TermStore) TermError!?Decl {
    const name = try self.expectIdentOrEol() orelse {
        return null;
    };
    try self.expectEquals();
    const term_index = try self.expectStatementTerm(store);

    return Decl{
        .name = name,
        .term = term_index,
    };
}

pub fn expectStatementTerm(self: *Self, store: *TermStore) TermError!Index {
    const index = try self.expectTerm(store, true);
    try self.expectEol();
    return index;
}

pub fn expectTerm(self: *Self, store: *TermStore, is_greedy: bool) TermError!Index {
    return try self.tryTerm(store, is_greedy) orelse {
        return error.UnexpectedEol;
    };
}

pub fn tryTerm(self: *Self, store: *TermStore, is_greedy: bool) !?Index {
    const first = self.tryNext() orelse {
        return null;
    };

    switch (first.kind) {
        .Ident => {
            var index = try store.append(Term{
                .variable = first.span,
            });

            while (is_greedy) {
                if (self.peek()) |token| {
                    if (token.kind == .ParenRight) {
                        break;
                    }
                }

                const right_index = try self.tryTerm(store, false) orelse {
                    break;
                };
                const right = store.get(right_index);
                const span = first.span.join(right.getSpan());

                index = try store.append(Term{
                    .application = Term.Appl{
                        .span = span,
                        .left = index,
                        .right = right_index,
                    },
                });
            }
            return index;
        },

        .Backslash => {
            const variable = try self.expectIdent();
            try self.expectDot();

            const right_index = try self.expectTerm(store, true);
            const right = store.get(right_index);
            const span = first.span.join(right.getSpan());

            return try store.append(Term{
                .abstraction = Term.Abstr{
                    .span = span,
                    .variable = variable,
                    .right = right_index,
                },
            });
        },

        .ParenLeft => {
            const inner = try self.expectTerm(store, true);

            const paren_right = try self.expectParenRight();
            const span = first.span.join(paren_right);

            return try store.append(Term{
                .group = Term.Group{
                    .span = span,
                    .inner = inner,
                },
            });
        },

        .ParenRight, .Equals, .Dot, .Invalid => {
            return error.UnexpectedToken;
        },
    }
}
