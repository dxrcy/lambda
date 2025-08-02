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
    switch (term.value) {
        .unresolved => {
            debugLabel(depth, prefix, "UNRESOLVED");
            debugSpan(term.span.in(text));
        },
        .local => |index| {
            debugLabel(depth, prefix, "local");
            std.debug.print("{{{}}} ", .{index});
            debugSpan(term.span.in(text));
        },
        .global => |index| {
            debugLabel(depth, prefix, "global");
            std.debug.print("[{}] ", .{index});
            debugSpan(term.span.in(text));
        },
        .group => |inner| {
            debugLabel(depth, prefix, "group");
            debugSpan(term.span.in(text));
            debugTermInner(&terms[inner], depth + 1, "", terms, text);
        },
        .abstraction => |abstr| {
            debugLabel(depth, prefix, "abstraction");
            debugSpan(term.span.in(text));
            debugLabel(depth + 1, "L", "parameter");
            debugSpan(abstr.parameter.in(text));
            debugTermInner(&terms[abstr.body], depth + 1, "R", terms, text);
        },
        .application => |appl| {
            debugLabel(depth, prefix, "application");
            debugSpan(term.span.in(text));
            debugTermInner(&terms[appl.function], depth + 1, "L", terms, text);
            debugTermInner(&terms[appl.argument], depth + 1, "R", terms, text);
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
