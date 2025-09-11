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
const Term = model.Term;

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
            const result = try resolve(
                query.term,
                0,
                decls.items,
                term_allocator.allocator(),
                &context,
            );
            debug.printTerm(result, 0, "", &context);
        }
    }
}

const ResolveError = Allocator.Error;

fn resolve(
    term: *const Term,
    depth: usize,
    decls: []const Decl,
    term_allocator: Allocator,
    context: *const Context,
) ResolveError!*const Term {
    const MAX_RESOLVE_RECURSION = 50;

    // std.debug.print("resolve?\n", .{});

    if (depth >= MAX_RESOLVE_RECURSION) {
        @panic("max recursion");
        // return error.MaxRecursion;
    }

    const appl = switch (term.value) {
        .unresolved, .local => unreachable,
        .group => |inner| return resolve(
            inner,
            depth + 1,
            decls,
            term_allocator,
            context,
        ),
        .global, .abstraction => return term,
        .application => |appl| appl,
    };

    // std.debug.print("RESOLVE!\n", .{});

    switch (appl.function.value) {
        .global, .abstraction, .application => {},
        else => unreachable,
    }

    std.debug.print("\n\n", .{});
    debug.printTerm(appl.function, 0, "PRE-EXPAND-FUNCTION", context);

    const function_term = try expand_global(
        appl.function,
        depth,
        decls,
        term_allocator,
        context,
    );

    debug.printTerm(&Term{
        .span = Span.new(0, 0),
        .value = .{ .application = .{
            .function = @constCast(function_term),
            .argument = appl.argument,
        } },
    }, 0, "POST-EXPAND", context);
    std.debug.print("\n", .{});

    const function_abstr = function_term.value.abstraction;

    const result = try beta_reduce(
        function_term,
        function_abstr.body,
        appl.argument,
        term_allocator,
        context,
    );

    debug.printTerm(result, 0, "RESULT", context);
    std.debug.print("\n", .{});

    switch (result.value) {
        .global, .abstraction, .application => {},
        else => unreachable,
    }

    return resolve(
        result,
        depth + 1,
        decls,
        term_allocator,
        context,
    );
}

fn expand_global(
    initial_term: *const Term,
    depth: usize,
    decls: []const Decl,
    term_allocator: Allocator,
    context: *const Context,
) ResolveError!*const Term {
    // std.debug.print("EXPAND GLOBAL\n", .{});
    const MAX_GLOBAL_EXPAND = 100;

    var term = initial_term;

    for (0..MAX_GLOBAL_EXPAND) |_| {
        const product = try resolve(
            term,
            depth + 1,
            decls,
            term_allocator,
            context,
        );
        term = switch (product.value) {
            .unresolved, .local, .application => unreachable,
            .global => |global| decls[global].term,
            .group => |inner| inner,
            .abstraction => {
                return product;
            },
        };
    }

    @panic("expansion limit reached. declaration reference cycle?");
    // return error.MaxRecursion;
}

fn beta_reduce(
    abstr_def: *const Term,
    substitution_body: *Term,
    substitution_argument: *Term,
    term_allocator: Allocator,
    context: *const Context,
) Allocator.Error!*Term {
    switch (substitution_body.value) {
        .unresolved => unreachable,
        .global => return substitution_body,
        .local => |ptr| {
            if (ptr == abstr_def) {
                std.debug.print("\n\n----- SUBSTITUTE -----\n", .{});
                debug.printTerm(substitution_body, 0, "SUBSTITUTION-BODY", context);
                debug.printTerm(substitution_argument, 0, "SUBSTITUTION-ARGUMENT", context);
                std.debug.print("\n", .{});
                return try substitution_argument.clone(term_allocator);
            }
            return substitution_body;
        },
        .group => |inner| {
            return try beta_reduce(
                abstr_def,
                inner,
                substitution_argument,
                term_allocator,
                context,
            );
        },
        .abstraction => |abstr| {
            const body = try beta_reduce(
                abstr_def,
                abstr.body,
                substitution_argument,
                term_allocator,
                context,
            );
            return try Term.create(Span.new(0, 0), .{
                .abstraction = .{
                    .parameter = abstr.parameter,
                    .body = body,
                },
            }, term_allocator);
        },
        .application => |appl| {
            const function = try beta_reduce(
                abstr_def,
                appl.function,
                substitution_argument,
                term_allocator,
                context,
            );
            const argument = try beta_reduce(
                abstr_def,
                appl.argument,
                substitution_argument,
                term_allocator,
                context,
            );
            return try Term.create(Span.new(0, 0), .{
                .application = .{
                    .function = function,
                    .argument = argument,
                },
            }, term_allocator);
        },
    }
}
