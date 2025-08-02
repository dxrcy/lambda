const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const Span = @import("Span.zig");

const model = @import("model.zig");
const Decl = model.Decl;
const DeclIndex = model.DeclIndex;
const TermIndex = model.TermIndex;
const TermStore = model.TermStore;
const Term = model.Term;

const SymbolError = error{UndefinedSymbol};

pub fn patchSymbols(
    index: TermIndex,
    text: []const u8,
    terms: *TermStore,
    locals: *LocalStore,
    declarations: []const Decl,
) (SymbolError || Allocator.Error)!void {
    const term = terms.getMut(index);
    switch (term.*) {
        .unresolved => |span| {
            term.* = try resolveSymbol(span, text, locals, declarations);
        },
        .abstraction => |abstr| {
            const value = abstr.parameter.in(text);
            try locals.add(index, value);
            defer locals.pop();
            try patchSymbols(abstr.right, text, terms, locals, declarations);
        },
        .application => |appl| {
            try patchSymbols(appl.left, text, terms, locals, declarations);
            try patchSymbols(appl.right, text, terms, locals, declarations);
        },
        .group => |group| {
            try patchSymbols(group.inner, text, terms, locals, declarations);
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
) SymbolError!Term {
    const value = span.in(text);
    if (resolveLocal(locals, value)) |index| {
        return Term{
            .local = .{ .span = span, .index = index },
        };
    }
    if (resolveGlobal(declarations, value, text)) |index| {
        return Term{
            .global = .{ .span = span, .index = index },
        };
    }
    return error.UndefinedSymbol;
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

    pub fn add(
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
