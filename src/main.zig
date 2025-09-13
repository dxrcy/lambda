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

const symbols = @import("symbols.zig");
const LocalStore = symbols.LocalStore;

const resolve = @import("resolve.zig");
const debug = @import("debug.zig");

pub fn main() !u8 {
    // pub fn main() Allocator.Error!void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = std.process.args();
    _ = args.next();

    defer Reporter.Output.flush();

    const filepath = args.next() orelse {
        return Reporter.reportFatal(
            "no filepath argument was provided",
            "",
            .{},
        );
    };

    // TODO: Include filepath in report
    var text = utils.readFile(filepath, allocator) catch |err| {
        return Reporter.reportFatal(
            "failed to read file",
            "{}",
            .{err},
        );
    };
    defer text.deinit(allocator);

    const context = Context{
        .filepath = filepath,
        .text = text.items,
    };

    if (!std.unicode.utf8ValidateSlice(context.text)) {
        // To include context filepath
        // TODO: Use `reportFatal`
        Reporter.report(
            "file contains invalid UTF-8 bytes",
            "",
            .{},
            .{ .file = &context },
        );
        if (Reporter.checkFatal()) |code|
            return code;
    }

    var decls = ArrayList(Decl).empty;
    defer decls.deinit(allocator);

    var queries = ArrayList(Query).empty;
    defer queries.deinit(allocator);

    // TODO: Separate term storage into
    // - terms in declarations
    // - temporary terms (file queries, repl queries)
    // And destroy temporaries after their use

    var term_allocator = std.heap.ArenaAllocator.init(gpa.allocator());
    defer term_allocator.deinit();

    {
        var statements = Statements.new(&context);
        while (statements.next()) |span| {
            var parser = Parser.new(span);
            const stmt = try parser.tryStatement(term_allocator.allocator()) orelse {
                continue;
            };
            switch (stmt) {
                .declaration => |decl| {
                    try decls.append(allocator, decl);
                },
                .query => |query| {
                    try queries.append(allocator, query);
                },
            }
        }
    }

    if (Reporter.checkFatal()) |code|
        return code;

    {
        symbols.checkDeclarationCollisions(decls.items);

        // PERF: Reuse all instances of local store in this function
        var locals = LocalStore.init(allocator);
        defer locals.deinit();

        for (decls.items) |*entry| {
            std.debug.assert(locals.isEmpty());
            try symbols.patchSymbols(entry.term, &locals, decls.items);
        }
        std.debug.assert(locals.isEmpty());
    }

    {
        var locals = LocalStore.init(allocator);
        defer locals.deinit();

        for (queries.items) |*query| {
            std.debug.assert(locals.isEmpty());
            try symbols.patchSymbols(query.term, &locals, decls.items);
        }
        std.debug.assert(locals.isEmpty());
    }

    if (Reporter.checkFatal()) |code|
        return code;

    // debug.printDeclarations(decls.items, &context);
    // debug.printQueries(queries.items, &context);

    // std.debug.print("Results:\n", .{});
    // std.debug.print("\n", .{});
    {
        for (queries.items) |*query| {
            const query_span = query.term.span.?;

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
                        .{ .query = query_span },
                    );
                    continue;
                },
                else => |other_err| return other_err,
            };

            std.debug.print("?- ", .{});
            debug.printSpanInline(query_span.string());
            std.debug.print("\n", .{});
            std.debug.print("-> ", .{});
            debug.printTermExpr(result, decls.items);
            std.debug.print("\n", .{});
            std.debug.print("\n", .{});
        }
    }

    // PERF: Don't append temporary query lines
    // Use a separate temporary string
    // This is not important at this stage

    // Storage for all stdin text (including non-persistant statements)
    var stdin_text = ArrayList(u8).empty;
    defer stdin_text.deinit(allocator);

    const BUFFER_SIZE = 4;

    const stdin = std.fs.File.stdin();

    var buffer: [BUFFER_SIZE]u8 = undefined;
    var reader = stdin.reader(&buffer);

    var stdin_context = Context{
        .filepath = null,
        .text = stdin_text.items,
    };

    while (true) {
        Reporter.clearCount();

        std.debug.print("?- ", .{});

        const text_line_start = stdin_text.items.len;
        const text_line = try readLineAndAppend(&reader, &stdin_text, allocator) orelse {
            break;
        };

        // Reassign pointer and length in case of resize or relocation
        stdin_context.text = stdin_text.items;

        const line_span = Span.new(text_line_start, text_line.len, &stdin_context);

        if (!std.unicode.utf8ValidateSlice(text_line)) {
            // To include context filepath
            Reporter.report(
                "input contains invalid UTF-8 bytes",
                "",
                .{},
                .{ .stdin = {} },
            );
            continue;
        }

        var parser = Parser.new(line_span);

        const stmt = try parser.tryStatement(term_allocator.allocator()) orelse {
            continue;
        };
        switch (stmt) {
            .declaration => {
                std.debug.print("unimplemented\n", .{});
            },
            .query => |query| {
                {
                    var locals = LocalStore.init(allocator);
                    defer locals.deinit();

                    std.debug.assert(locals.isEmpty());
                    try symbols.patchSymbols(query.term, &locals, decls.items);

                    std.debug.assert(locals.isEmpty());
                }

                if (Reporter.getCount() > 0) {
                    continue;
                }

                // debug.printTermAll("Query", query.term, decls.items);

                {
                    const query_span = query.term.span.?;

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
                                .{ .query = query_span },
                            );
                            continue;
                        },
                        else => |other_err| return other_err,
                    };

                    std.debug.print("-> ", .{});
                    debug.printTermExpr(result, decls.items);
                    std.debug.print("\n", .{});
                    std.debug.print("\n", .{});
                    // debug.printTermAll("Result", result, decls.items);
                }
            },
        }
    }

    std.debug.print("end.\n", .{});
    return 0;
}

fn readLineAndAppend(
    reader: *fs.File.Reader,
    text: *ArrayList(u8),
    allocator: Allocator,
) !?[]const u8 {
    const start = text.items.len;

    // TODO: Why is there an initial zero-byte read ? Remove if possible.
    // Not breaking anything though...

    while (true) {
        const byte = try readSingleByte(reader) orelse
            return null;
        if (byte == '\n') {
            break;
        }
        try text.append(allocator, byte);
    }

    if (start != text.items.len) {
        try text.append(allocator, '\n');
    }
    return text.items[start..text.items.len];
}

fn readSingleByte(reader: *fs.File.Reader) !?u8 {
    var bytes: [1]u8 = undefined;

    while (true) {
        const bytes_read = reader.read(&bytes) catch |err| switch (err) {
            error.EndOfStream => {
                return null;
            },
            else => |other_err| {
                return other_err;
            },
        };

        if (bytes_read > 0) {
            return bytes[0];
        }
    }
}
