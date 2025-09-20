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
const Signer = @import("signature.zig").Signer;

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
    defer decls.deinit(allocator);

    var queries = ArrayList(Query).empty;
    defer queries.deinit(allocator);

    var terms_persistent = model.TermStore.init(gpa.allocator());
    defer terms_persistent.deinit();

    // TODO: Separate term storage into
    // - terms in declarations
    // - temporary terms (file queries, repl queries)
    // And destroy temporaries after their use

    // TODO: Create DeclStore to handle inner allocations

    // TODO: Two passes per file, one to declare global bindings, one to run queries
    // This requires modifying the parse call, to avoid double allocations
    // We could even catch malformed queries while parsing declarations, by
    // dry-running query parse (if is query) when parsing decls: no allocations
    // will be made (pass in a dummy allocator and return nullptr).

    {
        var statements = Statements.new(file_source, &text);
        while (statements.next()) |span| {
            var parser = Parser.new(span, &text, &reporter);
            const stmt = try parser.tryStatement(&terms_persistent) orelse {
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
            entry.term.unwrapOwned(),
            &locals,
            decls.items,
            &text,
            &reporter,
        );
    }
    for (queries.items) |*query| {
        try resolution.resolveAllSymbols(
            query.term.unwrapOwned(),
            &locals,
            decls.items,
            &text,
            &reporter,
        );
    }

    if (reporter.checkFatal()) |code|
        return code;

    debug.printDeclarations(decls.items, &text);

    return 0;
}

fn dead() !void {
    const decls = undefined;
    const term_allocator = undefined;
    const reporter = undefined;
    const text = undefined;
    const allocator = undefined;
    const queries = undefined;
    const terms_persistent = undefined;
    const locals = undefined;

    var signer = Signer.init(allocator);
    defer signer.deinit();

    // Reduce *all nested* globals (eg. `1 := S 0` is applied)
    // So reduced queries can match decl signature
    for (decls.items) |*decl| {
        // Don't report recursion cutoff
        const reduced = try reduction.reduceTerm(
            decl.term,
            .greedy,
            decls.items,
            // TODO: Use termporary allocator
            &terms_persistent,
        ) orelse decl.term;

        // Sets to `null` on fail (iteration limit)
        decl.signature = try signer.sign(reduced, decls.items);
    }

    {
        for (queries.items) |*query| {
            const term_span = query.term.span.?;

            const reduced = try reduction.reduceTerm(
                query.term,
                .lazy,
                decls.items,
                &terms_persistent,
            ) orelse {
                reporter.report(
                    "recursion limit reached when reducing query",
                    "check for any reference cycles in declarations",
                    .{},
                    .{ .query = term_span },
                    &text,
                );
                continue;
            };

            output.print("?- ", .{});
            debug.printSpanInline(term_span.in(&text));
            output.print("\n", .{});
            output.print("-> ", .{});
            debug.printTermInline(reduced, decls.items, &text);
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
                const term_span = query.term.span.?;

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
                    const reduced_lazy = try reduction.reduceTerm(
                        query.term,
                        .lazy,
                        decls.items,
                        term_allocator.allocator(),
                    ) orelse {
                        reporter.report(
                            "recursion limit reached when reducing query",
                            "check for any reference cycles in declarations",
                            .{},
                            .{ .query = term_span },
                            &text,
                        );
                        continue;
                    };

                    output.print("-> ", .{});
                    debug.printTermInline(reduced_lazy, decls.items, &text);
                    output.print("\n", .{});

                    // Don't report recursion cutoff
                    const reduced_greedy = try reduction.reduceTerm(
                        query.term,
                        .greedy,
                        decls.items,
                        term_allocator.allocator(),
                    ) orelse continue;

                    if (try signer.sign(reduced_greedy, decls.items)) |signature| {
                        for (decls.items, 0..) |decl, i| {
                            const decl_signature = decl.signature orelse
                                continue;

                            if (signature == decl_signature and
                                !isDeclIndex(i, query.term) and
                                !isDeclIndex(i, reduced_lazy))
                            {
                                output.print("-> {s}\n", .{decl.name.in(&text)});
                            }
                        }
                    }

                    output.print("\n", .{});
                }
            },
            .inspect => |term| {
                const term_span = term.span.?;

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

                const reduced_lazy = try reduction.reduceTerm(
                    expanded,
                    .lazy,
                    decls.items,
                    term_allocator.allocator(),
                ) orelse {
                    reporter.report(
                        "recursion limit reached when reducing query",
                        "check for any reference cycles in declarations",
                        .{},
                        .{ .query = term_span },
                        &text,
                    );
                    continue;
                };

                // Don't report recursion cutoff
                const reduced_greedy = try reduction.reduceTerm(
                    expanded,
                    .greedy,
                    decls.items,
                    term_allocator.allocator(),
                ) orelse continue;

                const signature = try signer.sign(reduced_greedy, decls.items);

                output.print("* term.............. ", .{});
                debug.printTermInline(term, decls.items, &text);
                output.print("\n", .{});

                output.print("* expanded.......... ", .{});
                debug.printTermInline(expanded, decls.items, &text);
                output.print("\n", .{});

                output.print("* reduced lazy...... ", .{});
                debug.printTermInline(reduced_lazy, decls.items, &text);
                output.print("\n", .{});

                output.print("* reduced greedy.... ", .{});
                debug.printTermInline(reduced_greedy, decls.items, &text);
                output.print("\n", .{});

                output.print("* signature......... ", .{});
                debug.printSignature(signature);
                output.print("\n", .{});

                output.print("\n", .{});
            },
        }
    }

    output.print("end.\n", .{});
    return 0;
}

fn isDeclIndex(index: usize, term: *const model.Term) bool {
    switch (term.value) {
        .global => |global| return index == global,
        else => return false,
    }
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
