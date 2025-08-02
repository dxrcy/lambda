const std = @import("std");
const fs = std.fs;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const Parser = @import("Parser.zig");
const Span = @import("Span.zig");
const Statements = @import("Statements.zig");
const Tokenizer = @import("Tokenizer.zig");
const utils = @import("utils.zig");

const model = @import("model.zig");
const Decl = model.Decl;
const TermStore = model.TermStore;
const Term = model.Term;

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const filepath = "example";
    const text = try utils.readFile(filepath, allocator);
    defer text.deinit();

    var decls = ArrayList(Decl).init(allocator);
    defer decls.deinit();

    var term_store = TermStore.init(allocator);
    defer term_store.deinit();

    var stmts = Statements.new(text.items);
    while (stmts.next()) |stmt| {
        var parser = Parser.new(text.items, stmt);
        const decl = try parser.tryDeclaration(&term_store) orelse {
            continue;
        };
        try decls.append(decl);
    }

    var local_vars = LocalStore.init(allocator);
    defer local_vars.deinit();

    for (decls.items) |*decl| {
        local_vars.clearRetainingCapacity();
        try patchSymbols(decl.term, text.items, &term_store, &local_vars, decls.items);
        std.debug.assert(local_vars.items.len == 0);
    }

    // TODO(feat): In same pass resolve local variables to point to the corresponding parameter

    for (decls.items, 0..) |*decl, i| {
        std.debug.print("\n[{}] {s}\n", .{ i, decl.name.in(text.items) });
        const term = term_store.getMut(decl.term);
        term.debug(term_store.entries.items, text.items);
        std.debug.print("\n", .{});
    }
}

const GlobalError = error{UndefinedVariable} || Allocator.Error;

const LocalStore = ArrayList(struct {
    index: model.TermIndex,
    value: []const u8,
});

fn patchSymbols(index: model.TermIndex, text: []const u8, terms: *TermStore, locals: *LocalStore, declarations: []const Decl) GlobalError!void {
    const term = terms.getMut(index);
    switch (term.*) {
        .unresolved => |span| {
            term.* = try resolveSymbol(span, text, locals, declarations);
        },
        .abstraction => |abstr| {
            const value = abstr.variable.in(text);
            try locals.append(.{
                .index = index,
                .value = value,
            });
            try patchSymbols(abstr.right, text, terms, locals, declarations);
            _ = locals.pop();
        },
        .application => |appl| {
            try patchSymbols(appl.left, text, terms, locals, declarations);
            try patchSymbols(appl.right, text, terms, locals, declarations);
        },
        .group => |group| {
            try patchSymbols(group.inner, text, terms, locals, declarations);
        },
        .local => unreachable,
        .global => unreachable,
    }
}

fn resolveSymbol(span: Span, text: []const u8, locals: *const LocalStore, declarations: []const Decl) !Term {
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
    return error.UndefinedVariable;
}

fn resolveLocal(list: *const LocalStore, target: []const u8) ?model.TermIndex {
    for (list.items) |item| {
        if (std.mem.eql(u8, item.value, target)) {
            return item.index;
        }
    }
    return null;
}

fn resolveGlobal(declarations: []const Decl, value: []const u8, text: []const u8) ?model.DeclIndex {
    for (declarations, 0..) |*decl, i| {
        if (std.mem.eql(u8, decl.name.in(text), value)) {
            return i;
        }
    }
    return null;
}
