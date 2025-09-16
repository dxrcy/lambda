const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const model = @import("model.zig");
const DeclIndex = model.DeclIndex;
const Decl = model.Decl;
const ParamRef = model.ParamRef;
const Term = model.Term;

const TextStore = @import("text/TextStore.zig");
const SourceSpan = TextStore.SourceSpan;

const Reporter = @import("Reporter.zig");

pub fn checkDeclarationCollisions(
    declarations: []const Decl,
    text: *const TextStore,
    reporter: *Reporter,
) void {
    for (declarations, 0..) |current, i| {
        for (declarations[0..i], 0..) |prior, j| {
            if (i == j) {
                continue;
            }

            const current_value = current.name.in(text);
            const prior_value = prior.name.in(text);

            if (std.mem.eql(u8, current_value, prior_value)) {
                reporter.report(
                    "global already declared",
                    "cannot redeclare `{s}` as a global",
                    .{prior_value},
                    .{ .symbol_reference = .{
                        .declaration = prior.name,
                        .reference = current.name,
                    } },
                    text,
                );
            }
        }
    }
}

pub fn resolveAllSymbols(
    term: *Term,
    locals: *LocalStore,
    declarations: []const Decl,
    text: *const TextStore,
    reporter: *Reporter,
) Allocator.Error!void {
    std.debug.assert(locals.isEmpty());
    try resolveSymbolsInner(term, locals, declarations, text, reporter);
    std.debug.assert(locals.isEmpty());
}

fn resolveSymbolsInner(
    term: *Term,
    locals: *LocalStore,
    declarations: []const Decl,
    text: *const TextStore,
    reporter: *Reporter,
) Allocator.Error!void {
    switch (term.value) {
        .unresolved => {
            const span = term.span.?;
            if (resolveSymbol(span, locals, declarations, text)) |resolved| {
                term.* = resolved;
            } else {
                reporter.report(
                    "unresolved symbol",
                    "`{s}` was not declared a global or a parameter in this scope",
                    .{span.in(text)},
                    .{ .token = span },
                    text,
                );
            }
        },
        .group => |inner| {
            try resolveSymbolsInner(inner, locals, declarations, text, reporter);
        },
        .abstraction => |abstr| {
            const value = abstr.parameter.in(text);
            if (resolveLocal(locals, value)) |param| {
                reporter.report(
                    "parameter already declared as a variable in this scope",
                    "cannot shadow existing variable `{s}`",
                    .{abstr.parameter.in(text)},
                    .{ .symbol_reference = .{
                        .declaration = param,
                        .reference = abstr.parameter,
                    } },
                    text,
                );
            }
            if (resolveGlobal(declarations, value, text)) |global_index| {
                reporter.report(
                    "parameter already declared as a global",
                    "cannot shadow existing global declaration `{s}`",
                    .{abstr.parameter.in(text)},
                    .{ .symbol_reference = .{
                        .declaration = declarations[global_index].name,
                        .reference = abstr.parameter,
                    } },
                    text,
                );
            }
            try locals.push(abstr.parameter, value);
            try resolveSymbolsInner(abstr.body, locals, declarations, text, reporter);
            locals.pop();
        },
        .application => |appl| {
            try resolveSymbolsInner(appl.function, locals, declarations, text, reporter);
            try resolveSymbolsInner(appl.argument, locals, declarations, text, reporter);
        },
        // No symbols in this branch should be resolved yet
        .local => unreachable,
        .global => unreachable,
    }
}

fn resolveSymbol(
    span: SourceSpan,
    locals: *const LocalStore,
    declarations: []const Decl,
    text: *const TextStore,
) ?Term {
    const value = span.in(text);
    if (resolveLocal(locals, value)) |param| {
        return Term{
            .span = span,
            .value = .{ .local = .{
                .offset = param.free.offset,
                .source = param.source,
            } },
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

fn resolveLocal(
    locals: *const LocalStore,
    value: []const u8,
) ?SourceSpan {
    for (locals.entries.items) |entry| {
        if (std.mem.eql(u8, entry.value, value)) {
            return entry.param;
        }
    }
    return null;
}

fn resolveGlobal(
    declarations: []const Decl,
    value: []const u8,
    text: *const TextStore,
) ?DeclIndex {
    for (declarations, 0..) |*decl, i| {
        const decl_value = decl.name.in(text);
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
    allocator: Allocator,

    pub const Entry = struct {
        param: SourceSpan,
        value: []const u8,
    };

    pub fn init(allocator: Allocator) Self {
        return .{
            .entries = ArrayList(Entry).empty,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.entries.deinit(self.allocator);
    }

    pub fn isEmpty(self: *const Self) bool {
        return self.entries.items.len == 0;
    }

    pub fn push(
        self: *Self,
        param: SourceSpan,
        value: []const u8,
    ) Allocator.Error!void {
        try self.entries.append(self.allocator, .{
            .param = param,
            .value = value,
        });
    }

    pub fn pop(self: *Self) void {
        _ = self.entries.pop();
    }
};
