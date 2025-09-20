const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const model = @import("model.zig");
const Decl = model.Decl;
const Term = model.Term;
const TermCow = model.TermCow;
const TermStore = model.TermStore;

const TextStore = @import("text/TextStore.zig");
const SourceSpan = TextStore.SourceSpan;

const Reporter = @import("Reporter.zig");

// TODO: Rename
const MAX_REDUCTION_RECURSION = 200;
const MAX_GLOBAL_EXPAND = 200;

const ReductionError = Allocator.Error || error{DepthCutoff};

const Mode = enum { lazy, greedy };

/// Returns `null` if recursion limit was reached.
pub fn reduceTerm(
    term: TermCow,
    mode: Mode,
    decls: []const Decl,
    term_store: *TermStore,
) Allocator.Error!?TermCow {
    return reduceTermInner(
        term,
        mode,
        0,
        decls,
        term_store,
    ) catch |err| switch (err) {
        error.DepthCutoff => return null,
        else => |other_err| return other_err,
    };
}

fn reduceTermInner(
    term: TermCow,
    mode: Mode,
    depth: usize,
    decls: []const Decl,
    term_store: *TermStore,
) ReductionError!TermCow {
    if (depth >= MAX_REDUCTION_RECURSION) {
        return error.DepthCutoff;
    }
    return switch (term.asConst().value) {
        .local => term,
        .global => |global| {
            if (mode == .lazy) {
                return term;
            }
            return reduceTermInner(
                decls[global].term,
                mode,
                depth + 1,
                decls,
                term_store,
            );
        },
        .abstraction => |abstr| {
            if (mode == .lazy) {
                return term;
            }
            // TODO: `reduceTermInner` should return `null` if nothing changed
            const body = try reduceTermInner(
                abstr.body,
                mode,
                depth + 1,
                decls,
                term_store,
            );
            return try term_store.create(null, .{
                .abstraction = .{
                    .parameter = abstr.parameter,
                    .body = body,
                },
            });
        },
        // Flatten group
        .group => |inner| try reduceTermInner(
            inner,
            mode,
            depth + 1,
            decls,
            term_store,
        ),
        .application => |*appl| try reduceApplication(
            appl,
            mode,
            depth + 1,
            decls,
            term_store,
        ) orelse {
            if (mode == .lazy) {
                return term;
            }
            // TODO: `reduceTermInner` should return `null` if nothing changed
            const argument = try reduceTermInner(
                appl.argument,
                mode,
                depth + 1,
                decls,
                term_store,
            );
            return try term_store.create(null, .{
                .application = .{
                    .function = appl.function,
                    .argument = argument,
                },
            });
        },
        .unresolved => std.debug.panic("symbol should have been resolved already", .{}),
    };
}

fn reduceApplication(
    appl: *const Term.Appl,
    mode: Mode,
    depth: usize,
    decls: []const Decl,
    term_store: *TermStore,
) ReductionError!?TermCow {
    const function_term = try reduceTermInner(
        appl.function,
        mode,
        depth + 1,
        decls,
        term_store,
    );

    switch (function_term.asConst().value) {
        .global, .abstraction => {},
        else => return null,
    }

    const function = try expandGlobal(
        function_term,
        mode,
        depth,
        decls,
        term_store,
    );

    const product = try betaReduce(
        function.body,
        function.parameter,
        appl.argument.asConst(),
        term_store,
    ) orelse function.body;

    switch (product.asConst().value) {
        .global, .local, .abstraction, .application => {},
        .unresolved => std.debug.panic("symbol should have been resolved already", .{}),
        .group => std.debug.panic("group should have been flattened already", .{}),
    }

    return try reduceTermInner(
        product,
        mode,
        depth + 1,
        decls,
        term_store,
    );
}

pub fn expandGlobalOnce(
    term: *const Term,
    decls: []const Decl,
) *const Term {
    return switch (term.value) {
        .unresolved => std.debug.panic("symbol should have been resolved already", .{}),
        .local => std.debug.panic("local binding should have been beta-reduced already", .{}),
        .global => |global| decls[global].term,
        // Flatten group
        .group => |inner| inner,
        .abstraction, .application => term,
    };
}

fn expandGlobal(
    initial_term: TermCow,
    mode: Mode,
    depth: usize,
    decls: []const Decl,
    term_store: *TermStore,
) ReductionError!*const Term.Abstr {
    var term = initial_term;
    for (0..MAX_GLOBAL_EXPAND) |_| {
        const product = try reduceTermInner(
            term,
            mode,
            depth + 1,
            decls,
            term_store,
        );
        term = switch (product.asConst().value) {
            .unresolved => std.debug.panic("symbol should have been resolved already", .{}),
            .local => std.debug.panic("local binding should have been beta-reduced already", .{}),
            .application => std.debug.panic("application should have been resolved already", .{}),
            .global => |global| decls[global].term,
            .group => |inner| inner,
            .abstraction => |*abstr| {
                return abstr;
            },
        };
    }
    return error.DepthCutoff;
}

/// Returns `null` if no descendant term was substituted; no need to deep-copy.
fn betaReduce(
    term: TermCow,
    abstr_param: SourceSpan,
    applied_argument: *const Term,
    term_store: *TermStore,
) Allocator.Error!?TermCow {
    switch (term.asConst().value) {
        .unresolved => std.debug.panic("symbol should have been resolved already", .{}),
        .global => return null,
        .local => |param| {
            if (param.offset == abstr_param.free.offset //
            and param.source.equals(abstr_param.source)) {
                return try deepCopyTerm(applied_argument, term_store);
            } else {
                return null;
            }
        },
        .group => |inner| {
            // Flatten group
            return try betaReduce(
                inner,
                abstr_param,
                applied_argument,
                term_store,
            );
        },
        .abstraction => |abstr| {
            const body = try betaReduce(
                abstr.body,
                abstr_param,
                applied_argument,
                term_store,
            ) orelse {
                return null;
            };
            return try term_store.create(null, .{
                .abstraction = .{
                    .parameter = abstr.parameter,
                    .body = body,
                },
            });
        },
        .application => |appl| {
            const function = try betaReduce(
                appl.function,
                abstr_param,
                applied_argument,
                term_store,
            );
            const argument = try betaReduce(
                appl.argument,
                abstr_param,
                applied_argument,
                term_store,
            );
            if (function == null and argument == null) {
                return null;
            }
            return try term_store.create(null, .{
                .application = .{
                    .function = function orelse appl.function,
                    .argument = argument orelse appl.argument,
                },
            });
        },
    }
}

/// *Deep-copy* term by allocating and copying children.
/// Does not copy non-parent terms (`global` and `local`), since they should be
/// not be mutated by the caller.
// TODO: Move to `TermCow` ?
fn deepCopyTerm(term: *Term, term_store: *TermStore) Allocator.Error!*Term {
    const copy_value: Term.Kind = switch (term.value) {
        .unresolved => std.debug.panic("symbol should have been resolved already", .{}),
        .global, .local => return term,
        .group => |inner| {
            // Flatten group
            return try deepCopyTerm(inner, term_store);
        },
        .abstraction => |abstr| .{
            .abstraction = .{
                .parameter = abstr.parameter,
                .body = try deepCopyTerm(abstr.body, term_store),
            },
        },
        .application => |appl| .{
            .application = .{
                .function = try deepCopyTerm(appl.function, term_store),
                .argument = try deepCopyTerm(appl.argument, term_store),
            },
        },
    };
    return try term_store.create(term.span, copy_value);
}
