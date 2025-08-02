const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const assert = std.debug.assert;

const Span = @import("Span.zig");

pub const TermIndex = usize;
pub const DeclIndex = usize;

pub const Decl = struct {
    name: Span,
    term: TermIndex,
};

pub const Term = union(enum) {
    const Self = @This();

    variable: Span,
    abstraction: Abstr,
    application: Appl,
    group: Group,
    global: Global,

    pub const Abstr = struct {
        span: Span,
        variable: Span,
        right: TermIndex,
    };
    pub const Appl = struct {
        span: Span,
        left: TermIndex,
        right: TermIndex,
    };
    pub const Group = struct {
        span: Span,
        inner: TermIndex,
    };
    pub const Global = struct {
        span: Span,
        index: DeclIndex,
    };

    pub fn getSpan(self: *const Self) Span {
        return switch (self.*) {
            .variable => |span| span,
            .abstraction => |abstr| abstr.span,
            .application => |appl| appl.span,
            .group => |group| group.span,
            .global => |global| global.span,
        };
    }

    pub fn debug(self: *const Self, list: []const Term, text: []const u8) void {
        self.debugInner(0, "", list, text);
    }

    pub fn debugInner(self: *const Self, depth: usize, comptime prefix: []const u8, list: []const Term, text: []const u8) void {
        switch (self.*) {
            .variable => |span| {
                debugLabel(depth, prefix, "variable");
                debugSpan(span.in(text));
            },
            .global => |global| {
                debugLabel(depth, prefix, "global");
                std.debug.print("[{}] ", .{global.index});
                debugSpan(global.span.in(text));
            },
            .abstraction => |abstr| {
                debugLabel(depth, prefix, "abstraction");
                debugSpan(self.getSpan().in(text));
                debugLabel(depth + 1, "L", "variable");
                debugSpan(abstr.variable.in(text));
                list[abstr.right].debugInner(depth + 1, "R", list, text);
            },
            .application => |appl| {
                debugLabel(depth, prefix, "application");
                debugSpan(self.getSpan().in(text));
                list[appl.left].debugInner(depth + 1, "L", list, text);
                list[appl.right].debugInner(depth + 1, "R", list, text);
            },
            .group => |group| {
                debugLabel(depth, prefix, "group");
                debugSpan(self.getSpan().in(text));
                list[group.inner].debugInner(depth + 1, "", list, text);
            },
        }
    }

    fn debugLabel(depth: usize, comptime prefix: []const u8, comptime label: []const u8) void {
        for (0..depth) |_| {
            std.debug.print("|" ++ " " ** 5, .{});
        }
        if (prefix.len > 0) {
            std.debug.print("{s}.", .{prefix});
        }
        std.debug.print("{s}: ", .{label});
    }

    fn debugSpan(value: []const u8) void {
        var was_whitespace = true;
        for (value) |char| {
            if (std.ascii.isWhitespace(char)) {
                if (!was_whitespace) {
                    std.debug.print(" ", .{});
                    was_whitespace = true;
                }
            } else {
                was_whitespace = false;
                std.debug.print("{c}", .{char});
            }
        }
        std.debug.print("\n", .{});
    }
};

pub const TermStore = struct {
    const Self = @This();

    entries: ArrayList(Term),

    pub fn init(allocator: Allocator) Self {
        return .{
            .entries = ArrayList(Term).init(allocator),
        };
    }

    pub fn deinit(self: *const Self) void {
        self.entries.deinit();
    }

    pub fn append(self: *Self, term: Term) Allocator.Error!usize {
        try self.entries.append(term);
        return self.entries.items.len - 1;
    }

    pub fn get(self: *const Self, index: TermIndex) *const Term {
        assert(index <= self.entries.items.len);
        return &self.entries.items[index];
    }

    pub fn getMut(self: *Self, index: TermIndex) *Term {
        assert(index <= self.entries.items.len);
        return &self.entries.items[index];
    }
};
