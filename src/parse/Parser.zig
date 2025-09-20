const Self = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const unicode = std.unicode;

const TextStore = @import("../text/TextStore.zig");
const Source = TextStore.Source;
const SourceSpan = TextStore.SourceSpan;

const Reporter = @import("../Reporter.zig");

const model = @import("../model.zig");
const Decl = model.Decl;
const Query = model.Query;
const Term = model.Term;
const TermStore = model.TermStore;

const TokenBuf = @import("TokenBuf.zig");
const Tokenizer = @import("Tokenizer.zig");
const Token = @import("Token.zig");

token_buf: TokenBuf,
// TODO: Remove, and instead find text from `token_buf`
text: *const TextStore,
reporter: *Reporter,

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

fn SomeNull(comptime T: type) ?T {
    return @as(?T, null);
}

/// Assumes valid UTF-8.
pub fn new(
    stmt: SourceSpan,
    text: *const TextStore,
    reporter: *Reporter,
) Self {
    return .{
        .token_buf = TokenBuf.new(Tokenizer.new(stmt, text)),
        .text = text,
        .reporter = reporter,
    };
}

fn getStatement(self: *const Self) SourceSpan {
    return self.token_buf.tokenizer.statement;
}

pub const Statement = union(enum) {
    declaration: Decl,
    query: Query,
    inspect: *Term,
};

pub fn tryStatement(
    self: *Self,
    term_store: *TermStore,
) Allocator.Error!?Statement {
    if (!self.peekIsAnyToken()) {
        return null;
    }

    if (self.peekIsInspect()) {
        const term = try self.expectInspect(term_store) orelse
            return null;
        return .{ .inspect = term };
    }

    if (self.peekIsDeclaration()) {
        const decl = try self.expectDeclaration(term_store) orelse
            return null;
        return .{ .declaration = decl };
    }

    const query = try self.expectQuery(term_store) orelse
        return null;
    return .{ .query = query };
}

/// Returns `true` if the next token is present.
fn peekIsAnyToken(self: *Self) bool {
    return self.token_buf.peek() != null;
}

/// Returns `true` if the first token is `.Inspect` (it must be an inspect).
fn peekIsInspect(self: *Self) bool {
    const equals = self.token_buf.peek() orelse
        return false;
    return equals.kind == .Inspect;
}

/// Returns `true` if the second token is `.Equals` (it must be a declaration).
fn peekIsDeclaration(self: *Self) bool {
    const equals = self.token_buf.peekBy(2) orelse
        return false;
    return equals.kind == .Equals;
}

/// Assumes next token is present; caller must ensure this.
/// Assumes first token is `.Inspect`; caller must ensure this.
fn expectInspect(self: *Self, term_store: *TermStore) Allocator.Error!?*Term {
    assert(self.expectTokenKind(.Inspect) != null);
    return try self.expectStatementTerm(term_store);
}

/// Assumes next token is present; caller must ensure this.
/// Assumes second token is `.Equals`; caller must ensure this.
fn expectDeclaration(
    self: *Self,
    term_store: *TermStore,
) Allocator.Error!?Decl {
    const name = self.expectIdent() orelse
        return null;

    assert(self.expectTokenKind(.Equals) != null);

    const term = try self.expectStatementTerm(term_store) orelse
        return null;

    return Decl{
        .name = name,
        .term = term,
        .signature = undefined,
    };
}

/// Assumes next token is present; caller must ensure this.
fn expectQuery(self: *Self, term_store: *TermStore) Allocator.Error!?Query {
    const term = try self.expectStatementTerm(term_store) orelse
        return null;
    return Query{ .term = term };
}

fn expectStatementTerm(
    self: *Self,
    term_store: *TermStore,
) Allocator.Error!?*Term {
    const term = try self.tryTermGreedy(false, term_store) orelse
        (return null) orelse return null;
    // Any trailing characters should have already been handled (including
    // unmatched right paren)
    assert(self.nextToken().? == null);
    return term;
}

fn tryTermGreedy(
    self: *Self,
    comptime in_group: bool,
    term_store: *TermStore,
) Allocator.Error!??*Term {
    const left = try self.tryTermSingle(false, in_group, term_store) orelse
        (return null) orelse return SomeNull(*Term);

    // Keep taking following terms until [end of group or statement]
    var parent = left;
    while (true) {
        if (self.peekTokenIfKind(.ParenRight)) |right_paren| {
            if (!in_group) {
                self.reporter.report(
                    "unexpected token",
                    "expected term or end of statement, found {s}",
                    .{Token.Kind.ParenRight.display()},
                    .{ .statement_token = .{
                        .statement = self.getStatement(),
                        .token = right_paren,
                    } },
                    self.text,
                );
                return null;
            }
            break;
        }

        const right = try self.tryTermSingle(true, in_group, term_store) orelse
            (return null) orelse
            {
                break;
            };

        // TODO: Handle `null` span (panic)... and likewise elsewhere
        parent = try term_store.create(
            left.span.?.join(right.span.?),
            .{ .application = .{
                .function = parent,
                .argument = right,
            } },
        );
    }
    return parent;
}

