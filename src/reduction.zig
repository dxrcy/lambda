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
    return reducer.reduceTerm(term, 0) catch |err| switch (err) {
        error.DepthCutoff => return null,
        else => |other_err| return other_err,
    };
}

const Reducer = struct {
    const Self = @This();

    mode: Mode,
    decls: []const Decl,
    term_store: *TermStore,

    // `depth` should only be incremented in a recursive `reduceTerm` call; NOT
    // when calling other functions in this container.
    fn reduceTerm(
        self: *const Self,
        term: TermCow,
        depth: usize,
    ) ReductionError!TermCow {
        if (depth >= MAX_REDUCTION_RECURSION) {
            return error.DepthCutoff;
        }

        switch (term.asConst().value) {
            // Unreduced local binding cannot be reduced any further
            .local => return term,

            .global => |global| {
                if (self.mode == .lazy) {
                    return term;
                }
                // Expand global
                return self.reduceTerm(self.decls[global].term, depth + 1);
            },

            .group => |inner| {
                // Flatten group
                return self.reduceTerm(inner, depth + 1);
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

    /// Returns `null` if function is an unreduced local binding.
    fn reduceApplication(
        self: *const Self,
        appl: *const Term.Appl,
        depth: usize,
    ) ReductionError!?TermCow {
        const function_term = try self.reduceTerm(appl.function, depth + 1);

        // Cannot reduce application, if function is an unreduced local binding
        // Also don't reduce global if it wasn't expanded
        const function_abstr = switch (function_term.asConst().value) {
            .abstraction => |abstr| abstr,
            .local => return null,
            .global => if (self.mode == .lazy) {
                return null;
            } else {
                std.debug.panic("global binding should have been expanded already", .{});
            },
            .unresolved => std.debug.panic("symbol should have been resolved already", .{}),
            .group => std.debug.panic("group should have been flattened already", .{}),
            .application => std.debug.panic("application should have been resolved already", .{}),
        };

        const applied = try self.betaReduce(
            ParamRef.from(function_abstr.parameter),
            function_abstr.body,
            appl.argument,
        ) orelse function_abstr.body;

        switch (applied.asConst().value) {
            .global, .local, .abstraction, .application => {},
            .unresolved => std.debug.panic("symbol should have been resolved already", .{}),
            .group => std.debug.panic("group should have been flattened already", .{}),
        }

        return try self.reduceTerm(applied, depth + 1);
    }

    /// Returns `null` if no beta-reduction occurred.
    // TODO: Add depth parameter
    fn betaReduce(
        self: *const Self,
        abstr_param: ParamRef,
        abstr_body: TermCow,
        appl_argument: TermCow,
    ) Allocator.Error!?TermCow {
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
                );
            },

            .abstraction => |abstr| {
                // Do nothing if body was NOT beta-reduced.
                const reduced_body = try self.betaReduce(
                    abstr_param,
                    abstr.body,
                    appl_argument,
                ) orelse {
                    return null;
                };

                const owned_body = try abstr_body.toOwned(self.term_store);
                owned_body.unwrapOwned().* = Term{
                    .span = null,
                    .value = .{
                        .abstraction = .{
                            .parameter = abstr.parameter,
                            .body = reduced_body,
                        },
                    },
                };
                return owned_body;
            },

            .application => |appl| {
                // Do nothing if function AND argument were NOT beta-reduced.
                const reduced_function = try self.betaReduce(
                    abstr_param,
                    appl.function,
                    appl_argument,
                );
                const reduced_argument = try self.betaReduce(
                    abstr_param,
                    appl.argument,
                    appl_argument,
                );

                if (reduced_function == null and reduced_argument == null) {
                    return null;
                }

                const owned_body = try abstr_body.toOwned(self.term_store);
                owned_body.unwrapOwned().* = Term{
                    .span = null,
                    .value = .{
                        .application = .{
                            .function = reduced_function orelse appl.function,
                            .argument = reduced_argument orelse appl.argument,
                        },
                    },
                };
                return owned_body;
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
