const std = @import("std");

const Span = @import("Span.zig");

pub const Index = usize;

pub const Decl = struct {
    name: Span,
    term: Term,
};

pub const Term = union(enum) {
    const Self = @This();

    variable: Span,
    abstraction: Abstr,
    application: Appl,

    pub const Abstr = struct {
        span: Span,
        variable: Span,
        term: Index,
    };
    pub const Appl = struct {
        span: Span,
        variable: Span,
        term: Index,
    };

    pub fn getSpan(self: *const Self) Span {
        return switch (self.*) {
            .variable => |span| span,
            .abstraction => |abstr| abstr.span,
            .application => |appl| appl.span,
        };
    }

    pub fn debug(self: *const Self, list: []Term, text: []const u8, depth: usize) void {
        switch (self.*) {
            .variable => |variable| {
                debugVariable(variable, text, depth);
            },
            .abstraction => |abstr| {
                debugIndent(depth);
                std.debug.print("abstraction: `{s}`\n", .{self.getSpan().in(text)});

                debugVariable(abstr.variable, text, depth + 1);

                debugIndent(depth + 1);
                const term = &list[abstr.term];
                std.debug.print("term: `{s}`\n", .{term.getSpan().in(text)});
                term.debug(list, text, depth + 2);
            },
            .application => |abstr| {
                debugIndent(depth);
                std.debug.print("application: `{s}`\n", .{self.getSpan().in(text)});

                debugVariable(abstr.variable, text, depth + 1);

                debugIndent(depth + 1);
                const term = &list[abstr.term];
                std.debug.print("term: `{s}`\n", .{term.getSpan().in(text)});
                term.debug(list, text, depth + 2);
            },
        }
    }

    fn debugVariable(span: Span, text: []const u8, depth: usize) void {
        debugIndent(depth);
        std.debug.print("variable: `{s}`\n", .{span.in(text)});
    }

    fn debugIndent(depth: usize) void {
        for (0..depth) |_| {
            std.debug.print("|   ", .{});
        }
    }
};
