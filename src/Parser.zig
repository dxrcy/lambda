const Self = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const Span = @import("Span.zig");
const Tokenizer = @import("Tokenizer.zig");
const Token = @import("Token.zig");

const model = @import("model.zig");
const Term = model.Term;
const Index = model.Index;
const NO_TERM_INDEX = model.NO_TERM_INDEX;

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
pub fn expectParenRight(self: *Self) !void {
    const token = try self.expectNext();
    if (token.kind != .ParenRight) {
        return error.UnexpectedToken;
    }
}

const TermError = error{ UnexpectedToken, UnexpectedEol, OutOfMemory };

pub fn expectStatementTerm(self: *Self, list: *ArrayList(Term)) TermError!Index {
    const index = try self.expectTerm(list, true);
    try self.expectEol();
    return index;
}

pub fn expectTerm(self: *Self, list: *ArrayList(Term), is_greedy: bool) TermError!Index {
    switch (try self.tryTerm(list, is_greedy)) {
        .success => |index| return index,
        else => {
            // TODO
            return error.UnexpectedEol;
        },
    }
}

const Status = union(enum) {
    success: Index,
    end_of_group: void,
    end_of_statement: void,
    unknown: void,

    pub fn asSuccess(self: Status) ?Index {
        return switch (self) {
            .success => |index| index,
            else => null,
        };
    }
};

pub fn tryTerm(self: *Self, list: *ArrayList(Term), is_greedy: bool) !Status {
    const first = self.tryNext() orelse {
        return .{ .end_of_statement = {} };
    };

    switch (first.kind) {
        .ParenLeft => {
            const index = try self.expectTerm(list, true);
            try self.expectParenRight();
            return .{ .success = index };
        },

        .Ident => {
            var index = try appendTerm(list, Term{
                .variable = first.span,
            });

            while (is_greedy) {
                if (self.peek()) |token| {
                    if (token.kind == .ParenRight) {
                        break;
                    }
                }
                const right_index = (try self.tryTerm(list, false)).asSuccess() orelse {
                    break;
                };

                const right = &list.items[right_index];
                const span = first.span.join(right.getSpan());

                index = try appendTerm(list, Term{
                    .application = Term.Appl{
                        .span = span,
                        .left = index,
                        .right = right_index,
                    },
                });
            }

            return .{ .success = index };
        },

        .Backslash => {
            const left_span = try self.expectIdent();
            const left_index = try appendTerm(list, Term{
                .variable = left_span,
            });

            try self.expectDot();
            const right_index = try self.expectTerm(list, true);

            const right = &list.items[right_index];
            const span = first.span.join(right.getSpan());

            const index = try appendTerm(list, Term{
                .abstraction = Term.Abstr{
                    .span = span,
                    .left = left_index,
                    .right = right_index,
                },
            });
            return .{ .success = index };
        },

        .ParenRight => {
            unimplemented("unexpected parent right", .{});
        },

        else => {
            unimplemented("unknown token `{s}`", .{first.span.in(self.text)});
        },
    }

    // (until all branches implemented)
    return .{ .unknown = {} };
}

fn appendTerm(list: *ArrayList(Term), term: Term) !usize {
    try list.append(term);
    return list.items.len - 1;
}

fn unimplemented(comptime message: []const u8, args: anytype) void {
    std.debug.print("\twarning: " ++ message ++ "\n", args);
}
