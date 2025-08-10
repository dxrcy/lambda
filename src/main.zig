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
const Query = model.Query;
const TermStore = model.TermStore;

const symbols = @import("symbols.zig");
const LocalStore = symbols.LocalStore;

const debug = @import("debug.zig");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = std.process.args();
    _ = args.next();

    const filepath = args.next() orelse {
        std.debug.print("Please provide a file path.\n", .{});
        return;
    };

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

    var queries = ArrayList(Query).init(allocator);
    defer queries.deinit();

    var terms = TermStore.init(allocator);
    defer terms.deinit();

    {
        var stmts = Statements.new(&context);
        while (stmts.next()) |stmt| {
            var parser = Parser.new(stmt, &context);
            if (try parser.tryQuery(&terms)) |query| {
                try queries.append(query);
            } else if (try parser.tryDeclaration(&terms)) |decl| {
                try decls.append(decl);
            }
        }
    }
    if (!Reporter.isEmpty()) return;

    {
        var locals = LocalStore.init(allocator);
        defer locals.deinit();

        symbols.checkDeclarationCollisions(
            decls.items,
            &context,
        );

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

        for (queries.items) |*query| {
            std.debug.assert(locals.isEmpty());
            try symbols.patchSymbols(
                query.term,
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
    debug.printQueries(queries.items, &terms, &context);

    // TODO(feat): Check for recursive abstractions, in resolution step

    std.debug.print("Results:\n", .{});
    {
        for (queries.items) |*query| {
            const result = evaluateTerm(query.term, &terms, decls.items);
            debug.printResult(&result, &terms, &context);
        }
    }
}

fn evaluateTerm(index: model.TermIndex, terms: *const TermStore, decls: []const Decl) model.Result {
    const term = terms.get(index);
    return switch (term.value) {
        .unresolved => unreachable,
        .local => |local| .{ .local = local },
        .global => |global| {
            const decl = decls[global];
            return evaluateTerm(decl.term, terms, decls);
        },
        .group => |inner| evaluateTerm(inner, terms, decls),
        .abstraction => |abstr| .{
            .abstraction = abstr,
        },
        .application => |appl| {
            const argument = evaluateTerm(appl.argument, terms, decls);
            const function = evaluateTerm(appl.function, terms, decls);
            _ = argument;
            _ = function;
            // TODO
            unreachable;
        },
    };
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
