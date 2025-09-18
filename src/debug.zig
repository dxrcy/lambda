const std = @import("std");

const TextStore = @import("text/TextStore.zig");
const SourceSpan = TextStore.SourceSpan;

const model = @import("model.zig");
const Decl = model.Decl;
const Query = model.Query;
const Term = model.Term;

const output = @import("output.zig");

const MAX_RECURSION = 256;

const WARNING_CUTOFF = "#[CUTOFF]#";
const WARNING_UNRESOLVED = "#[UNRESOLVED]#";
const WARNING_UNKNOWN = "#[UNKNOWN]#";
const WARNING_CONSTRUCTED = "#[CONSTRUCTED]#";

pub fn printDeclarations(
    declarations: []const Decl,
    text: *const TextStore,
) void {
    for (declarations, 0..) |*decl, i| {
        output.print("\n[{}] {s}\n", .{ i, decl.name.in(text) });
        printTermDetailedInner(decl.term, 0, "", text);
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

pub fn printSignature(signature: ?u64) void {
    if (signature) |sig| {
        output.print("0x{x:08}", .{sig});
    } else {
        output.print(WARNING_CUTOFF, .{});
    }
}

pub fn printTermInline(
    term: *const Term,
    decls: []const Decl,
    text: *const TextStore,
) void {
    printTermInlineInner(term, true, decls, 0, text);
}

fn printTermInlineInner(
    term: *const Term,
    comptime never_ambiguous: bool,
    decls: []const Decl,
    depth: usize,
    text: *const TextStore,
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
            output.print("{s}", .{span.in(text)});
        } else {
            output.print(WARNING_UNKNOWN, .{});
        },
        .global => |index| {
            output.print("{s}", .{decls[index].name.in(text)});
        },
        .group => |inner| {
            printTermInlineInner(inner, true, decls, depth + 1, text);
        },
        .abstraction => |abstr| {
            output.print("\\{s}. ", .{abstr.parameter.in(text)});
            printTermInlineInner(abstr.body, true, decls, depth + 1, text);
        },
        .application => |appl| {
            printTermInlineInner(appl.function, false, decls, depth + 1, text);
            output.print(" ", .{});
            printTermInlineInner(appl.argument, false, decls, depth + 1, text);
        },
    }

    if (require_parens) {
        output.print(")", .{});
    }
}

pub fn printTermDetailed(term: *const Term, text: *const TextStore) void {
    printTermDetailedInner(term, 0, "", text);
}

// TODO: Re-order parameters
fn printTermDetailedInner(
    term: *const Term,
    depth: usize,
    comptime prefix: []const u8,
    text: *const TextStore,
) void {
    if (depth > MAX_RECURSION) {
        output.print(WARNING_CUTOFF, .{});
        return;
    }

    switch (term.value) {
        .unresolved => {
            printLabel(depth, prefix, WARNING_UNRESOLVED);
            printSpanValue(term.span, false, text);
        },
        .local => {
            printLabel(depth, prefix, "local");
            printSpanValue(term.span, true, text);
        },
        .global => |index| {
            printLabel(depth, prefix, "global");
            output.print("[{}] ", .{index});
            printSpanValue(term.span, false, text);
        },
        .group => |inner| {
            printLabel(depth, prefix, "group");
            printSpanValue(term.span, false, text);
            printTermDetailedInner(inner, depth + 1, "", text);
        },
        .abstraction => |abstr| {
            printLabel(depth, prefix, "abstraction");
            printSpanValue(term.span, false, text);
            printLabel(depth + 1, "parameter", "");
            printSpanValue(abstr.parameter, true, text);
            printTermDetailedInner(abstr.body, depth + 1, "body", text);
        },
        .application => |appl| {
            printLabel(depth, prefix, "application");
            printSpanValue(term.span, false, text);
            printTermDetailedInner(appl.function, depth + 1, "function", text);
            printTermDetailedInner(appl.argument, depth + 1, "argument", text);
        },
    }
}

// TODO: Re-order parameters
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

fn printSpanValue(
    span: ?SourceSpan,
    comptime details: bool,
    text: *const TextStore,
) void {
    const span_unwrapped = span orelse {
        output.print(WARNING_CONSTRUCTED, .{});
        output.print("\n", .{});
        return;
    };

    output.print("`", .{});
    printSpanInline(span_unwrapped.in(text));
    output.print("`", .{});

    if (details) {
        const path = text.getSourcePath(span_unwrapped.source) orelse "";
        output.print(" {{{s}@{x}}}", .{ path, span_unwrapped.free.offset });
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
