const Self = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const unicode = std.unicode;

const Span = @import("../Span.zig");
const Context = @import("../Context.zig");
const Reporter = @import("../Reporter.zig");

const model = @import("../model.zig");
const Decl = model.Decl;
const TermIndex = model.TermIndex;
const TermStore = model.TermStore;
const Term = model.Term;

const TokenBuf = @import("TokenBuf.zig");
const Tokenizer = @import("Tokenizer.zig");
const Token = @import("Token.zig");

token_buf: TokenBuf,

// For methods with `??T` return, `null` (`None`) indicates that an error was
// reported, and we should stop parsing the current statement. This should
// always be bubbled up initial callsite (so the parsing can skip this statement
// and continue).
//
// Alternatively, a return of `SomeNull` (`Some(None)`) simply indicates that
// the method in question didn't yield a token (end of statement or otherwise).
// This will be handled differently depending on context.
//
// I don't like this solution but I can't think of a better way to do it within
// Zig's type system. Perhaps by using another error union but this creates
// other problems.

fn SomeNull(T: type) ?T {
    return @as(?T, null);
}

/// Assumes valid UTF-8.
pub fn new(stmt: Span, context: *const Context) Self {
    return .{ .token_buf = TokenBuf.new(Tokenizer.new(stmt, context)) };
}

fn getContext(self: *const Self) *const Context {
    return self.token_buf.tokenizer.context;
}
fn getStatement(self: *const Self) Span {
    return self.token_buf.tokenizer.statement;
}

pub fn tryDeclaration(self: *Self, terms: *TermStore) Allocator.Error!?Decl {
    const name = self.expectIdentOrEnd() orelse
        (return null) orelse return null;

    _ = self.expectTokenKind(.Equals) orelse
        (return null) orelse return null;

    const index = try self.expectTermGreedy(false, terms) orelse
        (return null) orelse return null;

    // Any trailing characters should have already been handled (including
    // unmatched right paren)
    assert(self.nextToken() == null);

    return Decl{
        .name = name,
        .term = index,
    };
}

fn expectTermGreedy(self: *Self, comptime in_group: bool, terms: *TermStore) Allocator.Error!??TermIndex {
    const left = try self.tryTermSingle(false, in_group, terms) orelse
        (return null) orelse return SomeNull(TermIndex);

    const left_span = terms.get(left).span;

    // Keep taking following terms until [end of group or statement]
    var parent = left;
    while (true) {
        if (self.peekTokenIfKind(.ParenRight)) |right_paren| {
            if (!in_group) {
                Reporter.report(
                    "unexpected token",
                    "expected term or end of statement, found {s}",
                    .{Token.Kind.ParenRight.display()},
                    .{ .statement_token = .{
                        .statement = self.getStatement(),
                        .token = right_paren,
                    } },
                    self.getContext(),
                );
                return null;
            }
            break;
        }

        const right = try self.tryTermSingle(true, in_group, terms) orelse
            (return null) orelse
            {
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

fn tryTermSingle(self: *Self, comptime allow_end: bool, comptime in_group: bool, terms: *TermStore) Allocator.Error!??TermIndex {
    const left = self.nextToken() orelse (return null) orelse {
        if (!allow_end) {
            Reporter.report(
                "unexpected end of statement",
                "expected term",
                .{},
                .{ .statement_end = self.getStatement() },
                self.getContext(),
            );
        }
        return null;
    };

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
            const parameter = self.expectTokenKind(.Ident) orelse
                (return null) orelse return SomeNull(TermIndex);

            _ = self.expectTokenKind(.Dot) orelse
                (return null) orelse return SomeNull(TermIndex);

            const right = try self.expectTermGreedy(in_group, terms) orelse
                (return null) orelse return SomeNull(TermIndex);

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
            const inner = try self.expectTermGreedy(true, terms) orelse
                (return null) orelse return SomeNull(TermIndex);

            const right_paren = self.expectTokenKind(.ParenRight) orelse
                (return null) orelse return SomeNull(TermIndex);

            return try terms.append(Term{
                .span = left.span.join(right_paren),
                .value = .{
                    .group = inner,
                },
            });
        },

        .ParenRight, .Equals, .Dot, .Invalid => {
            assert(!(in_group and left.kind == .ParenRight));
            Reporter.report(
                "unexpected token",
                if (in_group)
                    "expected term or " ++ Token.Kind.ParenRight.display() ++ ", found {s}"
                else
                    "expected term or end of statement, found {s}",
                .{left.kind.display()},
                .{ .statement_token = .{
                    .statement = self.getStatement(),
                    .token = left.span,
                } },
                self.getContext(),
            );
            return null;
        },
    }
}

fn expectIdentOrEnd(self: *Self) ??Span {
    const token = self.nextToken() orelse
        (return null) orelse return SomeNull(Span);
    if (token.kind != .Ident) {
        Reporter.report(
            "unexpected token",
            "expected {s} or end of statement, found {s}",
            .{ Token.Kind.Ident.display(), token.kind.display() },
            .{ .statement_token = .{
                .statement = self.getStatement(),
                .token = token.span,
            } },
            self.getContext(),
        );
        return null;
    }
    return token.span;
}

fn expectTokenKind(self: *Self, kind: Token.Kind) ??Span {
    const token = self.nextToken() orelse (return null) orelse {
        Reporter.report(
            "unexpected end of statement",
            "expected {s}",
            .{kind.display()},
            .{ .statement_end = self.getStatement() },
            self.getContext(),
        );
        return null;
    };
    if (token.kind != kind) {
        Reporter.report(
            "unexpected token",
            "expected {s}, found {s}",
            .{ kind.display(), token.kind.display() },
            .{ .statement_token = .{
                .statement = self.getStatement(),
                .token = token.span,
            } },
            self.getContext(),
        );
        return null;
    }
    return token.span;
}

fn peekTokenIfKind(self: *Self, kind: Token.Kind) ?Span {
    if (self.peekToken()) |token| {
        if (token.kind == kind) {
            return token.span;
        }
    }
    return null;
}

fn peekToken(self: *Self) ?Token {
    // Only validate token when actually consuming with `nextToken`
    return self.token_buf.peek();
}

fn nextToken(self: *Self) ??Token {
    const token = self.token_buf.next() orelse {
        return SomeNull(Token);
    };
    if (!self.validateToken(token)) {
        return null;
    }
    return token;
}

/// Does not check for invalid UTF-8, this should already be checked.
fn validateToken(self: *const Self, token: Token) bool {
    const value = token.span.in(self.getContext());

    if (findDisallowedCharacter(value)) |codepoint| {
        var buffer: [4]u8 = undefined;
        const length = unicode.utf8Encode(codepoint, &buffer) catch unreachable;
        const slice = buffer[0..length];

        Reporter.report(
            "invalid charracter in token",
            "character not allowed `{s}` (0x{x})",
            .{ slice, codepoint },
            .{ .token = token.span },
            self.getContext(),
        );
        return false;
    }
    return true;
}

// TODO(feat): Support more characters
fn findDisallowedCharacter(value: []const u8) ?u21 {
    const view = unicode.Utf8View.init(value) catch unreachable;
    var iter = view.iterator();
    while (iter.nextCodepoint()) |codepoint| {
        switch (codepoint) {
            ' ', '\t'...'\r' => unreachable,
            // Greek letters
            0x3b1...0x3c9, 0x391...0x3a1, 0x3a3...0x3a9 => {},
            // Ascii (except whitespace or control)
            0x21...0x7e => {},
            else => return codepoint,
        }
    }
    return null;
}
