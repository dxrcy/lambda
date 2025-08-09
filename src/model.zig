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

pub const Query = struct {
    term: TermIndex,
};

pub const Term = struct {
    const Self = @This();

    span: Span,
    value: Kind,

    const Kind = union(enum) {
        unresolved: void,
        local: TermIndex,
        global: DeclIndex,
        group: TermIndex,
        abstraction: Abstr,
        application: Appl,

        const Abstr = struct {
            parameter: Span,
            body: TermIndex,
        };
        const Appl = struct {
            function: TermIndex,
            argument: TermIndex,
        };
    };
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
