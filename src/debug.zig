const std = @import("std");

const model = @import("model.zig");
const TermStore = model.TermStore;
const Term = model.Term;

pub fn debugTerm(
    term: *const Term,
    terms: []const Term,
    text: []const u8,
) void {
    debugTermInner(term, 0, "", terms, text);
}

pub fn debugTermInner(
    term: *const Term,
    depth: usize,
    comptime prefix: []const u8,
    terms: []const Term,
    text: []const u8,
) void {
    switch (term.*) {
        .unresolved => |span| {
            debugLabel(depth, prefix, "UNRESOLVED");
            debugSpan(span.in(text));
        },
        .local => |local| {
            debugLabel(depth, prefix, "local");
            std.debug.print("{{{}}} ", .{local.index});
            debugSpan(local.span.in(text));
        },
        .global => |global| {
            debugLabel(depth, prefix, "global");
            std.debug.print("[{}] ", .{global.index});
            debugSpan(global.span.in(text));
        },
        .group => |group| {
            debugLabel(depth, prefix, "group");
            debugSpan(term.getSpan().in(text));
            debugTermInner(&terms[group.inner], depth + 1, "", terms, text);
        },
        .abstraction => |abstr| {
            debugLabel(depth, prefix, "abstraction");
            debugSpan(term.getSpan().in(text));
            debugLabel(depth + 1, "L", "parameter");
            debugSpan(abstr.parameter.in(text));
            debugTermInner(&terms[abstr.right], depth + 1, "R", terms, text);
        },
        .application => |appl| {
            debugLabel(depth, prefix, "application");
            debugSpan(term.getSpan().in(text));
            debugTermInner(&terms[appl.left], depth + 1, "L", terms, text);
            debugTermInner(&terms[appl.right], depth + 1, "R", terms, text);
        },
    }
}

fn debugLabel(
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

fn debugSpan(value: []const u8) void {
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
