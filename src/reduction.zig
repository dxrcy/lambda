const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const model = @import("model.zig");
const Decl = model.Decl;
const ParamRef = model.ParamRef;
const Term = model.Term;
const TermCow = model.TermCow;
const TermStore = model.TermStore;

const TextStore = @import("text/TextStore.zig");
const SourceSpan = TextStore.SourceSpan;

const Reporter = @import("Reporter.zig");

const MAX_REDUCTION_RECURSION = 200;
const MAX_EXPAND_ITERATION = 200;

const ReductionError = Allocator.Error || error{DepthCutoff};

const Mode = enum { lazy, greedy };

/// Returns `null` if recursion limit was reached.
pub fn reduceTerm(
    term: TermCow,
    mode: Mode,
    decls: []const Decl,
    term_store: *TermStore,
) Allocator.Error!?TermCow {
    const reducer = Reducer{
        .mode = mode,
        .decls = decls,
        .term_store = term_store,
    };
    return reducer.reduceTerm(term, false, 0) catch |err| switch (err) {
        error.DepthCutoff => return null,
        else => |other_err| return other_err,
    };
}

const Reducer = struct {
    const Self = @This();

    mode: Mode,
    decls: []const Decl,
    term_store: *TermStore,

    /// Depth should only be incremented when calling `reduceTerm` or
    /// `betaReduce`
    fn checkDepthLimit(depth: usize) error{DepthCutoff}!void {
        if (depth >= MAX_REDUCTION_RECURSION) {
            return error.DepthCutoff;
        }
    }

    fn reduceTerm(
        self: *const Self,
        term: TermCow,
        must_expand_global: bool,
        depth: usize,
    ) ReductionError!TermCow {
        try checkDepthLimit(depth);

        switch (term.asConst().value) {
            // Unreduced local binding cannot be reduced any further
            .local => return term,

            .global => |global| {
                if (self.mode == .lazy and !must_expand_global) {
                    return term;
                }
                // Expand globals recursively until expands to something else,
                // then reduce that term
                const expanded = self.decls[global].term.copyReference();
                return try self.reduceTerm(
                    expanded,
                    must_expand_global,
                    depth + 1,
                ) orelse expanded; // Note we don't return `null` in here
            },

            .group => |inner| {
                // Flatten group
                return self.reduceTerm(inner, must_expand_global, depth + 1);
            },

            .abstraction => |abstr| {
                if (self.mode == .lazy) {
                    return term;
                }
                // TODO:
                // Try to reduce body of abstraction
                _ = abstr;
                unreachable;
            },

            .application => |appl| {
                // Try to reduce application directly
                return try self.reduceApplication(&appl, depth) orelse {
                    if (self.mode == .lazy) {
                        return term;
                    }
                    // TODO:
                    // Try to reduce function and/or body of application
                    unreachable;
                };
            },

            .unresolved => std.debug.panic("symbol should have been resolved already", .{}),
        }
    }

    /// Returns `null` if function depends on an unreduced local binding.
    fn reduceApplication(
        self: *const Self,
        appl: *const Term.Appl,
        depth: usize,
    ) ReductionError!?TermCow {
        // Always expand global if it is an application function
        const function_term: TermCow = try self.reduceTerm(
            appl.function,
            true,
            depth + 1,
        ) orelse appl.function;

        // Cannot reduce application, if function depends on an unreduced local
        // binding (ie. is a local binding, or another application which cannot
        // be reduced for the same reason)
        // Also don't reduce global if it wasn't expanded
        const function_abstr: Term.Abstr = switch (function_term.asConst().value) {
            .abstraction => |abstr| abstr,
            .local, .application => return null,
            .global => if (self.mode == .lazy) {
                return null;
            } else {
                std.debug.panic("global binding should have been expanded already", .{});
            },
            .unresolved => std.debug.panic("symbol should have been resolved already", .{}),
            .group => std.debug.panic("group should have been flattened already", .{}),
        };

        const applied: TermCow = try self.betaReduce(
            ParamRef.from(function_abstr.parameter),
            function_abstr.body,
            appl.argument,
            depth + 1,
        ) orelse function_abstr.body;

        switch (applied.asConst().value) {
            .global, .local, .abstraction, .application => {},
            .unresolved => std.debug.panic("symbol should have been resolved already", .{}),
            .group => std.debug.panic("group should have been flattened already", .{}),
        }

        const reduced: TermCow = try self.reduceTerm(
            applied,
            false,
            depth + 1,
        ) orelse applied;

        return reduced;
    }

    /// Returns `null` if no beta-reduction occurred.
    // TODO: Add depth parameter
    fn betaReduce(
        self: *const Self,
        abstr_param: ParamRef,
        abstr_body: TermCow,
        appl_argument: TermCow,
        depth: usize,
    ) ReductionError!?TermCow {
        try checkDepthLimit(depth);

        switch (abstr_body.asConst().value) {
            .global => if (self.mode == .lazy) {
                return null;
            } else {
                std.debug.panic("global binding should have been expanded already", .{});
            },

            .local => |param| {
                // If local binding matches parameter, perform beta-reduction
                if (param.equals(abstr_param)) {
                    return try self.deepCopyTerm(appl_argument);
                } else {
                    return null;
                }
            },

            .group => |inner| {
                // Flatten group
                return self.betaReduce(
                    abstr_param,
                    inner,
                    appl_argument,
                    depth + 1,
                );
            },

            .abstraction => |abstr| {
                // Do nothing if body was NOT beta-reduced.
                const reduced_body: TermCow = try self.betaReduce(
                    abstr_param,
                    abstr.body,
                    appl_argument,
                    depth + 1,
                ) orelse {
                    return null;
                };

                return try self.term_store.createOrReuse(
                    abstr_body,
                    null,
                    .{ .abstraction = .{
                        .parameter = abstr.parameter,
                        .body = reduced_body,
                    } },
                );
            },

            .application => |appl| {
                // Do nothing if function AND argument were NOT beta-reduced.
                const reduced_function: ?TermCow = try self.betaReduce(
                    abstr_param,
                    appl.function,
                    appl_argument,
                    depth + 1,
                );
                const reduced_argument: ?TermCow = try self.betaReduce(
                    abstr_param,
                    appl.argument,
                    appl_argument,
                    depth + 1,
                );

                if (reduced_function == null and reduced_argument == null) {
                    return null;
                }

                return try self.term_store.createOrReuse(
                    abstr_body,
                    null,
                    .{ .application = .{
                        .function = reduced_function orelse appl.function.copyReference(),
                        .argument = reduced_argument orelse appl.argument.copyReference(),
                    } },
                );
            },

            .unresolved => std.debug.panic("symbol should have been resolved already", .{}),
        }
    }

    fn deepCopyTerm(self: *const Self, term: TermCow) Allocator.Error!TermCow {
        // PERF: We can probably avoid redundant copies of terms whos
        // descendants are all referenced, since any later modification to a
        // referenced descendant will require copying it to make it owned.
        // And possibly other unnecessary cases are present.

        const copy_value: Term.Kind = switch (term.asConst().value) {
            .global, .local => return term,

            .group => |inner| {
                // Flatten group
                return try self.deepCopyTerm(inner);
            },

            .abstraction => |abstr| .{
                .abstraction = .{
                    .parameter = abstr.parameter,
                    .body = try self.deepCopyTerm(abstr.body),
                },
            },

            .application => |appl| .{
                .application = .{
                    .function = try self.deepCopyTerm(appl.function),
                    .argument = try self.deepCopyTerm(appl.argument),
                },
            },

            .unresolved => std.debug.panic("symbol should have been resolved already", .{}),
        };

        return try self.term_store.create(term.asConst().span, copy_value);
    }
};
