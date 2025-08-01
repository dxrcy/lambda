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

    for (stmt_list.items) |stmt| {
        var parser = try Parser.new(text.items, stmt, allocator);
        defer parser.deinit();

        const name = try parser.expectIdentOrEol() orelse continue;
        std.debug.print("\nname: {s}\n", .{name.in(text.items)});

        try parser.expectEquals();

        var term_list = ArrayList(Term).init(allocator);
        defer term_list.deinit();

        const term_index = try parser.expectTerm(&term_list, true);
        if (term_index != model.NO_TERM_INDEX) {
            const term = &term_list.items[term_index];
            term.debug(term_list.items, text.items);
        }

        // for (term_list.items) |item| {
        //     std.debug.print("[ {s} ]\n", .{item.getSpan().in(text.items)});
        // }
    }
}
