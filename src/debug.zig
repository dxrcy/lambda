const std = @import("std");

const model = @import("model.zig");
const Decl = model.Decl;
const Query = model.Query;
const Term = model.Term;

const Span = @import("Span.zig");
const output = @import("output.zig");

// TODO: Add wrappers to recursive functions, flush on completion

pub fn printDeclarations(declarations: []const Decl) void {
    for (declarations, 0..) |*entry, i| {
        output.print(
            "\n[{}] {s}\n",
            .{ i, entry.decl.name.string() },
        );
        printTerm(entry.decl.term, 0, "");
        output.print("\n", .{});
    }
}

pub fn printQueries(queries: []const Query) void {
    for (queries, 0..) |*query, i| {
        output.print("\n<{}>\n", .{i});
        printTerm(query.term, 0, "");
        output.print("\n", .{});
    }
}

pub fn printTermAll(
    comptime label: []const u8,
    term: *const Term,
    decls: []const Decl,
) void {
    output.print("\n:: " ++ label ++ " :: \n", .{});
    output.print("[ ", .{});
    printTermExpr(term, decls);
    output.print(" ]\n", .{});
    printTerm(term, 0, "");
    output.print("\n", .{});
}

pub fn printTermExpr(term: *const Term, decls: []const Decl) void {
    switch (term.value) {
        .unresolved => {
            output.print("UNRESOLVED", .{});
        },
        .local => {
            if (term.span) |span| {
                output.print("{s}", .{span.string()});
            } else {
                output.print("MISSING", .{});
            }
        },
        .global => |index| {
            output.print("{s}", .{decls[index].name.string()});
        },
        .group => |inner| {
            output.print("(", .{});
            printTermExpr(inner, decls);
            output.print(")", .{});
        },
        .abstraction => |abstr| {
            output.print("(\\{s}. ", .{abstr.parameter.string()});
            printTermExpr(abstr.body, decls);
            output.print(")", .{});
        },
        .application => |appl| {
            output.print("(", .{});
            printTermExpr(appl.function, decls);
            output.print(" ", .{});
            printTermExpr(appl.argument, decls);
            output.print(")", .{});
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
            output.print("[{}] ", .{index});
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
        output.print("|" ++ " " ** 5, .{});
    }
    if (prefix.len > 0) {
        output.print("{s}", .{prefix});
    }
    if (prefix.len > 0 and label.len > 0) {
        output.print(".", .{});
    }
    output.print("{s}: ", .{label});
}

fn printSpanValue(span: ?Span, id: ?usize) void {
    if (span) |span_unwrapped| {
        output.print("`", .{});
        printSpanInline(span_unwrapped.string());
        output.print("`", .{});
    } else {
        output.print("CONSTRUCTED", .{});
    }

    if (id) |id_value| {
        output.print(" {{0x{x:04}}}", .{id_value});
    }

    output.print("\n", .{});
}

pub fn printSpanInline(value: []const u8) void {
    var was_whitespace = true;
    for (value) |char| {
        if (std.ascii.isWhitespace(char)) {
            if (!was_whitespace) {
                output.print(" ", .{});
                was_whitespace = true;
            }
        } else {
            was_whitespace = false;
            output.print("{c}", .{char});
        }
    }
}
