const std = @import("std");
const fs = std.fs;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const TextStore = @import("text/TextStore.zig");
const SourceSpan = TextStore.SourceSpan;

const reduction = @import("reduction.zig");
const debug = @import("debug.zig");
const output = @import("output.zig");
const Reporter = @import("Reporter.zig");
const utils = @import("utils.zig");
const encode = @import("encode.zig");

const Parser = @import("parse/Parser.zig");
const Statements = @import("parse/Statements.zig");
const Tokenizer = @import("parse/Tokenizer.zig");

const LineReader = @import("input/LineReader.zig");

const model = @import("model.zig");
const Decl = model.Decl;
const Query = model.Query;

const resolution = @import("resolution.zig");
const LocalStore = resolution.LocalStore;

pub fn main() !u8 {
    // pub fn main() Allocator.Error!void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    output.init();

    var args = std.process.args();
    _ = args.next();

    var reporter = Reporter.new();
    defer Reporter.Output.flush();

    const filepath = args.next() orelse {
        return reporter.reportFatal(
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
            return reporter.reportFatal(
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
        reporter.report(
            "file contains invalid UTF-8 bytes",
            "",
            .{},
            .{ .source = file_source },
            &text,
        );
        if (reporter.checkFatal()) |code|
            return code;
    }

    var decls = ArrayList(Decl).empty;
    // `fingerprint`s deinitialized later, in case we exit before they are initialized
    defer decls.deinit(allocator);

    var queries = ArrayList(Query).empty;
    defer queries.deinit(allocator);

    var term_allocator = std.heap.ArenaAllocator.init(gpa.allocator());
    defer term_allocator.deinit();

    // TODO: Separate term storage into
    // - terms in declarations
    // - temporary terms (file queries, repl queries)
    // And destroy temporaries after their use

    // TODO: Two passes per file, one to declare global bindings, one to run queries
    // This requires modifying the parse call, to avoid double allocations
    // We could even catch malformed queries while parsing declarations, by
    // dry-running query parse (if is query) when parsing decls: no allocations
    // will be made (pass in a dummy allocator and return nullptr).

    {
        var statements = Statements.new(file_source, &text);
        while (statements.next()) |span| {
            var parser = Parser.new(span, &text, &reporter);
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

    if (reporter.checkFatal()) |code|
        return code;

    // Reusable by any operation which patches symbols
    var locals = LocalStore.init(allocator);
    defer locals.deinit();

    resolution.checkDeclarationCollisions(decls.items, &text, &reporter);
    for (decls.items) |*entry| {
        try resolution.resolveAllSymbols(
            entry.term,
            &locals,
            decls.items,
            &text,
            &reporter,
        );
    }
    for (queries.items) |*query| {
        try resolution.resolveAllSymbols(
            query.term,
            &locals,
            decls.items,
            &text,
            &reporter,
        );
    }

    if (reporter.checkFatal()) |code|
        return code;

    // Reduce *all nested* globals (eg. `1 := S 0` is applied)
    // So reduced queries can match decl fingerprint
    for (decls.items) |*decl| {
        // TODO: Use temporary allocator for this, since terms are only used
        // within the current iteration; fingerprint does not refer to terms
        const reduced = try reduction.reduceTerm(
            decl.term,
            decls.items,
            term_allocator.allocator(),
            &text,
            &reporter,
        ) orelse decl.term;

        decl.fingerprint = try encode.TermTree.encodeTerm(
            reduced,
            allocator,
            decls.items,
        );
    }
    defer for (decls.items) |*decl| {
        decl.fingerprint.deinit();
    };

    debug.printDeclarations(decls.items, &text);

    {
        for (queries.items) |*query| {
            const query_span = query.term.span.?;

            const result = try reduction.reduceTerm(
                query.term,
                decls.items,
                term_allocator.allocator(),
                &text,
                &reporter,
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
        reporter.clear();

        if (!std.unicode.utf8ValidateSlice(line.in(&text))) {
            // To include context filepath
            reporter.report(
                "input contains invalid UTF-8 bytes",
                "",
                .{},
                .{ .source = .{ .input = {} } },
                &text,
            );
            continue;
        }

        var parser = Parser.new(line, &text, &reporter);

        const stmt = try parser.tryStatement(term_allocator.allocator()) orelse {
            continue;
        };
        switch (stmt) {
            .declaration => {
                output.print("unimplemented\n", .{});
            },
            .query => |query| {
                try resolution.resolveAllSymbols(
                    query.term,
                    &locals,
                    decls.items,
                    &text,
                    &reporter,
                );

                if (reporter.count > 0) {
                    continue;
                }

                {
                    const result = try reduction.reduceTerm(
                        query.term,
                        decls.items,
                        term_allocator.allocator(),
                        &text,
                        &reporter,
                    ) orelse continue;

                    output.print("-> ", .{});
                    debug.printTermInline(result, decls.items, &text);
                    output.print("\n", .{});

                    var tree = try encode.TermTree.encodeTerm(
                        result,
                        allocator,
                        decls.items,
                    );
                    defer tree.deinit();

                    // debug.printFingerprint(&decls.items[8].fingerprint);
                    // debug.printFingerprint(&tree);

                    // output.print("\n", .{});
                    // output.print("-> ", .{});
                    // debug.printTermInline(result, decls.items, &text);
                    // output.print("\n", .{});
                    // output.print("-- ", .{});
                    // debug.printTermInline(decls.items[8].term, decls.items, &text);
                    // output.print("\n", .{});

                    // TODO: If query is a a single global, don't repeat it here
                    for (decls.items) |decl| {
                        if (tree.equals(&decl.fingerprint)) {
                            output.print("~> {s}\n", .{decl.name.in(&text)});
                        }
                    }

                    output.print("\n", .{});
                }
            },
            .inspect => |term| {
                try resolution.resolveAllSymbols(
                    term,
                    &locals,
                    decls.items,
                    &text,
                    &reporter,
                );
                if (reporter.count > 0) {
                    continue;
                }

                const expanded = reduction.expandGlobalOnce(term, decls.items);

                // Reduce *expanded* term. This is different to queries
                const result = try reduction.reduceTerm(
                    expanded,
                    decls.items,
                    term_allocator.allocator(),
                    &text,
                    &reporter,
                ) orelse continue;

                output.print("* term....... ", .{});
                debug.printTermInline(term, decls.items, &text);
                output.print("\n", .{});

                output.print("* expanded... ", .{});
                debug.printTermInline(expanded, decls.items, &text);
                output.print("\n", .{});

                output.print("* reduced.... ", .{});
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