fn tryTermSingle(
    self: *Self,
    comptime allow_end: bool,
    comptime in_group: bool,
    term_store: *TermStore,
) Allocator.Error!??*Term {
    const left = self.nextToken() orelse (return null) orelse {
        if (!allow_end) {
            self.reporter.report(
                "unexpected end of statement",
                "expected term",
                .{},
                .{ .statement_end = self.getStatement() },
                self.text,
            );
        }
        return SomeNull(*Term);
    };

    switch (left.kind) {
        .Ident => {
            return try term_store.create(
                left.span,
                .{ .unresolved = {} },
            );
        },

        .Backslash => {
            const parameter = self.expectTokenKind(.Ident) orelse
                (return null) orelse return SomeNull(*Term);

            _ = self.expectTokenKind(.Dot) orelse
                (return null) orelse return SomeNull(*Term);

            const right = try self.tryTermGreedy(in_group, term_store) orelse
                (return null) orelse return SomeNull(*Term);

            return try term_store.create(
                left.span.join(right.span.?),
                .{ .abstraction = .{
                    .parameter = parameter,
                    .body = right,
                } },
            );
        },

        .ParenLeft => {
            const inner = try self.tryTermGreedy(true, term_store) orelse
                (return null) orelse return SomeNull(*Term);

            const right_paren = self.expectTokenKind(.ParenRight) orelse
                (return null) orelse return SomeNull(*Term);

            return try term_store.create(
                left.span.join(right_paren),
                .{ .group = inner },
            );
        },

        .ParenRight, .Equals, .Dot, .Inspect => {
            self.reporter.report(
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
                self.text,
            );
            return null;
        },
    }
}

/// Assumes next token is present; caller must ensure this.
fn expectIdent(self: *Self) ?SourceSpan {
    const token = self.nextToken() orelse
        (return null) orelse {
        unreachable;
    };
    if (token.kind != .Ident) {
        self.reporter.report(
            "unexpected token",
            "expected {s} or end of statement, found {s}",
            .{ Token.Kind.Ident.display(), token.kind.display() },
            .{ .statement_token = .{
                .statement = self.getStatement(),
                .token = token.span,
            } },
            self.text,
        );
        return null;
    }
    return token.span;
}

fn expectTokenKind(self: *Self, kind: Token.Kind) ??SourceSpan {
    const token = self.nextToken() orelse (return null) orelse {
        self.reporter.report(
            "unexpected end of statement",
            "expected {s}",
            .{kind.display()},
            .{ .statement_end = self.getStatement() },
            self.text,
        );
        return null;
    };
    if (token.kind != kind) {
        self.reporter.report(
            "unexpected token",
            "expected {s}, found {s}",
            .{ kind.display(), token.kind.display() },
            .{ .statement_token = .{
                .statement = self.getStatement(),
                .token = token.span,
            } },
            self.text,
        );
        return null;
    }
    return token.span;
}

fn peekTokenIfKind(self: *Self, kind: Token.Kind) ?SourceSpan {
    if (self.token_buf.peek()) |token| {
        if (token.kind == kind) {
            return token.span;
        }
    }
    return null;
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
fn validateToken(self: *Self, token: Token) bool {
    const value = token.span.in(self.text);

    if (findDisallowedCharacter(value)) |codepoint| {
        var buffer: [4]u8 = undefined;
        const length = unicode.utf8Encode(codepoint, &buffer) catch unreachable;
        const slice = buffer[0..length];

        self.reporter.report(
            "invalid charracter in token",
            "character not allowed `{s}` (0x{x})",
            .{ slice, codepoint },
            .{ .token = token.span },
            self.text,
        );
        return false;
    }
    return true;
}

// TODO: Support more characters
fn findDisallowedCharacter(value: []const u8) ?u21 {
    const view = unicode.Utf8View.init(value) catch unreachable;
    var iter = view.iterator();
    while (iter.nextCodepoint()) |codepoint| {
        switch (codepoint) {
            ' ', '\t'...'\r' => unreachable,
            // Ascii (except whitespace or control)
            0x21...0x7e => {},
            // Greek letters
            0x3b1...0x3c9, 0x391...0x3a1, 0x3a3...0x3a9 => {},
            else => return codepoint,
        }
    }
    return null;
}
