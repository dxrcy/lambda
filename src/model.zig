const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

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
    group: Group,

    pub const Abstr = struct {
        span: Span,
        variable: Span,
        right: Index,
    };
    pub const Appl = struct {
        span: Span,
        left: Index,
        right: Index,
    };
    pub const Group = struct {
        span: Span,
        inner: Index,
    };

    pub fn getSpan(self: *const Self) Span {
        return switch (self.*) {
            .variable => |span| span,
            .abstraction => |abstr| abstr.span,
            .application => |appl| appl.span,
            .group => |group| group.span,
        };
    }

    pub fn debug(self: *const Self, list: []const Term, text: []const u8) void {
        self.debugInner(0, "", list, text);
    }

    pub fn debugInner(self: *const Self, depth: usize, comptime prefix: []const u8, list: []const Term, text: []const u8) void {
        switch (self.*) {
            .variable => |span| {
                debugSpan(depth, prefix, "variable", span.in(text));
            },
            .abstraction => |abstr| {
                debugSpan(depth, prefix, "abstraction", self.getSpan().in(text));
                debugSpan(depth + 1, "L", "variable", abstr.variable.in(text));
                list[abstr.right].debugInner(depth + 1, "R", list, text);
            },
            .application => |appl| {
                debugSpan(depth, prefix, "application", self.getSpan().in(text));
                list[appl.left].debugInner(depth + 1, "L", list, text);
                list[appl.right].debugInner(depth + 1, "R", list, text);
            },
            .group => |group| {
                debugSpan(depth, prefix, "group", self.getSpan().in(text));
                list[group.inner].debugInner(depth + 1, "", list, text);
            },
        }
    }

    fn debugSpan(depth: usize, comptime prefix: []const u8, comptime label: []const u8, value: []const u8) void {
        for (0..depth) |_| {
            std.debug.print("|" ++ " " ** 5, .{});
        }
        if (prefix.len > 0) {
            std.debug.print("{s}.", .{prefix});
        }
        std.debug.print("{s}: `", .{label});
        printSpan(value);
        std.debug.print("`\n", .{});
    }

    fn printSpan(value: []const u8) void {
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

    pub fn append(self: *Self, term: Term) !usize {
        try self.entries.append(term);
        return self.entries.items.len - 1;
    }

    pub fn get(self: *const Self, index: Index) *const Term {
        assert(index <= self.entries.items.len);
        return &self.entries.items[index];
    }
};
