const std = @import("std");
const Allocator = std.mem.Allocator;

const Span = @import("Span.zig");
const Context = @import("Context.zig");

pub const DeclIndex = usize;
pub const AbstrId = usize;

pub const Decl = struct {
    name: Span,
    term: *Term,
};

// TODO: Remove, and simply use `*Term`
pub const Query = struct {
    term: *Term,
};

/// Not very type-safe, since this type is used in many different contexts,
/// each with their own assumptions about what `Kind` is valid or if `span` may
/// be `null`.
/// `Term` could be specialized for different stages, but this would get tricky
/// with how terms are allocated, since specialized types would have different
/// layouts and sizes.
pub const Term = struct {
    const Self = @This();

    /// `null` represents a constructed term, which does not correspond to a
    /// string slice in a source text.
    span: ?Span,
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
        // FIXME: Ids are not unique between terms of different contexts
        id: AbstrId,
        /// Should only be used to display a parameter name.
        /// For resolution or reduction use `id`.
        parameter: Span,
        body: *Term,
    };

    pub const Appl = struct {
        function: *Term,
        argument: *Term,
    };

    /// Allocate and initialize a `Term`.
    pub fn create(
        span: ?Span,
        value: Kind,
        allocator: Allocator,
    ) Allocator.Error!*Term {
        const ptr = try allocator.create(Term);
        ptr.* = .{ .span = span, .value = value };
        return ptr;
    }
};
