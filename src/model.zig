const Span = @import("Span.zig");

pub const Decl = struct {
    span: Span,
    name: Span,
    term: Term,
};

pub const Term = union(enum) {
    variable: Span,
    abstraction: Abstr,
    application: Appl,

    const Abstr = struct {
        variable: Span,
        term: *const Term,
    };
    const Appl = struct {
        variable: Span,
        term: *const Term,
    };
};
