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
const DeclEntry = model.DeclEntry;
const Query = model.Query;

const symbols = @import("symbols.zig");
const LocalStore = symbols.LocalStore;

const resolve = @import("resolve.zig");
const debug = @import("debug.zig");

pub fn main() !void {
    // pub fn main() Allocator.Error!void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = std.process.args();
    _ = args.next();

    defer Reporter.Output.flush();

    const filepath = args.next() orelse {
        Reporter.reportFatal("no filepath argument was provided", "", .{});
    };

    // TODO(feat): Include filepath in report
    const text = utils.readFile(filepath, allocator) catch |err| {
        Reporter.reportFatal("failed to read file", "{}", .{err});
    };
    defer text.deinit();

    const context = Context{
        .filepath = filepath,
        .text = text.items,
    };

    if (!std.unicode.utf8ValidateSlice(context.text)) {
        // To include context filepath
        Reporter.report(
            "file contains invalid UTF-8 bytes",
            "",
            .{},
            .{ .file = {} },
            &context,
        );
        Reporter.checkFatal();
    }

    var decls = ArrayList(DeclEntry).init(allocator);
    defer decls.deinit();

    var queries = ArrayList(Query).init(allocator);
    defer queries.deinit();

    var term_allocator = std.heap.ArenaAllocator.init(gpa.allocator());
    defer term_allocator.deinit();

    {
        var stmts = Statements.new(&context);
        while (stmts.next()) |stmt| {
            var parser = Parser.new(stmt, &context);
            if (try parser.tryQuery(term_allocator.allocator())) |query| {
                try queries.append(query);
            } else if (try parser.tryDeclaration(term_allocator.allocator())) |decl| {
                try decls.append(DeclEntry{
                    .decl = decl,
                    .context = &context,
                });
            }
        }
    }

    Reporter.checkFatal();

    {
        symbols.checkDeclarationCollisions(
            decls.items,
            &context,
        );

        // TODO(opt): Reuse all instances of local store in this function
        var locals = LocalStore.init(allocator);
        defer locals.deinit();

        for (decls.items) |*entry| {
            std.debug.assert(locals.isEmpty());
            try symbols.patchSymbols(
                entry.decl.term,
                &context,
                &locals,
                decls.items,
            );
        }
        std.debug.assert(locals.isEmpty());
    }

    {
        var locals = LocalStore.init(allocator);
        defer locals.deinit();

        for (queries.items) |*query| {
            std.debug.assert(locals.isEmpty());
            try symbols.patchSymbols(
                query.term,
                &context,
                &locals,
                decls.items,
            );
        }
        std.debug.assert(locals.isEmpty());
    }

    Reporter.checkFatal();

    // debug.printDeclarations(decls.items, &context);
    // debug.printQueries(queries.items, &context);

    // std.debug.print("Results:\n", .{});
    // std.debug.print("\n", .{});
    {
        for (queries.items) |*query| {
            const result = resolve.resolveTerm(
                query.term,
                0,
                decls.items,
                term_allocator.allocator(),
            ) catch |err| switch (err) {
                error.MaxRecursion => {
                    Reporter.report(
                        "recursion limit reached when expanding query",
                        "check for any reference cycles in declarations",
                        .{},
                        .{ .query = query.term.span },
                        &context,
                    );
                    continue;
                },
                else => |other_err| return other_err,
            };

            std.debug.print(" ? ", .{});
            debug.printSpanInline(query.term.span.in(&context));
            std.debug.print("\n", .{});
            std.debug.print("-> ", .{});
            debug.printTermExpr(result, decls.items, &context);
            std.debug.print("\n", .{});
        }
    }

    // Continue even if queries reported errors
    Reporter.clearCount();

    const BUFFER_SIZE = 1024;

    var stdin_text = ArrayList(u8).init(allocator);
    defer stdin_text.deinit();

    const stdin = std.io.getStdIn();

    const reader = stdin.reader();
    var buf: [BUFFER_SIZE]u8 = undefined;

    // TODO: Remove `?`. If statement isnt a decl, its a query

    while (true) {
        std.debug.print("-- ", .{});
        const line = reader.readUntilDelimiter(&buf, '\n') catch |err| switch (err) {
            error.StreamTooLong => {
                unreachable;
            },
            error.EndOfStream => {
                break;
            },
            else => |other_err| return other_err,
        };

        const text_line_start = stdin_text.items.len;

        try stdin_text.appendSlice(line);
        try stdin_text.append('\n');

        // Include '\n'
        const text_line = stdin_text.items[text_line_start..stdin_text.items.len];

        std.debug.print("<{s}>\n", .{stdin_text.items});

        // TODO: Use single context for all stdin
        const line_context = Context{
            .filepath = "",
            .text = text_line,
        };

        const line_span = Span.new(0, line.len);

        // TODO: Validate encoding

        std.debug.print("{s}\n", .{line_span.in(&line_context)});

        var parser = Parser.new(line_span, &line_context);

        if (try parser.tryQuery(term_allocator.allocator())) |query| {
            try queries.append(query);

            var locals = LocalStore.init(allocator);
            defer locals.deinit();

            std.debug.assert(locals.isEmpty());
            try symbols.patchSymbols(
                query.term,
                &line_context,
                &locals,
                decls.items,
            );

            std.debug.assert(locals.isEmpty());

            debug.printTermAll("Query", query.term, decls.items, &line_context);

            const result = resolve.resolveTerm(
                query.term,
                0,
                decls.items,
                term_allocator.allocator(),
            ) catch |err| switch (err) {
                error.MaxRecursion => {
                    Reporter.report(
                        "recursion limit reached when expanding query",
                        "check for any reference cycles in declarations",
                        .{},
                        .{ .query = query.term.span },
                        &context,
                    );
                    continue;
                },
                else => |other_err| return other_err,
            };

            debug.printTermAll("Result", result, decls.items, &line_context);
        } else if (try parser.tryDeclaration(term_allocator.allocator())) |_| {
            @panic("unimplemented");
        }

        Reporter.clearCount();
    }

    std.debug.print("end.\n", .{});
}
