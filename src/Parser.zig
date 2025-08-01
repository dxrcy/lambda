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

pub fn expectIdentOrEol(self: *Self) !?Span {
    const token = self.tryNext() orelse return null;
    if (token.kind != .Ident) {
        return error.UnexpectedToken;
    }
    return token.span;
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

pub const NO_TERM_INDEX = std.math.maxInt(u32);

const TermError = error{ UnexpectedToken, UnexpectedEol, OutOfMemory };

pub fn expectTerm(self: *Self, list: *ArrayList(Term)) TermError!Index {
    return try self.tryTerm(list) orelse return error.UnexpectedEol;
}

pub fn tryTerm(self: *Self, list: *ArrayList(Term)) !?Index {
    // TODO(fix): FIX PRECEDENCE !!!
    const first = self.tryNext() orelse return null;
    switch (first.kind) {
        .Ident => {
            std.debug.print("{s}\n", .{first.span.in(self.text)});

            const term_index =
                try self.tryTerm(list) orelse {
                    try list.append(Term{
                        .variable = first.span,
                    });
                    return list.items.len - 1;
                };

            if (term_index == std.math.maxInt(u32)) {
                unimplemented("unresolved term", .{});
                return NO_TERM_INDEX;
            }

            const term = &list.items[term_index];
            const span = first.span.join(term.getSpan());

            try list.append(Term{
                .application = Term.Appl{
                    .span = span,
                    .variable = first.span,
                    .term = term_index,
                },
            });
            return list.items.len - 1;
        },

        .Backslash => {
            // std.debug.print("{s}\n", .{first.span.in(self.text)});

            const variable = try self.expectIdent();
            try self.expectDot();

            const term_index = try self.expectTerm(list);
            if (term_index == std.math.maxInt(u32)) {
                unimplemented("unresolved term", .{});
                return NO_TERM_INDEX;
            }

            const term = &list.items[term_index];
            const span = first.span.join(term.getSpan());

            try list.append(Term{
                .abstraction = Term.Abstr{
                    .span = span,
                    .variable = variable,
                    .term = term_index,
                },
            });
            return list.items.len - 1;
        },

        else => {
            unimplemented("unknown token `{s}`", .{first.span.in(self.text)});
        },
    }
    // (until all branches implemented)
    return NO_TERM_INDEX;
}

fn unimplemented(comptime message: []const u8, args: anytype) void {
    std.debug.print("\twarning: " ++ message ++ "\n", args);
}
