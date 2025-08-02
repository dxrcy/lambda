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

const symbols = @import("symbols.zig");
const LocalStore = symbols.LocalStore;

const debug = @import("debug.zig");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const filepath = "example";
    const text = try utils.readFile(filepath, allocator);
    defer text.deinit();

    var decls = ArrayList(Decl).init(allocator);
    defer decls.deinit();

    var terms = TermStore.init(allocator);
    defer terms.deinit();

    {
        var stmts = Statements.new(text.items);
        while (stmts.next()) |stmt| {
            var parser = Parser.new(text.items, stmt);
            const decl = try parser.tryDeclaration(&terms) orelse {
                continue;
            };
            try decls.append(decl);
        }
    }

    {
        var locals = LocalStore.init(allocator);
        defer locals.deinit();

        for (decls.items) |*decl| {
            std.debug.assert(locals.isEmpty());
            try symbols.patchSymbols(
                decl.term,
                text.items,
                &terms,
                &locals,
                decls.items,
            );
        }
        std.debug.assert(locals.isEmpty());
    }

    debug.printDeclarations(decls.items, &terms, text.items);
}
