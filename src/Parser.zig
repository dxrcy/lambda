const Self = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const Span = @import("Span.zig");
const Tokenizer = @import("Tokenizer.zig");
const Token = @import("Token.zig");

const model = @import("model.zig");
const Term = model.Term;

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

pub fn expectTerm(self: *Self, list: *ArrayList(Term)) !?usize {
    const first = try self.expectNext();
    switch (first.kind) {
        .Ident => {
            std.debug.print("{s}\n", .{first.span.in(self.text)});

            if (self.tryNext()) |second| {
                unimplemented("tokens following variable `{s}`", .{second.span.in(self.text)});
            } else {
                try list.append(Term{ .variable = first.span });
                return list.items.len - 1;
            }
        },

        .Backslash => {
            std.debug.print("{s}\n", .{first.span.in(self.text)});

            const variable = try self.expectIdent();
            try self.expectDot();

            const term_index = try self.expectTerm(list) orelse {
                unimplemented("unresolved term", .{});
                return null;
            };

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
    return null;
}

fn unimplemented(comptime message: []const u8, args: anytype) void {
    std.debug.print("\twarning: " ++ message ++ "\n", args);
}
