const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const Reporter = @import("Reporter.zig");
const Span = @import("Span.zig");

const model = @import("model.zig");
const AbstrId = model.AbstrId;
const DeclIndex = model.DeclIndex;
const DeclEntry = model.DeclEntry;
const Term = model.Term;

pub fn checkDeclarationCollisions(declarations: []const DeclEntry) void {
    for (declarations, 0..) |current, i| {
        for (declarations[0..i], 0..) |prior, j| {
            if (i == j) {
                continue;
            }

            const current_value = current.decl.name.string();
            const prior_value = prior.decl.name.string();

            if (std.mem.eql(u8, current_value, prior_value)) {
                Reporter.report(
                    "global already declared",
                    "cannot redeclare `{s}` as a global",
                    .{prior_value},
                    // FIXME: Include individual decl contexts
                    .{ .symbol_reference = .{
                        .declaration = prior.decl.name,
                        .reference = current.decl.name,
                    } },
                );
            }
        }
    }
}

pub fn patchSymbols(
    term: *Term,
    locals: *LocalStore,
    declarations: []const DeclEntry,
) Allocator.Error!void {
    switch (term.value) {
        .unresolved => {
            if (resolveSymbol(term.span, locals, declarations)) |resolved| {
                term.* = resolved;
            } else {
                Reporter.report(
                    "unresolved symbol",
                    "`{s}` was not declared a global or a parameter in this scope",
                    .{term.span.string()},
                    .{ .token = term.span },
                );
            }
        },
        .group => |inner| {
            try patchSymbols(inner, locals, declarations);
        },
        .abstraction => |abstr| {
            const value = abstr.parameter.string();
            if (resolveLocal(locals, value)) |prior_term| {
                const prior_param = switch (prior_term.value) {
                    .abstraction => |prior_abstr| prior_abstr.parameter,
                    else => unreachable,
                };
                Reporter.report(
                    "parameter already declared as a variable in this scope",
                    "cannot shadow existing variable `{s}`",
                    .{abstr.parameter.string()},
                    .{ .symbol_reference = .{
                        .declaration = prior_param,
                        .reference = abstr.parameter,
                    } },
                );
            }
            if (resolveGlobal(declarations, value)) |global_index| {
                Reporter.report(
                    "parameter already declared as a global",
                    "cannot shadow existing global declaration `{s}`",
                    .{abstr.parameter.string()},
                    .{ .symbol_reference = .{
                        .declaration = declarations[global_index].decl.name,
                        .reference = abstr.parameter,
                    } },
                );
            }
            try locals.push(term, value);
            try patchSymbols(abstr.body, locals, declarations);
            locals.pop();
        },
        .application => |appl| {
            try patchSymbols(appl.function, locals, declarations);
            try patchSymbols(appl.argument, locals, declarations);
        },
        // No symbols in this branch should be resolved yet
        .local => unreachable,
        .global => unreachable,
    }
}

// TODO: Rename `resolve*` to avoid confusion with `resolve.zig`

fn resolveSymbol(
    span: Span,
    locals: *const LocalStore,
    declarations: []const DeclEntry,
) ?Term {
    const value = span.string();
    if (resolveLocal(locals, value)) |term| {
        // Assumes `term` is `abstraction`
        const id = term.value.abstraction.id;
        return Term{
            .span = span,
            .value = .{ .local = id },
        };
    }
    if (resolveGlobal(declarations, value)) |index| {
        return Term{
            .span = span,
            .value = .{ .global = index },
        };
    }
    return null;
}

fn resolveLocal(
    locals: *const LocalStore,
    value: []const u8,
) ?*Term {
    for (locals.entries.items) |entry| {
        if (std.mem.eql(u8, entry.value, value)) {
            return entry.term;
        }
    }
    return null;
}

fn resolveGlobal(
    declarations: []const DeclEntry,
    value: []const u8,
) ?DeclIndex {
    for (declarations, 0..) |*entry, i| {
        const decl_value = entry.decl.name.string();
        if (std.mem.eql(u8, decl_value, value)) {
            return i;
        }
    }
    return null;
}

/// Temporary reusable stack for local variables in a statement.
pub const LocalStore = struct {
    const Self = @This();

    entries: ArrayList(Entry),

    pub const Entry = struct {
        term: *Term,
        value: []const u8,
    };

    pub fn init(allocator: Allocator) Self {
        return .{
            .entries = ArrayList(Entry).init(allocator),
        };
    }

    pub fn deinit(self: *const Self) void {
        self.entries.deinit();
    }

    pub fn isEmpty(self: *const Self) bool {
        return self.entries.items.len == 0;
    }

    pub fn push(
        self: *Self,
        term: *Term,
        value: []const u8,
    ) Allocator.Error!void {
        try self.entries.append(.{
            .term = term,
            .value = value,
        });
    }

    pub fn pop(self: *Self) void {
        _ = self.entries.pop();
    }
};
