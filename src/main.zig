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
                &context,
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

const ResolveError = Allocator.Error || error{MaxRecursion};

fn resolve(
    term: *const Term,
    depth: usize,
    decls: []const Decl,
    term_allocator: Allocator,
    // debugging
    context: *const Context,
) ResolveError!*const Term {
    const MAX_RESOLVE_RECURSION = 20;

    if (depth >= MAX_RESOLVE_RECURSION) {
        return error.MaxRecursion;
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

    switch (appl.function.value) {
        .global, .abstraction, .application => {},
        else => unreachable,
    }

    const function_term = try expand_global(
        appl.function,
        depth,
        decls,
        term_allocator,
        context,
    );

    const function_abstr = function_term.value.abstraction;

    const result = try beta_reduce(
        function_abstr.id,
        function_abstr.body,
        appl.argument,
        term_allocator,
        decls,
        context,
    ) orelse function_abstr.body;

    switch (result.value) {
        .unresolved, .group => unreachable,
        .local => @panic("local binding should have been beta-reduced already"),
        .global, .abstraction, .application => {},
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
    // debugging
    context: *const Context,
) ResolveError!*const Term {
    const MAX_GLOBAL_EXPAND = 20;

    // std.debug.print("-- expand?\n", .{});

    var term = initial_term;

    for (0..MAX_GLOBAL_EXPAND) |_| {
        // if (i > 0) {
        //     std.debug.print("-- expand!\n", .{});
        // }

        const product = try resolve(
            term,
            depth + 1,
            decls,
            term_allocator,
            context,
        );
        // std.debug.print("-- expansion => {s}\n", .{@tagName(product.value)});

        term = switch (product.value) {
            .unresolved, .local, .application => unreachable,
            .global => |global| decls[global].term,
            .group => |inner| inner,
            .abstraction => {
                return product;
            },
        };
    }

    return error.MaxRecursion;
}

/// Returns `null` if no descendant term was substituted; no need to deep-copy.
fn beta_reduce(
    abstr_id: AbstrId,
    substitution_body: *Term,
    substitution_argument: *Term,
    term_allocator: Allocator,
    // debugging
    decls: []const Decl,
    context: *const Context,
) Allocator.Error!?*Term {
    switch (substitution_body.value) {
        .unresolved => unreachable,
        .global => return null,
        .local => |id| {
            if (id != abstr_id) {
                return null;
            }
            return try deepCopyTerm(substitution_argument, term_allocator);
        },
        .group => |inner| {
            // Flatten group
            return try beta_reduce(
                abstr_id,
                inner,
                substitution_argument,
                term_allocator,
                decls,
                context,
            );
        },
        .abstraction => |abstr| {
            const body = try beta_reduce(
                abstr_id,
                abstr.body,
                substitution_argument,
                term_allocator,
                decls,
                context,
            ) orelse {
                return null;
            };
            return try Term.create(Span.new(0, 0), .{
                .abstraction = .{
                    .id = abstr.id,
                    .parameter = abstr.parameter,
                    .body = body,
                },
            }, term_allocator);
        },
        .application => |appl| {
            const function = try beta_reduce(
                abstr_id,
                appl.function,
                substitution_argument,
                term_allocator,
                decls,
                context,
            );
            const argument = try beta_reduce(
                abstr_id,
                appl.argument,
                substitution_argument,
                term_allocator,
                decls,
                context,
            );
            if (function == null and argument == null) {
                return null;
            }
            return try Term.create(Span.new(0, 0), .{
                .application = .{
                    .function = function orelse appl.function,
                    .argument = argument orelse appl.argument,
                },
            }, term_allocator);
        },
    }
}

/// *Deep-copy* term by allocating and copying children.
/// Copy of `.local` refers to *original* abstraction definition.
pub fn deepCopyTerm(self: *Term, allocator: Allocator) Allocator.Error!*Term {
    const copy_value = switch (self.value) {
        .unresolved, .global, .local => self.value,
        .group => |inner| {
            // Flatten group
            return try deepCopyTerm(inner, allocator);
        },
        .abstraction => |abstr| Term.Kind{
            .abstraction = .{
                .id = abstr.id,
                .parameter = abstr.parameter,
                .body = try deepCopyTerm(abstr.body, allocator),
            },
        },
        .application => |appl| Term.Kind{
            .application = .{
                .function = try deepCopyTerm(appl.function, allocator),
                .argument = try deepCopyTerm(appl.argument, allocator),
            },
        },
    };
    return try Term.create(self.span, copy_value, allocator);
}
