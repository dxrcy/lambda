const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const assert = std.debug.assert;

const Span = @import("Span.zig");

const Context = @import("Context.zig");

pub const DeclIndex = usize;

pub const AbstrId = usize;

pub const Decl = struct {
    name: Span,
    term: *Term,
};

// TODO: Move?
pub const DeclEntry = struct {
    decl: Decl,
    context: *const Context,
};

pub const Query = struct {
    term: *Term,
};

// TODO: Include `Context` for each `Span` in each term...

pub const Term = struct {
    const Self = @This();

    span: Span,
    value: Kind,

    pub const Kind = union(enum) {
        unresolved: void,
        local: AbstrId,
        global: DeclIndex,
        group: *Term,
        abstraction: Abstr,
        application: Appl,
    };

    pub const Abstr = struct {
        id: AbstrId,
        parameter: Span,
        body: *Term,
    };

    pub const Appl = struct {
        function: *Term,
        argument: *Term,
    };

    /// Allocate and initialize a `Term`.
    pub fn create(span: Span, value: Kind, allocator: Allocator) Allocator.Error!*Term {
        const ptr = try allocator.create(Term);
        ptr.* = .{ .span = span, .value = value };
        return ptr;
    }
};
