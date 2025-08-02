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

    var local_vars = ArrayList([]const u8).init(allocator);
    defer local_vars.deinit();

    for (decls.items) |*decl| {
        local_vars.clearRetainingCapacity();
        const term = term_store.getMut(decl.term);
        try patchGlobalVariable(term, text.items, decls.items, &term_store, &local_vars);
        std.debug.assert(local_vars.items.len == 0);
    }

    for (decls.items, 0..) |*decl, i| {
        std.debug.print("\n[{}] {s}\n", .{ i, decl.name.in(text.items) });
        const term = term_store.getMut(decl.term);
        term.debug(term_store.entries.items, text.items);
        std.debug.print("\n", .{});
    }
}

const GlobalError = error{UndefinedVariable} || Allocator.Error;

fn patchGlobalVariable(term: *Term, text: []const u8, declarations: []const Decl, store: *TermStore, locals: *ArrayList([]const u8)) GlobalError!void {
    if (try findGlobalVariables(term, text, declarations, store, locals)) {
        const span = term.getSpan();
        const value = span.in(text);
        const index = findDeclaration(declarations, value, text) orelse {
            return error.UndefinedVariable;
        };
        term.* = Term{
            .global = .{
                .span = span,
                .index = index,
            },
        };
    }
}

fn findDeclaration(declarations: []const Decl, value: []const u8, text: []const u8) ?model.DeclIndex {
    for (declarations, 0..) |*decl, i| {
        if (std.mem.eql(u8, decl.name.in(text), value)) {
            return i;
        }
    }
    return null;
}

fn findGlobalVariables(term: *Term, text: []const u8, declarations: []const Decl, store: *TermStore, locals: *ArrayList([]const u8)) GlobalError!bool {
    switch (term.*) {
        .variable => |span| {
            return !containsString(locals.items, span.in(text));
        },
        .abstraction => |abstr| {
            const value = abstr.variable.in(text);
            try locals.append(value);
            try patchGlobalVariable(store.getMut(abstr.right), text, declarations, store, locals);
            _ = locals.pop();
        },
        .application => |appl| {
            try patchGlobalVariable(store.getMut(appl.left), text, declarations, store, locals);
            try patchGlobalVariable(store.getMut(appl.right), text, declarations, store, locals);
        },
        .group => |group| {
            try patchGlobalVariable(store.getMut(group.inner), text, declarations, store, locals);
        },
        .global => unreachable,
    }
    return false;
}

fn containsString(list: []const []const u8, target: []const u8) bool {
    for (list) |item| {
        if (std.mem.eql(u8, item, target)) {
            return true;
        }
    }
    return false;
}
