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
const Term = model.Term;

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const filepath = "example";

    const text = try utils.readFile(filepath, allocator);
    defer text.deinit();

    var stmt_list = ArrayList(Span).init(allocator);
    defer stmt_list.deinit();

    var stmts = Statements.new(text.items);
    while (stmts.next()) |stmt| {
        try stmt_list.append(stmt);
    }

    { // debug
        var i: usize = 0;
        for (stmt_list.items) |stmt| {
            var tokens = Tokenizer.new(text.items, stmt);
            var j: usize = 0;
            while (tokens.next()) |token| : (j += 1) {
                while (i < text.items.len) : (i += 1) {
                    if (i >= token.span.offset) {
                        i += token.span.length;
                        break;
                    }
                    std.debug.print("{c}", .{text.items[i]});
                }
                std.debug.print("\x1b[3{}m", .{j % 6 + 1});
                std.debug.print("{s}", .{token.span.in(text.items)});
                std.debug.print("\x1b[0m", .{});
            }
        }
        std.debug.print("\n", .{});
    }

    var decls = ArrayList(Decl).init(allocator);
    defer decls.deinit();

    var term_store = model.TermStore.init(allocator);
    defer term_store.deinit();

    for (stmt_list.items) |stmt| {
        var parser = try Parser.new(text.items, stmt, allocator);
        defer parser.deinit();
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
