const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const Reporter = @import("Reporter.zig");
const Span = @import("Span.zig");

const Context = @import("Context.zig");
const model = @import("model.zig");
const Decl = model.Decl;
const DeclIndex = model.DeclIndex;
const TermIndex = model.TermIndex;
const TermStore = model.TermStore;
const Term = model.Term;

pub fn checkDeclarationCollisions(
    declarations: []const Decl,
    context: *const Context,
) void {
    for (declarations, 0..) |current, i| {
        for (declarations[0..i], 0..) |prior, j| {
            if (i == j) {
                continue;
            }
            if (std.mem.eql(u8, current.name.in(context.text), prior.name.in(context.text))) {
                Reporter.report(
                    "global already declared",
                    "cannot redeclare `{s}` as a global",
                    .{prior.name.in(context.text)},
                    .{ .symbol_reference = .{
                        .declaration = prior.name,
                        .reference = current.name,
                    } },
                    context,
                );
            }
        }
    }
}

pub fn patchSymbols(
    index: TermIndex,
    context: *const Context,
    terms: *TermStore,
    locals: *LocalStore,
    declarations: []const Decl,
) Allocator.Error!void {
    const term = terms.getMut(index);
    switch (term.value) {
        .unresolved => {
            if (resolveSymbol(term.span, context.text, locals, declarations)) |resolved| {
                term.* = resolved;
            } else {
                Reporter.report(
                    "unresolved symbol",
                    "`{s}` was not declared a global or a parameter in this scope",
                    .{term.span.in(context.text)},
                    .{ .token = term.span },
                    context,
                );
            }
        },
        .group => |inner| {
            try patchSymbols(inner, context, terms, locals, declarations);
        },
        .abstraction => |abstr| {
            const value = abstr.parameter.in(context.text);
            if (resolveLocal(locals, value)) |prior_index| {
                const prior_param = switch (terms.get(prior_index).value) {
                    .abstraction => |prior_abstr| prior_abstr.parameter,
                    else => unreachable,
                };
                Reporter.report(
                    "parameter already declared as a variable in this scope",
                    "cannot shadow existing variable `{s}`",
                    .{abstr.parameter.in(context.text)},
                    .{ .symbol_reference = .{
                        .declaration = prior_param,
                        .reference = abstr.parameter,
                    } },
                    context,
                );
            }
            if (resolveGlobal(declarations, value, context.text)) |global_index| {
                Reporter.report(
                    "parameter already declared as a global",
                    "cannot shadow existing global declaration `{s}`",
                    .{abstr.parameter.in(context.text)},
                    .{ .symbol_reference = .{
                        .declaration = declarations[global_index].name,
                        .reference = abstr.parameter,
                    } },
                    context,
                );
            }
            try locals.push(index, value);
            try patchSymbols(abstr.body, context, terms, locals, declarations);
            locals.pop();
        },
        .application => |appl| {
            try patchSymbols(appl.function, context, terms, locals, declarations);
            try patchSymbols(appl.argument, context, terms, locals, declarations);
        },
        // No symbols in this branch should be resolved yet
        .local => unreachable,
        .global => unreachable,
    }
}

fn resolveSymbol(
    span: Span,
    text: []const u8,
    locals: *const LocalStore,
    declarations: []const Decl,
) ?Term {
    const value = span.in(text);
    if (resolveLocal(locals, value)) |index| {
        return Term{
            .span = span,
            .value = .{ .local = index },
        };
    }
    if (resolveGlobal(declarations, value, text)) |index| {
        return Term{
            .span = span,
            .value = .{ .global = index },
        };
    }
    return null;
}

fn resolveLocal(locals: *const LocalStore, value: []const u8) ?TermIndex {
    for (locals.entries.items) |item| {
        if (std.mem.eql(u8, item.value, value)) {
            return item.index;
        }
    }
    return null;
}

fn resolveGlobal(
    declarations: []const Decl,
    value: []const u8,
    text: []const u8,
) ?DeclIndex {
    for (declarations, 0..) |*decl, i| {
        if (std.mem.eql(u8, decl.name.in(text), value)) {
            return i;
        }
    }
    return null;
}

/// Temporary reusable stack for local variables in a statement.
pub const LocalStore = struct {
    const Self = @This();

    entries: ArrayList(Entry),

    const Entry = struct {
        index: TermIndex,
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
        index: TermIndex,
        value: []const u8,
    ) Allocator.Error!void {
        try self.entries.append(.{
            .index = index,
            .value = value,
        });
    }

    pub fn pop(self: *Self) void {
        _ = self.entries.pop();
    }
};
