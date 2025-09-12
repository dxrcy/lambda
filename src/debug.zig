const std = @import("std");

const model = @import("model.zig");
const Decl = model.Decl;
const Query = model.Query;
const Term = model.Term;

const Span = @import("Span.zig");

pub fn printDeclarations(declarations: []const Decl) void {
    for (declarations, 0..) |*entry, i| {
        std.debug.print(
            "\n[{}] {s}\n",
            .{ i, entry.decl.name.string() },
        );
        printTerm(entry.decl.term, 0, "");
        std.debug.print("\n", .{});
    }
}

pub fn printQueries(queries: []const Query) void {
    for (queries, 0..) |*query, i| {
        std.debug.print("\n<{}>\n", .{i});
        printTerm(query.term, 0, "");
        std.debug.print("\n", .{});
    }
}

pub fn printTermAll(
    comptime label: []const u8,
    term: *const Term,
    decls: []const Decl,
) void {
    std.debug.print("\n:: " ++ label ++ " :: \n", .{});
    std.debug.print("[ ", .{});
    printTermExpr(term, decls);
    std.debug.print(" ]\n", .{});
    printTerm(term, 0, "");
    std.debug.print("\n", .{});
}

pub fn printTermExpr(term: *const Term, decls: []const Decl) void {
    switch (term.value) {
        .unresolved => {
            std.debug.print("UNRESOLVED", .{});
        },
        .local => {
            if (term.span) |span| {
                std.debug.print("{s}", .{span.string()});
            } else {
                std.debug.print("MISSING", .{});
            }
        },
        .global => |index| {
            std.debug.print("{s}", .{decls[index].name.string()});
        },
        .group => |inner| {
            std.debug.print("(", .{});
            printTermExpr(inner, decls);
            std.debug.print(")", .{});
        },
        .abstraction => |abstr| {
            std.debug.print("(\\{s}. ", .{abstr.parameter.string()});
            printTermExpr(abstr.body, decls);
            std.debug.print(")", .{});
        },
        .application => |appl| {
            std.debug.print("(", .{});
            printTermExpr(appl.function, decls);
            std.debug.print(" ", .{});
            printTermExpr(appl.argument, decls);
            std.debug.print(")", .{});
        },
    }
}

pub fn printTerm(
    term: *const Term,
    depth: usize,
    comptime prefix: []const u8,
) void {
    if (depth > 30) {
        @panic("max recursion depth reached");
    }

    switch (term.value) {
        .unresolved => {
            printLabel(depth, prefix, "UNRESOLVED");
            printSpanValue(term.span, null);
        },
        .local => |id| {
            printLabel(depth, prefix, "local");
            printSpanValue(term.span, id);
        },
        .global => |index| {
            printLabel(depth, prefix, "global");
            std.debug.print("[{}] ", .{index});
            printSpanValue(term.span, null);
        },
        .group => |inner| {
            printLabel(depth, prefix, "group");
            printSpanValue(term.span, null);
            printTerm(inner, depth + 1, "");
        },
        .abstraction => |abstr| {
            printLabel(depth, prefix, "abstraction");
            printSpanValue(term.span, null);
            printLabel(depth + 1, "parameter", "");
            printSpanValue(abstr.parameter, abstr.id);
            printTerm(abstr.body, depth + 1, "body");
        },
        .application => |appl| {
            printLabel(depth, prefix, "application");
            printSpanValue(term.span, null);
            printTerm(appl.function, depth + 1, "function");
            printTerm(appl.argument, depth + 1, "argument");
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

fn printSpanValue(span: ?Span, id: ?usize) void {
    if (span) |span_unwrapped| {
        std.debug.print("`", .{});
        printSpanInline(span_unwrapped.string());
        std.debug.print("`", .{});
    } else {
        std.debug.print("CONSTRUCTED", .{});
    }

    if (id) |id_value| {
        std.debug.print(" {{0x{x:04}}}", .{id_value});
    }

    std.debug.print("\n", .{});
}

pub fn printSpanInline(value: []const u8) void {
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
}
