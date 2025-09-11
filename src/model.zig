const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const assert = std.debug.assert;

const Span = @import("Span.zig");

pub const DeclIndex = usize;

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
        local: *Term,
        global: DeclIndex,
        group: *Term,
        abstraction: Abstr,
        application: Appl,

        const Abstr = struct {
            parameter: Span,
            body: *Term,
        };
        const Appl = struct {
            function: *Term,
            argument: *Term,
        };
    };
};
