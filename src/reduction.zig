const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const model = @import("model.zig");
const AbstrId = model.AbstrId;
const Decl = model.Decl;
const Term = model.Term;

const TextStore = @import("text/TextStore.zig");
const SourceSpan = TextStore.SourceSpan;

const Reporter = @import("Reporter.zig");

// TODO: Rename
const MAX_REDUCTION_RECURSION = 2_000;
const MAX_GLOBAL_EXPAND = 200;

const ReductionError = Allocator.Error || error{DepthCutoff};

/// Requires that `Param`, `Input`, and `Output` are all pointers.
/// Requires that `Input` and `Output` are non-`const` (for consistency).
/// Requires that `Param` points to the same type that `Input` does (although
/// `Param` may be `const`).
/// Returns a pointer equivalent to `Output`, but with the `const`-ness of `Param`
fn PointerMaybeConst(
    comptime Param: type,
    comptime Input: type,
    comptime Output: type,
) type {
    const param = @typeInfo(Param);
    var input = @typeInfo(Input);
    var output = @typeInfo(Output);

    if (input.pointer.is_const or output.pointer.is_const) {
        @compileError("Input and output pointers must be non-const");
    }

    input.pointer.is_const = param.pointer.is_const;
    output.pointer.is_const = param.pointer.is_const;

    if (@Type(param) != @Type(input)) {
        @compileError("Input pointer does not match parameter pointer");
    }

    return @Type(output);
}

/// Returns `null` if recursion limit was reached.
pub fn reduceTerm(
    term: anytype,
    decls: []const Decl,
    term_allocator: Allocator,
    text: *const TextStore,
    reporter: *Reporter,
) Allocator.Error!?PointerMaybeConst(@TypeOf(term), *Term, *Term) {
    return reduceTermInner(
        term,
        0,
        decls,
        term_allocator,
    ) catch |err|
        switch (err) {
            error.DepthCutoff => {
                // TODO: Handle this
                const span = term.span orelse {
                    std.debug.panic("unimplemented", .{});
                };

                reporter.report(
                    "recursion limit reached when expanding term",
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

fn reduceTermInner(
    term: anytype,
    depth: usize,
    decls: []const Decl,
    term_allocator: Allocator,
) ReductionError!PointerMaybeConst(@TypeOf(term), *Term, *Term) {
    if (depth >= MAX_REDUCTION_RECURSION) {
        return error.DepthCutoff;
    }
    return switch (term.value) {
        .local, .global => term,
        .abstraction => |abstr| {
            // TODO: `reduceTermInner` should return `null` if nothing changed
            const body = try reduceTermInner(
                abstr.body,
                depth + 1,
                decls,
                term_allocator,
            );
            return try Term.create(null, .{
                .abstraction = .{
                    .parameter = abstr.parameter,
                    .body = body,
                },
            }, term_allocator);
        },
        // Flatten group
        .group => |inner| try reduceTermInner(
            inner,
            depth + 1,
            decls,
            term_allocator,
        ),
        .application => |*appl| try reduceApplication(
            appl,
            depth + 1,
            decls,
            term_allocator,
        ) orelse term,
        .unresolved => std.debug.panic("symbol should have been resolved already", .{}),
    };
}

fn reduceApplication(
    appl: anytype,
    depth: usize,
    decls: []const Decl,
    term_allocator: Allocator,
) ReductionError!?PointerMaybeConst(@TypeOf(appl), *Term.Appl, *Term) {
    const function_term = try reduceTermInner(
        appl.function,
        depth + 1,
        decls,
        term_allocator,
    );

    switch (function_term.value) {
        .global, .abstraction => {},
        else => return null,
    }

    const function = try expandGlobal(
        function_term,
        depth,
        decls,
        term_allocator,
    );

    const product = try betaReduce(
        function.body,
        function.parameter,
        appl.argument,
        term_allocator,
    ) orelse function.body;

    switch (product.value) {
        .global, .abstraction, .application => {},
        .unresolved => std.debug.panic("symbol should have been resolved already", .{}),
        .local => std.debug.panic("local binding should have been beta-reduced already", .{}),
        .group => std.debug.panic("group should have been flattened already", .{}),
    }

    return reduceTermInner(
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
        .unresolved => std.debug.panic("symbol should have been resolved already", .{}),
        .local => std.debug.panic("local binding should have been beta-reduced already", .{}),
        .global => |global| decls[global].term,
        // Flatten group
        .group => |inner| inner,
        .abstraction, .application => term,
    };
}

fn expandGlobal(
    initial_term: anytype,
    depth: usize,
    decls: []const Decl,
    term_allocator: Allocator,
) ReductionError!PointerMaybeConst(@TypeOf(initial_term), *Term, *Term.Abstr) {
    var term = initial_term;
    for (0..MAX_GLOBAL_EXPAND) |_| {
        const product = try reduceTermInner(
            term,
            depth + 1,
            decls,
            term_allocator,
        );
        term = switch (product.value) {
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
    term: *Term,
    abstr_param: SourceSpan,
    applied_argument: *Term,
    term_allocator: Allocator,
) Allocator.Error!?*Term {
    switch (term.value) {
        .unresolved => std.debug.panic("symbol should have been resolved already", .{}),
        .global => return null,
        .local => |param| {
            if (param.offset == abstr_param.free.offset //
            and param.source.equals(abstr_param.source)) {
                return try deepCopyTerm(applied_argument, term_allocator);
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
                term_allocator,
            );
        },
        .abstraction => |abstr| {
            const body = try betaReduce(
                abstr.body,
                abstr_param,
                applied_argument,
                term_allocator,
            ) orelse {
                return null;
            };
            return try Term.create(null, .{
                .abstraction = .{
                    .parameter = abstr.parameter,
                    .body = body,
                },
            }, term_allocator);
        },
        .application => |appl| {
            const function = try betaReduce(
                appl.function,
                abstr_param,
                applied_argument,
                term_allocator,
            );
            const argument = try betaReduce(
                appl.argument,
                abstr_param,
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
        .unresolved => std.debug.panic("symbol should have been resolved already", .{}),
        .global, .local => return term,
        .group => |inner| {
            // Flatten group
            return try deepCopyTerm(inner, allocator);
        },
        .abstraction => |abstr| .{
            .abstraction = .{
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
