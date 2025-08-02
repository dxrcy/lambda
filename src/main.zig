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
        std.debug.print("\nname: {s}\n", .{decl.name.in(text.items)});
        const term = term_store.get(decl.term);
        term.debug(term_store.entries.items, text.items);
        try decls.append(decl);
    }

    // for (decls.items) |decl| {
    //     std.debug.print("\nname: {s}\n", .{decl.name.in(text.items)});
    //     const term = term_store.get(decl.term);
    //     term.debug(term_store.entries.items, text.items);
    //
    //     var local_vars = ArrayList([]const u8).init(allocator);
    //     defer local_vars.deinit();
    //
    //     try findGlobalVariables(term, text.items, &term_store, &local_vars);
    // }
}

fn findGlobalVariables(term: *const Term, text: []const u8, store: *TermStore, locals: *ArrayList([]const u8)) !void {
    switch (term.*) {
        .variable => |span| {
            const value = span.in(text);
            if (!containsString(locals.items, value)) {
                std.debug.print("[{s}]\n", .{value});
            }
        },
        .abstraction => |abstr| {
            const value = abstr.variable.in(text);
            try locals.append(value);
            try findGlobalVariables(store.get(abstr.right), text, store, locals);
        },
        .application => |appl| {
            try findGlobalVariables(store.get(appl.left), text, store, locals);
            try findGlobalVariables(store.get(appl.right), text, store, locals);
        },
        .group => |group| {
            try findGlobalVariables(store.get(group.inner), text, store, locals);
        },
    }
}

fn containsString(list: []const []const u8, target: []const u8) bool {
    for (list) |item| {
        if (std.mem.eql(u8, item, target)) {
            return true;
        }
    }
    return false;
}
