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
                .inspect => |term| {
                    _ = term;
                    std.debug.print("unimplemented\n", .{});
                },
            }
        }
    }

    if (Reporter.checkFatal()) |code|
        return code;

    // Reusable by any operation which patches symbols
    var locals = LocalStore.init(allocator);
    defer locals.deinit();

    symbols.checkDeclarationCollisions(decls.items);
    for (decls.items) |*entry| {
        try symbols.patchSymbols(entry.term, &locals, decls.items);
    }
    for (queries.items) |*query| {
        try symbols.patchSymbols(query.term, &locals, decls.items);
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

            const result = try resolve.resolveTerm(
                query.term,
                decls.items,
                term_allocator.allocator(),
            ) orelse continue;

            std.debug.print("?- ", .{});
            debug.printSpanInline(query_span.string());
            std.debug.print("\n", .{});
            std.debug.print("-> ", .{});
            debug.printTermExpr(result, decls.items);
            std.debug.print("\n", .{});
            std.debug.print("\n", .{});
        }
    }

    var repl = try Repl.init(allocator);

    while (try repl.readLine()) |line| {
        Reporter.clearCount();

        if (!std.unicode.utf8ValidateSlice(line.string())) {
            // To include context filepath
            Reporter.report(
                "input contains invalid UTF-8 bytes",
                "",
                .{},
                .{ .stdin = {} },
            );
            continue;
        }

        var parser = Parser.new(line);

        const stmt = try parser.tryStatement(term_allocator.allocator()) orelse {
            continue;
        };
        switch (stmt) {
            .declaration => {
                std.debug.print("unimplemented\n", .{});
            },
            .query => |query| {
                try symbols.patchSymbols(query.term, &locals, decls.items);

                if (Reporter.getCount() > 0) {
                    continue;
                }

                // debug.printTermAll("Query", query.term, decls.items);

                {
                    const result = try resolve.resolveTerm(
                        query.term,
                        decls.items,
                        term_allocator.allocator(),
                    ) orelse continue;

                    std.debug.print("-> ", .{});
                    debug.printTermExpr(result, decls.items);
                    std.debug.print("\n", .{});
                    std.debug.print("\n", .{});
                    // debug.printTermAll("Result", result, decls.items);
                }
            },
            .inspect => |term| {
                try symbols.patchSymbols(term, &locals, decls.items);
                const expanded = resolve.expandGlobalOnce(term, decls.items);

                // Resolve *expanded* term. This is different to queries
                const result = try resolve.resolveTerm(
                    expanded,
                    decls.items,
                    term_allocator.allocator(),
                ) orelse continue;

                std.debug.print("* term....... ", .{});
                debug.printTermExpr(term, decls.items);
                std.debug.print("\n", .{});

                std.debug.print("* expanded... ", .{});
                debug.printTermExpr(expanded, decls.items);
                std.debug.print("\n", .{});

                std.debug.print("* resolved... ", .{});
                debug.printTermExpr(result, decls.items);
                std.debug.print("\n", .{});
                std.debug.print("\n", .{});
            },
        }
    }

    std.debug.print("end.\n", .{});
    return 0;
}

const Repl = struct {
    const Self = @This();

    /// Collects all input lines (including temporaries).
    /// `reader.history` references slices of this text via `context`.
    text: ArrayList(u8),
    allocator: Allocator,
    context: Context,
    reader: LineReader,

    pub fn init(allocator: Allocator) !Self {
        const self = Self{
            .text = ArrayList(u8).empty,
            .allocator = allocator,
            .context = Context{
                .filepath = null,
                .text = undefined,
            },
            .reader = try LineReader.new(),
        };
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.text.deinit(self.allocator);
    }

    /// Returns `null` iff **EOF**.
    // TODO: Add explicit error kinds
    pub fn readLine(self: *Self) !?Span {
        while (true) {
            if (!try self.reader.readLine()) {
                return null;
            }
            if (self.reader.getLine().len > 0) {
                break;
            }
        }

        const text_line_start = self.text.items.len;
        try self.text.appendSlice(self.allocator, self.reader.getLine());

        const text_line = self.text.items[text_line_start..self.text.items.len];
        try self.text.append(self.allocator, '\n');

        // Reassign pointer and length in case of resize or relocation
        self.context.text = self.text.items;

        const line_span = Span.new(text_line_start, text_line.len, &self.context);

        self.reader.appendHistory(line_span);

        return line_span;
    }
};
