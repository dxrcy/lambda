const std = @import("std");

const Context = @import("Context.zig");

const model = @import("model.zig");
const Decl = model.Decl;
const Query = model.Query;
const Term = model.Term;

pub fn printDeclarations(
    declarations: []const Decl,
    context: *const Context,
) void {
    for (declarations, 0..) |*decl, i| {
        std.debug.print("\n[{}] {s}\n", .{ i, decl.name.in(context) });
        printTerm(decl.term, 0, "", context);
        std.debug.print("\n", .{});
    }
}

pub fn printQueries(
    queries: []const Query,
    context: *const Context,
) void {
    for (queries, 0..) |*query, i| {
        std.debug.print("\n<{}>\n", .{i});
        printTerm(query.term, 0, "", context);
        std.debug.print("\n", .{});
    }
}

pub fn printTermAll(
    comptime label: []const u8,
    term: *const Term,
    decls: []const Decl,
    context: *const Context,
) void {
    std.debug.print("\n:: " ++ label ++ " :: \n", .{});
    std.debug.print("[ ", .{});
    printTermExpr(term, decls, context);
    std.debug.print(" ]\n", .{});
    printTerm(term, 0, "", context);
    std.debug.print("\n", .{});
}

pub fn printTermExpr(
    term: *const Term,
    decls: []const Decl,
    context: *const Context,
) void {
    switch (term.value) {
        .unresolved => {
            std.debug.print("UNRESOLVED", .{});
        },
        .local => {
            std.debug.print("{s}", .{term.span.in(context)});
        },
        .global => |index| {
            std.debug.print("{s}", .{decls[index].name.in(context)});
        },
        .group => |inner| {
            std.debug.print("(", .{});
            printTermExpr(inner, decls, context);
            std.debug.print(")", .{});
        },
        .abstraction => |abstr| {
            std.debug.print("(\\{s}. ", .{abstr.parameter.in(context)});
            printTermExpr(abstr.body, decls, context);
            std.debug.print(")", .{});
        },
        .application => |appl| {
            std.debug.print("(", .{});
            printTermExpr(appl.function, decls, context);
            std.debug.print(" ", .{});
            printTermExpr(appl.argument, decls, context);
            std.debug.print(")", .{});
        },
    }
}

pub fn printTerm(
    term: *const Term,
    depth: usize,
    comptime prefix: []const u8,
    context: *const Context,
) void {
    if (depth > 30) {
        @panic("max recursion depth reached");
    }

    switch (term.value) {
        .unresolved => {
            printLabel(depth, prefix, "UNRESOLVED");
            printSpan(term.span.in(context), null);
        },
        .local => |ptr| {
            printLabel(depth, prefix, "local");
            printSpan(term.span.in(context), ptr);
        },
        .global => |index| {
            printLabel(depth, prefix, "global");
            std.debug.print("[{}] ", .{index});
            printSpan(term.span.in(context), null);
        },
        .group => |inner| {
            printLabel(depth, prefix, "group");
            printSpan(term.span.in(context), null);
            printTerm(inner, depth + 1, "", context);
        },
        .abstraction => |abstr| {
            printLabel(depth, prefix, "abstraction");
            printSpan(term.span.in(context), null);
            printLabel(depth + 1, "parameter", "");
            printSpan(abstr.parameter.in(context), term);
            printTerm(abstr.body, depth + 1, "body", context);
        },
        .application => |appl| {
            printLabel(depth, prefix, "application");
            printSpan(term.span.in(context), null);
            printTerm(appl.function, depth + 1, "function", context);
            printTerm(appl.argument, depth + 1, "argument", context);
        },
    }
}

fn printLabel(
    depth: usize,
    comptime prefix: []const u8,
    comptime label: []const u8,
) void {
    for (0..depth) |_| {
        std.debug.print("|" ++ " " ** 5, .{});
    }
    if (prefix.len > 0) {
        std.debug.print("{s}", .{prefix});
    }
    if (prefix.len > 0 and label.len > 0) {
        std.debug.print(".", .{});
    }
    std.debug.print("{s}: ", .{label});
}

fn printSpan(value: []const u8, term_ptr: ?*const Term) void {
    if (value.len == 0) {
        std.debug.print("-", .{});
    } else {
        std.debug.print("`", .{});
        var was_whitespace = true;
        for (value) |char| {
            if (std.ascii.isWhitespace(char)) {
                if (!was_whitespace) {
                    std.debug.print(" ", .{});
                    was_whitespace = true;
                }
            } else {
                was_whitespace = false;
                std.debug.print("{c}", .{char});
            }
        }
        std.debug.print("`", .{});
    }

    if (term_ptr) |ptr| {
        std.debug.print(" {{0x{x:08}}}", .{@intFromPtr(ptr)});
    }

    std.debug.print("\n", .{});
}
