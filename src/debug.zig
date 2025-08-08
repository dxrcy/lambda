const std = @import("std");

const Context = @import("Context.zig");

const model = @import("model.zig");
const Decl = model.Decl;
const TermStore = model.TermStore;
const Term = model.Term;

pub fn printDeclarations(
    declarations: []const Decl,
    terms: *const TermStore,
    context: *const Context,
) void {
    for (declarations, 0..) |*decl, i| {
        const term = terms.get(decl.term);
        std.debug.print("\n[{}] {s}\n", .{ i, decl.name.in(context) });
        printTerm(term, 0, "", terms.entries.items, context);
        std.debug.print("\n", .{});
    }
}

fn printTerm(
    term: *const Term,
    depth: usize,
    comptime prefix: []const u8,
    terms: []const Term,
    context: *const Context,
) void {
    switch (term.value) {
        .unresolved => {
            printLabel(depth, prefix, "UNRESOLVED");
            printSpan(term.span.in(context));
        },
        .local => |index| {
            printLabel(depth, prefix, "local");
            std.debug.print("{{{}}} ", .{index});
            printSpan(term.span.in(context));
        },
        .global => |index| {
            printLabel(depth, prefix, "global");
            std.debug.print("[{}] ", .{index});
            printSpan(term.span.in(context));
        },
        .group => |inner| {
            printLabel(depth, prefix, "group");
            printSpan(term.span.in(context));
            printTerm(&terms[inner], depth + 1, "", terms, context);
        },
        .abstraction => |abstr| {
            printLabel(depth, prefix, "abstraction");
            printSpan(term.span.in(context));
            printLabel(depth + 1, "parameter", "");
            printSpan(abstr.parameter.in(context));
            printTerm(&terms[abstr.body], depth + 1, "body", terms, context);
        },
        .application => |appl| {
            printLabel(depth, prefix, "application");
            printSpan(term.span.in(context));
            printTerm(&terms[appl.function], depth + 1, "function", terms, context);
            printTerm(&terms[appl.argument], depth + 1, "argument", terms, context);
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
        std.debug.print("{s}.", .{prefix});
    }
    std.debug.print("{s}: ", .{label});
}

fn printSpan(value: []const u8) void {
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
    std.debug.print("\n", .{});
}
