const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const assert = std.debug.assert;

const Span = @import("Span.zig");

pub const DeclIndex = usize;

pub const AbstrId = usize;

pub const Decl = struct {
    name: Span,
    term: *Term,
};

pub const Query = struct {
    term: *Term,
};

pub const Term = struct {
    const Self = @This();

    span: Span,
    value: Kind,

    const Kind = union(enum) {
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

    /// *Deep-copy* self by allocating and copying children.
    /// Copy of `.local` refers to *original* abstraction definition
    pub fn clone(self: *Self, allocator: Allocator) Allocator.Error!*Term {
        const copy_value = switch (self.value) {
            .unresolved, .global, .local => self.value,
            .group => |inner| Kind{
                .group = try inner.clone(allocator),
            },
            .abstraction => |abstr| Kind{
                .abstraction = .{
                    .id = abstr.id,
                    .parameter = abstr.parameter,
                    .body = try abstr.body.clone(allocator),
                },
            },
            .application => |appl| Kind{
                .application = .{
                    .function = try appl.function.clone(allocator),
                    .argument = try appl.argument.clone(allocator),
                },
            },
        };
        return try Self.create(self.span, copy_value, allocator);
    }
};
