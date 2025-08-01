const std = @import("std");

const Span = @import("Span.zig");

// TODO(feat): Remove
pub const NO_TERM_INDEX = std.math.maxInt(u32);

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
        left: Index,
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
                debugBranch(depth + 1, "L", list, text, abstr.left);
                debugBranch(depth + 1, "R", list, text, abstr.right);
            },
            .application => |appl| {
                debugSpan(depth, prefix, "application", self.getSpan().in(text));
                debugBranch(depth + 1, "L", list, text, appl.left);
                debugBranch(depth + 1, "R", list, text, appl.right);
            },
            .group => |group| {
                debugSpan(depth, prefix, "group", self.getSpan().in(text));
                debugBranch(depth + 1, "", list, text, group.inner);
            },
        }
    }

    fn debugBranch(depth: usize, comptime prefix: []const u8, list: []const Term, text: []const u8, index: Index) void {
        if (index != NO_TERM_INDEX) {
            list[index].debugInner(depth, prefix, list, text);
        } else {
            debugSpan(depth, prefix, "<ERROR>", "-");
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
