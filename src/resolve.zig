const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const model = @import("model.zig");
const AbstrId = model.AbstrId;
const Decl = model.Decl;
const Term = model.Term;

const TextStore = @import("TextStore.zig");
const SourceSpan = TextStore.SourceSpan;

const Reporter = @import("Reporter.zig");

const MAX_RESOLVE_RECURSION = 2_000;
const MAX_GLOBAL_EXPAND = 200;

const ResolveError = Allocator.Error || error{MaxRecursion};

// TODO: Replace `@panic` with `std.debug.panic` (and elsewhere)

/// Returns `null` if recursion limit was reached.
pub fn resolveTerm(
    term: *const Term,
    decls: []const Decl,
    term_allocator: Allocator,
    text: *const TextStore,
    reporter: *Reporter,
) Allocator.Error!?*const Term {
    assert(term.span != null);
    const span = term.span orelse unreachable;

    return resolveTermInner(term, 0, decls, term_allocator) catch |err|
        switch (err) {
            error.MaxRecursion => {
                reporter.report(
                    "recursion limit reached when expanding query",
                    "check for any reference cycles in declarations",
                    .{},
                    .{ .query = span },
                    text,
                );
                return null;
            },
            else => |other_err| return other_err,
        };
}

fn resolveTermInner(
    term: *const Term,
    depth: usize,
    decls: []const Decl,
    term_allocator: Allocator,
) ResolveError!*const Term {
    if (depth >= MAX_RESOLVE_RECURSION) {
        return error.MaxRecursion;
    }
    return switch (term.value) {
        .global, .abstraction => term,
        // Flatten group
        .group => |inner| try resolveTermInner(
            inner,
            depth + 1,
            decls,
            term_allocator,
        ),
        .application => |appl| try resolveApplication(
            &appl,
            depth + 1,
            decls,
            term_allocator,
        ),
        .unresolved => @panic("symbol should have been resolved already"),
        .local => @panic("local binding should have been beta-reduced already"),
    };
}

fn resolveApplication(
    appl: *const Term.Appl,
    depth: usize,
    decls: []const Decl,
    term_allocator: Allocator,
) ResolveError!*const Term {
    switch (appl.function.value) {
        .group, .global, .abstraction, .application => {},
        .unresolved => @panic("symbol should have been resolved already"),
        .local => @panic("local binding should have been beta-reduced already"),
    }

    const function = try expandGlobal(
        appl.function,
        depth,
        decls,
        term_allocator,
    );

    const product = try betaReduce(
        function.body,
        function.id,
        appl.argument,
        term_allocator,
    ) orelse function.body;

    switch (product.value) {
        .global, .abstraction, .application => {},
        .group => @panic("group should have been flattened already"),
        .unresolved => @panic("symbol should have been resolved already"),
        .local => @panic("local binding should have been beta-reduced already"),
    }

    return resolveTermInner(
        product,
        depth + 1,
        decls,
        term_allocator,
    );
}

pub fn expandGlobalOnce(
    term: *const Term,
    decls: []const Decl,
) *const Term {
    return switch (term.value) {
        .unresolved => @panic("symbol should have been resolved already"),
        .local => @panic("local binding should have been beta-reduced already"),
        .global => |global| decls[global].term,
        // Flatten group
        .group => |inner| inner,
        .abstraction, .application => term,
    };
}

fn expandGlobal(
    initial_term: *const Term,
    depth: usize,
    decls: []const Decl,
    term_allocator: Allocator,
) ResolveError!*const Term.Abstr {
    var term = initial_term;
    for (0..MAX_GLOBAL_EXPAND) |_| {
        const product = try resolveTermInner(
            term,
            depth + 1,
            decls,
            term_allocator,
        );
        term = switch (product.value) {
            .unresolved => @panic("symbol should have been resolved already"),
            .local => @panic("local binding should have been beta-reduced already"),
            .application => @panic("application should have been resolved already"),
            .global => |global| decls[global].term,
            .group => |inner| inner,
            .abstraction => |abstr| {
                return &abstr;
            },
        };
    }
    return error.MaxRecursion;
}

/// Returns `null` if no descendant term was substituted; no need to deep-copy.
fn betaReduce(
    term: *Term,
    abstr_id: AbstrId,
    applied_argument: *Term,
    term_allocator: Allocator,
) Allocator.Error!?*Term {
    switch (term.value) {
        .unresolved => @panic("symbol should have been resolved already"),
        .global => return null,
        .local => |id| {
            if (id != abstr_id) {
                return null;
            }
            return try deepCopyTerm(applied_argument, term_allocator);
        },
        .group => |inner| {
            // Flatten group
            return try betaReduce(
                inner,
                abstr_id,
                applied_argument,
                term_allocator,
            );
        },
        .abstraction => |abstr| {
            const body = try betaReduce(
                abstr.body,
                abstr_id,
                applied_argument,
                term_allocator,
            ) orelse {
                return null;
            };
            return try Term.create(null, .{
                .abstraction = .{
                    .id = abstr.id,
                    .parameter = abstr.parameter,
                    .body = body,
                },
            }, term_allocator);
        },
        .application => |appl| {
            const function = try betaReduce(
                appl.function,
                abstr_id,
                applied_argument,
                term_allocator,
            );
            const argument = try betaReduce(
                appl.argument,
                abstr_id,
                applied_argument,
                term_allocator,
            );
            if (function == null and argument == null) {
                return null;
            }
            return try Term.create(null, .{
                .application = .{
                    .function = function orelse appl.function,
                    .argument = argument orelse appl.argument,
                },
            }, term_allocator);
        },
    }
}

/// *Deep-copy* term by allocating and copying children.
/// Does not copy non-parent terms (`global` and `local`), since they should be
/// not be mutated by the caller.
fn deepCopyTerm(term: *Term, allocator: Allocator) Allocator.Error!*Term {
    const copy_value: Term.Kind = switch (term.value) {
        .unresolved => @panic("symbol should have been resolved already"),
        .global, .local => return term,
        .group => |inner| {
            // Flatten group
            return try deepCopyTerm(inner, allocator);
        },
        .abstraction => |abstr| .{
            .abstraction = .{
                .id = abstr.id,
                .parameter = abstr.parameter,
                .body = try deepCopyTerm(abstr.body, allocator),
            },
        },
        .application => |appl| .{
            .application = .{
                .function = try deepCopyTerm(appl.function, allocator),
                .argument = try deepCopyTerm(appl.argument, allocator),
            },
        },
    };
    return try Term.create(term.span, copy_value, allocator);
}
