const Slice = []const u8;

const Decl = struct {
    name: Slice,
    term: Term,
};

const Term = union(enum) {
    variable: Slice,
    abstraction: Abstr,
    application: Appl,

    const Abstr = struct {
        variable: Slice,
        term: Term,
    };
    const Appl = struct {
        variable: Slice,
        term: Term,
    };
};
