const std = @import("std");
const fs = std.fs;
const Allocator = std.mem.Allocator;
const ArrayList = std.array_list.Managed;

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
            .{ .file = &context },
        );
        Reporter.checkFatal();
    }

    var decls = ArrayList(Decl).init(allocator);
    defer decls.deinit();

    var queries = ArrayList(Query).init(allocator);
    defer queries.deinit();

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
                    try decls.append(decl);
                },
                .query => |query| {
                    try queries.append(query);
                },
            }
        }
    }

    Reporter.checkFatal();

    {
        symbols.checkDeclarationCollisions(decls.items);

        // TODO(opt): Reuse all instances of local store in this function
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

    Reporter.checkFatal();

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

    // TODO(opt): Don't append temporary query lines
    // Use a separate temporary string
    // This is not important at this stage

    // Storage for all stdin text (including non-persistant statements)
    var stdin_text = ArrayList(u8).init(allocator);
    defer stdin_text.deinit();

    const BUFFER_SIZE = 4;

    const stdin = std.fs.File.stdin();

    var buffer: [BUFFER_SIZE]u8 = undefined;
    var reader = stdin.reader(&buffer);

    // TODO: Add stdin case to `Context`, don't use filepath
    var stdin_context = Context{
        .filepath = null,
        .text = stdin_text.items,
    };

    while (true) {
        Reporter.clearCount();

        std.debug.print("?- ", .{});

        const text_line_start = stdin_text.items.len;
        const text_line = try readLineAndAppend(&reader, &stdin_text) orelse {
            break;
        };

        // Reassign pointer and length in case of resize or relocation
        stdin_context.text = stdin_text.items;

        const line_span = Span.new(text_line_start, text_line.len, &stdin_context);

        // TODO: Validate encoding

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
}

fn readLineAndAppend(
    reader: *fs.File.Reader,
    text: *ArrayList(u8),
) !?[]const u8 {
    const start = text.items.len;

    // TODO: Why is there an initial zero-byte read ? Remove if possible
    while (true) {
        const byte = try readSingleByte(reader) orelse
            return null;
        if (byte == '\n') {
            break;
        }
        try text.append(byte);
    }

    if (start != text.items.len) {
        try text.append('\n');
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
