const std = @import("std");

const model = @import("model.zig");
const Decl = model.Decl;
const Query = model.Query;
const Term = model.Term;

const Span = @import("Span.zig");
const output = @import("output.zig");

const MAX_RECURSION = 256;

const WARNING_CUTOFF = "#[CUTOFF]#";
const WARNING_UNRESOLVED = "#[UNRESOLVED]#";
const WARNING_UNKNOWN = "#[UNKNOWN]#";
const WARNING_CONSTRUCTED = "#[CONSTRUCTED]#";

pub fn printDeclarations(declarations: []const Decl) void {
    for (declarations, 0..) |*entry, i| {
        output.print("\n[{}] {s}\n", .{ i, entry.decl.name.string() });
        printTermDetailedInner(entry.decl.term, 0, "");
        output.print("\n", .{});
    }
}

pub fn printQueries(queries: []const Query) void {
    for (queries, 0..) |*query, i| {
        output.print("\n<{}>\n", .{i});
        printTermDetailedInner(query.term, 0, "");
        output.print("\n", .{});
    }
}

pub fn printTermInline(term: *const Term, decls: []const Decl) void {
    printTermInlineInner(term, true, decls, 0);
}

fn printTermInlineInner(
    term: *const Term,
    comptime never_ambiguous: bool,
    decls: []const Decl,
    depth: usize,
) void {
    if (depth > MAX_RECURSION) {
        output.print(WARNING_CUTOFF, .{});
        return;
    }

    // Whether parentheses are required to avoid ambiguity
    const require_parens = !never_ambiguous and switch (term.value) {
        .group, .abstraction, .application => true,
        else => false,
    };

    if (require_parens) {
        output.print("(", .{});
    }

    switch (term.value) {
        .unresolved => {
            output.print(WARNING_UNRESOLVED, .{});
        },
        .local => if (term.span) |span| {
            output.print("{s}", .{span.string()});
        } else {
            output.print(WARNING_UNKNOWN, .{});
        },
        .global => |index| {
            output.print("{s}", .{decls[index].name.string()});
        },
        .group => |inner| {
            printTermInlineInner(inner, true, decls, depth + 1);
        },
        .abstraction => |abstr| {
            output.print("\\{s}. ", .{abstr.parameter.string()});
            printTermInlineInner(abstr.body, true, decls, depth + 1);
        },
        .application => |appl| {
            printTermInlineInner(appl.function, false, decls, depth + 1);
            output.print(" ", .{});
            printTermInlineInner(appl.argument, false, decls, depth + 1);
        },
    }

    if (require_parens) {
        output.print(")", .{});
    }
}

pub fn printTermDetailed(term: *const Term) void {
    printTermDetailedInner(term, 0, "");
}

fn printTermDetailedInner(
    term: *const Term,
    depth: usize,
    comptime prefix: []const u8,
) void {
    if (depth > MAX_RECURSION) {
        output.print(WARNING_CUTOFF, .{});
        return;
    }

    switch (term.value) {
        .unresolved => {
            printLabel(depth, prefix, WARNING_UNRESOLVED);
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
            printTermDetailedInner(inner, depth + 1, "");
        },
        .abstraction => |abstr| {
            printLabel(depth, prefix, "abstraction");
            printSpanValue(term.span, null);
            printLabel(depth + 1, "parameter", "");
            printSpanValue(abstr.parameter, abstr.id);
            printTermDetailedInner(abstr.body, depth + 1, "body");
        },
        .application => |appl| {
            printLabel(depth, prefix, "application");
            printSpanValue(term.span, null);
            printTermDetailedInner(appl.function, depth + 1, "function");
            printTermDetailedInner(appl.argument, depth + 1, "argument");
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
        output.print(WARNING_CONSTRUCTED, .{});
    }

    if (comptime id) |id_value| {
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
