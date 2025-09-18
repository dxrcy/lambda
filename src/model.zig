const std = @import("std");
const Allocator = std.mem.Allocator;

const TextStore = @import("text/TextStore.zig");
const Source = TextStore.Source;
const SourceSpan = TextStore.SourceSpan;

const Signature = @import("signature.zig").Signature;

pub const DeclIndex = usize;

pub const Decl = struct {
    name: SourceSpan,
    term: *Term,
    signature: ?u64,
};

// TODO: Remove, and simply use `*Term`
pub const Query = struct {
    term: *Term,
};

/// Like a `SourceSpan` without a `length`.
/// To uniquely identify a paramater declaration.
pub const ParamRef = struct {
    const Self = @This();

    source: Source,
    offset: usize,

    pub fn from(span: SourceSpan) Self {
        return Self{
            .source = span.source,
            .offset = span.free.offset,
        };
    }

    // TODO: Use in `reduction.zig`
    pub fn equals(left: Self, right: Self) bool {
        return left.offset == right.offset and left.source.equals(right.source);
    }
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
    span: ?SourceSpan,
    value: Kind,

    pub const Kind = union(enum) {
        unresolved: void,
        local: ParamRef,
        global: DeclIndex,
        group: *Term,
        abstraction: Abstr,
        application: Appl,
    };

    pub const Abstr = struct {
        /// Used for resolution and reduction.
        /// Referred to by `ParamRef`.
        parameter: SourceSpan,
        body: *Term,
    };

    pub const Appl = struct {
        function: *Term,
        argument: *Term,
    };

    /// Allocate and initialize a `Term`.
    pub fn create(
        span: ?SourceSpan,
        value: Kind,
        allocator: Allocator,
    ) Allocator.Error!*Term {
        const ptr = try allocator.create(Term);
        ptr.* = .{ .span = span, .value = value };
        return ptr;
    }
};
