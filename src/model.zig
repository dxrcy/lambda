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

    unresolved: Span,
    local: Local,
    global: Global,

    abstraction: Abstr,
    application: Appl,
    group: Group,

    pub const Global = struct {
        span: Span,
        index: DeclIndex,
    };
    pub const Local = struct {
        span: Span,
        index: TermIndex,
    };
    pub const Group = struct {
        span: Span,
        inner: TermIndex,
    };
    pub const Abstr = struct {
        span: Span,
        parameter: Span,
        right: TermIndex,
    };
    pub const Appl = struct {
        span: Span,
        left: TermIndex,
        right: TermIndex,
    };

    pub fn getSpan(self: *const Self) Span {
        return switch (self.*) {
            .unresolved => |span| span,
            .local => |local| local.span,
            .global => |global| global.span,
            .group => |group| group.span,
            .abstraction => |abstr| abstr.span,
            .application => |appl| appl.span,
        };
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
