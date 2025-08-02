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
        var parser = try Parser.new(text.items, stmt);
        const decl = try parser.tryDeclaration(&term_store) orelse {
            continue;
        };
        try decls.append(decl);
    }

    for (decls.items) |decl| {
        std.debug.print("\nname: {s}\n", .{decl.name.in(text.items)});
        const term = term_store.get(decl.term);
        term.debug(term_store.entries.items, text.items);
    }
}
