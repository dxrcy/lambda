const std = @import("std");
const fs = std.fs;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const Context = @import("Context.zig");
const Reporter = @import("Reporter.zig");
const Span = @import("Span.zig");
const utils = @import("utils.zig");

const Parser = @import("parse/Parser.zig");
const Statements = @import("parse/Statements.zig");
const Tokenizer = @import("parse/Tokenizer.zig");

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

    const context = Context{
        .filepath = filepath,
        .text = text.items,
    };

    checkUtf8(&context);
    if (!Reporter.isEmpty()) return;

    var decls = ArrayList(Decl).init(allocator);
    defer decls.deinit();

    var terms = TermStore.init(allocator);
    defer terms.deinit();

    {
        var stmts = Statements.new(&context);
        while (stmts.next()) |stmt| {
            var parser = Parser.new(stmt, &context);
            if (try parser.tryDeclaration(&terms)) |decl| {
                try decls.append(decl);
            }
        }
    }
    // if (!Reporter.isEmpty()) return;

    // std.debug.print("Done\n", .{});
    // debug.printDeclarations(decls.items, &terms, &context);

    {
        symbols.checkDeclarationCollisions(
            decls.items,
            &context,
        );

        var locals = LocalStore.init(allocator);
        defer locals.deinit();

        for (decls.items) |*decl| {
            std.debug.assert(locals.isEmpty());
            try symbols.patchSymbols(
                decl.term,
                &context,
                &terms,
                &locals,
                decls.items,
            );
        }
        std.debug.assert(locals.isEmpty());
    }
    if (!Reporter.isEmpty()) return;

    debug.printDeclarations(decls.items, &terms, &context);
}

fn checkUtf8(context: *const Context) void {
    if (!std.unicode.utf8ValidateSlice(context.text)) {
        Reporter.report(
            "file contains invalid UTF-8 bytes",
            "",
            .{},
            .{ .file = {} },
            context,
        );
    }
}
