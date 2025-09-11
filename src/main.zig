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

const debug = @import("debug.zig");

pub fn main() Allocator.Error!void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = std.process.args();
    _ = args.next();

    errdefer Reporter.Output.flush();

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

    var decls = ArrayList(Decl).init(allocator);
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
                try decls.append(decl);
            }
        }
    }

    Reporter.checkFatal();

    {
        symbols.checkDeclarationCollisions(
            decls.items,
            &context,
        );

        // TODO(opt): Reuse local store
        var locals = LocalStore.init(allocator);
        defer locals.deinit();

        for (decls.items) |*decl| {
            std.debug.assert(locals.isEmpty());
            try symbols.patchSymbols(
                decl.term,
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

    debug.printDeclarations(decls.items, &context);
    debug.printQueries(queries.items, &context);

    std.debug.print("Results:\n", .{});
    {
        for (queries.items) |*query| {
            const result = resolve(query.term, 0, &terms, decls.items);
            debug.printResult(&result, &terms, &context);
        }
    }
}

fn resolve(index: TermIndex, depth: usize, terms: *const TermStore, decls: []const Decl) !TermIndex {
    const MAX_RESOLVE_RECURSION = 100;

    if (depth >= MAX_RESOLVE_RECURSION) {
        return error.MaxRecursion;
    }

    const term = terms.get(index);

    const appl = switch (term.value) {
        .unresolved, .local => unreachable,
        .group => |inner| return resolve(inner, depth + 1, terms, decls),
        .global, .abstraction => return term,
        .application => |appl| appl,
    };

    const function = terms.get(appl.function).value;

    const function_free = switch (function) {
        .global, .abstraction, .application => function,
        else => unreachable,
    };

    var function_abstr = expand_globals_recursively(&appl.function);

    _ = &function_abstr;
    //
}
