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
const AbstrId = model.AbstrId;
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

    // debug.printDeclarations(decls.items, &context);
    // debug.printQueries(queries.items, &context);

    // std.debug.print("Results:\n", .{});
    // std.debug.print("\n", .{});
    {
        for (queries.items) |*query| {
            const result = resolve(
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
}

const MAX_RESOLVE_RECURSION = 2_000;
const MAX_GLOBAL_EXPAND = 200;

const ResolveError = Allocator.Error || error{MaxRecursion};

fn resolve(
    term: *const Term,
    depth: usize,
    decls: []const Decl,
    term_allocator: Allocator,
) ResolveError!*const Term {
    if (depth >= MAX_RESOLVE_RECURSION) {
        return error.MaxRecursion;
    }
    return switch (term.value) {
        .global, .abstraction => term,
        // Flatten group
        .group => |inner| try resolve(
            inner,
            depth + 1,
            decls,
            term_allocator,
        ),
        .application => |appl| try resolveApplication(
            &appl,
            depth + 1,
            decls,
            term_allocator,
        ),
        .unresolved => @panic("symbol should have been resolved already"),
        .local => @panic("local binding should have been beta-reduced already"),
    };
}

fn resolveApplication(
    appl: *const Term.Appl,
    depth: usize,
    decls: []const Decl,
    term_allocator: Allocator,
) ResolveError!*const Term {
    switch (appl.function.value) {
        .group, .global, .abstraction, .application => {},
        .unresolved => @panic("symbol should have been resolved already"),
        .local => @panic("local binding should have been beta-reduced already"),
    }

    const function = try expandGlobal(
        appl.function,
        depth,
        decls,
        term_allocator,
    );

    const product = try betaReduce(
        function.body,
        function.id,
        appl.argument,
        term_allocator,
    ) orelse function.body;

    switch (product.value) {
        .global, .abstraction, .application => {},
        .group => @panic("group should have been flattened already"),
        .unresolved => @panic("symbol should have been resolved already"),
        .local => @panic("local binding should have been beta-reduced already"),
    }

    return resolve(
        product,
        depth + 1,
        decls,
        term_allocator,
    );
}

fn expandGlobal(
    initial_term: *const Term,
    depth: usize,
    decls: []const Decl,
    term_allocator: Allocator,
) ResolveError!*const Term.Abstr {
    var term = initial_term;
    for (0..MAX_GLOBAL_EXPAND) |_| {
        const product = try resolve(
            term,
            depth + 1,
            decls,
            term_allocator,
        );
        term = switch (product.value) {
            .unresolved => @panic("symbol should have been resolved already"),
            .local => @panic("local binding should have been beta-reduced already"),
            .application => @panic("application should have been resolved already"),
            .global => |global| decls[global].term,
            .group => |inner| inner,
            .abstraction => |abstr| {
                return &abstr;
            },
        };
    }
    return error.MaxRecursion;
}

/// Returns `null` if no descendant term was substituted; no need to deep-copy.
fn betaReduce(
    term: *Term,
    abstr_id: AbstrId,
    applied_argument: *Term,
    term_allocator: Allocator,
) Allocator.Error!?*Term {
    // Use a placeholder span for constructed terms, since they do not refer to
    // any part of the source text, even if their descendants may.
    const DUMMY_SPAN = Span.new(0, 0);

    switch (term.value) {
        .unresolved => @panic("symbol should have been resolved already"),
        .global => return null,
        .local => |id| {
            if (id != abstr_id) {
                return null;
            }
            return try deepCopyTerm(applied_argument, term_allocator);
        },
        .group => |inner| {
            // Flatten group
            return try betaReduce(
                inner,
                abstr_id,
                applied_argument,
                term_allocator,
            );
        },
        .abstraction => |abstr| {
            const body = try betaReduce(
                abstr.body,
                abstr_id,
                applied_argument,
                term_allocator,
            ) orelse {
                return null;
            };
            return try Term.create(DUMMY_SPAN, .{
                .abstraction = .{
                    .id = abstr.id,
                    .parameter = abstr.parameter,
                    .body = body,
                },
            }, term_allocator);
        },
        .application => |appl| {
            const function = try betaReduce(
                appl.function,
                abstr_id,
                applied_argument,
                term_allocator,
            );
            const argument = try betaReduce(
                appl.argument,
                abstr_id,
                applied_argument,
                term_allocator,
            );
            if (function == null and argument == null) {
                return null;
            }
            return try Term.create(DUMMY_SPAN, .{
                .application = .{
                    .function = function orelse appl.function,
                    .argument = argument orelse appl.argument,
                },
            }, term_allocator);
        },
    }
}

/// *Deep-copy* term by allocating and copying children.
/// Does not copy non-parent terms (`global` and `local`), since they should be
/// not be mutated by the caller.
pub fn deepCopyTerm(term: *Term, allocator: Allocator) Allocator.Error!*Term {
    const copy_value: Term.Kind = switch (term.value) {
        .unresolved => @panic("symbol should have been resolved already"),
        .global, .local => return term,
        .group => |inner| {
            // Flatten group
            return try deepCopyTerm(inner, allocator);
        },
        .abstraction => |abstr| .{
            .abstraction = .{
                .id = abstr.id,
                .parameter = abstr.parameter,
                .body = try deepCopyTerm(abstr.body, allocator),
            },
        },
        .application => |appl| .{
            .application = .{
                .function = try deepCopyTerm(appl.function, allocator),
                .argument = try deepCopyTerm(appl.argument, allocator),
            },
        },
    };
    return try Term.create(term.span, copy_value, allocator);
}
