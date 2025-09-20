const std = @import("std");
const Allocator = std.mem.Allocator;

const TextStore = @import("text/TextStore.zig");
const Source = TextStore.Source;
const SourceSpan = TextStore.SourceSpan;

pub const DeclIndex = usize;

pub const Decl = struct {
    name: SourceSpan,
    term: TermCow,
    signature: ?u64,
};

// TODO: Remove, and simply use `TermCow`
pub const Query = struct {
    term: TermCow,
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

pub const TermStore = struct {
    const Self = @This();

    const ArenaAllocator = std.heap.ArenaAllocator;

    allocator: ArenaAllocator,

    pub fn init(child_allocator: Allocator) Self {
        return Self{
            .allocator = ArenaAllocator.init(child_allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.deinit();
    }

    pub fn create(
        self: *Self,
        span: ?SourceSpan,
        value: Term.Kind,
    ) Allocator.Error!TermCow {
        const owned = try self.allocator.allocator().create(Term);
        owned.* = .{ .span = span, .value = value };
        return TermCow{ .owned = owned };
    }
};

/// Copy-on-write reference to a `Term`.
/// Do not use this type behind a pointer, this is useless.
pub const TermCow = union(enum) {
    const Self = @This();

    owned: *Term,
    referenced: *const Term,

    /// Returns the underlying pointer of `self` (as `const`), regardless of
    /// whether `self` is *owned* or *referenced*.
    // TODO: Rename
    pub fn asConst(self: Self) *const Term {
        return switch (self) {
            .owned => |owned| owned,
            .referenced => |reference| reference,
        };
    }

    /// Asserts that `self` is *owned*, and returns the underlying pointer.
    pub fn unwrapOwned(self: Self) *Term {
        return switch (self) {
            .owned => |owned| owned,
            .referenced => std.debug.panic(
                "tried to unwrap `TermCow.reference` as `TermCow.owned`",
                .{},
            ),
        };
    }

    /// Same as `unwrapOwned`, but also asserts that all descendants are
    /// *owned*.
    pub fn unwrapOwnedAll(self: Self) *Term {
        const owned = self.unwrapOwned();
        switch (owned.value) {
            .unresolved, .local, .global => {},
            .group => |inner| {
                _ = inner.unwrapOwnedAll();
            },
            .abstraction => |abstr| {
                _ = abstr.body.unwrapOwnedAll();
            },
            .application => |appl| {
                _ = appl.function.unwrapOwnedAll();
                _ = appl.argument.unwrapOwnedAll();
            },
        }
        return owned;
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
        group: TermCow,
        abstraction: Abstr,
        application: Appl,
    };

    pub const Abstr = struct {
        /// Used for resolution and reduction.
        /// Referred to by `ParamRef`.
        parameter: SourceSpan,
        body: TermCow,
    };

    pub const Appl = struct {
        function: TermCow,
        argument: TermCow,
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
