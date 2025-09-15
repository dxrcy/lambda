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
const LineReader = @import("input/LineReader.zig");
const output = @import("output.zig");

const TextStore = @import("TextStore.zig");
const SourceSpan = TextStore.SourceSpan;

pub fn main() !u8 {
    // pub fn main() Allocator.Error!void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    output.init();

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

    var text = TextStore.init(allocator);
    defer text.deinit();

    // PERF: Stream file into text storage without intermediate ArrayList
    const file_source = blk: {
        // TODO: Include filepath in report
        var file_text = utils.readFile(filepath, allocator) catch |err| {
            return Reporter.reportFatal(
                "failed to read file",
                "{}",
                .{err},
            );
        };
        defer file_text.deinit(allocator);

        break :blk try text.addFile(filepath, file_text.items);
    };

    const file_text = text.getSourceText(file_source);

    if (!std.unicode.utf8ValidateSlice(file_text)) {
        // To include context filepath
        // TODO: Use `reportFatal`
        // TODO:
        // Reporter.report(
        //     "file contains invalid UTF-8 bytes",
        //     "",
        //     .{},
        //     .{ .file = &context },
        // );
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
        var statements = Statements.new(file_source, &text);
        while (statements.next()) |span| {
            std.debug.print("<{s}>\n", .{span.in(&text)});
            var parser = Parser.new(span, &text);
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
                .inspect => |term| {
                    _ = term;
                    output.print("unimplemented\n", .{});
                },
            }
        }
    }

    debug.printDeclarations(decls.items, &text);

    if (Reporter.checkFatal()) |code|
        return code;

    // Reusable by any operation which patches symbols
    var locals = LocalStore.init(allocator);
    defer locals.deinit();

    symbols.checkDeclarationCollisions(decls.items, &text);
    for (decls.items) |*entry| {
        try symbols.patchSymbols(entry.term, &locals, decls.items, &text);
    }
    for (queries.items) |*query| {
        try symbols.patchSymbols(query.term, &locals, decls.items, &text);
    }

    if (Reporter.checkFatal()) |code|
        return code;

    // debug.printDeclarations(decls.items, &context);
    // debug.printQueries(queries.items, &context);

    // output.print("Results:\n", .{});
    // output.print("\n", .{});
    {
        for (queries.items) |*query| {
            const query_span = query.term.span.?;

            const result = try resolve.resolveTerm(
                query.term,
                decls.items,
                term_allocator.allocator(),
            ) orelse continue;

            output.print("?- ", .{});
            debug.printSpanInline(query_span.in(&text));
            output.print("\n", .{});
            output.print("-> ", .{});
            debug.printTermInline(result, decls.items, &text);
            output.print("\n", .{});
            output.print("\n", .{});
        }
    }

    var repl = try Repl.new(&text);

    while (try repl.readLine()) |line| {
        Reporter.clearCount();

        if (!std.unicode.utf8ValidateSlice(line.in(&text))) {
            // To include context filepath
            // TODO:
            Reporter.report(
                "input contains invalid UTF-8 bytes",
                "",
                .{},
                .{ .stdin = {} },
            );
            continue;
        }

        var parser = Parser.new(line, &text);

        const stmt = try parser.tryStatement(term_allocator.allocator()) orelse {
            continue;
        };
        switch (stmt) {
            .declaration => {
                output.print("unimplemented\n", .{});
            },
            .query => |query| {
                try symbols.patchSymbols(
                    query.term,
                    &locals,
                    decls.items,
                    &text,
                );

                if (Reporter.getCount() > 0) {
                    continue;
                }

                {
                    const result = try resolve.resolveTerm(
                        query.term,
                        decls.items,
                        term_allocator.allocator(),
                    ) orelse continue;

                    output.print("-> ", .{});
                    debug.printTermInline(result, decls.items, &text);
                    output.print("\n", .{});
                    output.print("\n", .{});
                }
            },
            .inspect => |term| {
                try symbols.patchSymbols(term, &locals, decls.items, &text);
                if (Reporter.getCount() > 0) {
                    continue;
                }

                const expanded = resolve.expandGlobalOnce(term, decls.items);

                // Resolve *expanded* term. This is different to queries
                const result = try resolve.resolveTerm(
                    expanded,
                    decls.items,
                    term_allocator.allocator(),
                ) orelse continue;

                output.print("* term....... ", .{});
                debug.printTermInline(term, decls.items, &text);
                output.print("\n", .{});

                output.print("* expanded... ", .{});
                debug.printTermInline(expanded, decls.items, &text);
                output.print("\n", .{});

                output.print("* resolved... ", .{});
                debug.printTermInline(result, decls.items, &text);
                output.print("\n", .{});
                output.print("\n", .{});
            },
        }
    }

    output.print("end.\n", .{});
    return 0;
}

const Repl = struct {
    const Self = @This();

    const ReadError = LineReader.ReadError || Allocator.Error;

    // TODO: Properly support reading from non-terminal stdin

    reader: LineReader,
    // `LineReader` has a const reference to text store, but this is only used
    // for reading. Best to keep the text store mutation within this container,
    // at least in terminal mode, since input isn't streamed.
    text: *TextStore,

    pub fn new(text: *TextStore) LineReader.NewError!Self {
        return Self{
            .reader = try LineReader.new(text),
            .text = text,
        };
    }

    /// Returns `null` iff **EOF**.
    pub fn readLine(self: *Self) ReadError!?SourceSpan {
        while (true) {
            if (!try self.reader.readLine()) {
                return null;
            }
            if (self.reader.getLine().len > 0) {
                break;
            }
        }

        const line = try self.text.appendInput(self.reader.getLine());
        self.reader.appendHistory(line);
        return line;
    }
};
