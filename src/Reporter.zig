const std = @import("std");
const assert = std.debug.assert;

const Context = @import("Context.zig");
const Span = @import("Span.zig");

var count: usize = 0;

// TODO(feat): Use proper stderr handle

pub const Layout = union(enum) {
    file: void,
    token: Span,
    statement: Span,
    statement_end: Span,
    statement_token: struct {
        statement: Span,
        token: Span,
    },
    symbol_reference: struct {
        declaration: Span,
        reference: Span,
    },
};

pub fn isEmpty() bool {
    return count == 0;
}

pub fn report(
    comptime kind: []const u8,
    comptime description: []const u8,
    args: anytype,
    layout: Layout,
    context: *const Context,
) void {
    count += 1;

    comptime assert(kind.len > 0);
    setStyle(.{ .Bold, .Underline, .FgRed });
    std.debug.print("Error", .{});
    setStyle(.{ .Reset, .Bold, .FgRed });
    std.debug.print(": ", .{});
    setStyle(.{ .Reset, .FgRed });
    std.debug.print(kind, .{});
    std.debug.print(".\n", .{});

    if (description.len > 0) {
        setStyle(.{ .Reset, .FgRed });
        printIndent(1);
        std.debug.print(description, args);
        std.debug.print(".\n", .{});
        setStyle(.{.Reset});
    }

    switch (layout) {
        .file => {
            printFileLabel("bytes in file", context);
        },
        .token => |token| {
            printSpan("token", token, context);
        },
        .statement => |stmt| {
            printSpan("statement", stmt, context);
        },
        .statement_end => |stmt| {
            printSpan("end of statement", Span.new(stmt.end(), 0), context);
            printSpan("statement", stmt, context);
        },
        .statement_token => |value| {
            printSpan("token", value.token, context);
            printSpan("statement", value.statement, context);
        },
        .symbol_reference => |value| {
            printSpan("initial declaration", value.declaration, context);
            printSpan("redeclaration", value.reference, context);
        },
    }
}

fn printIndent(comptime depth: usize) void {
    const INDENT = " " ** 4;
    std.debug.print(INDENT ** depth, .{});
}

fn printLabel(comptime format: []const u8, args: anytype) void {
    setStyle(.{ .FgWhite, .Dim });
    printIndent(1);
    std.debug.print(format, args);
    setStyle(.{.Reset});
}

fn printFileLabel(comptime label: []const u8, context: *const Context) void {
    printLabel("({s}) {s}\n", .{
        context.filepath,
        label,
    });
}

fn printSpan(comptime label: []const u8, span: Span, context: *const Context) void {
    printLabel("({s}:{}) {s}:\n", .{
        context.filepath,
        context.startingLineOf(span),
        label,
    });

    if (span.length == 0) {
        const line = context.getSingleLine(span.offset);
        printLineParts(line, Span.new(line.end(), 0), context);
        printLineHighlight(line, Span.new(line.end(), 1), context);
    } else if (!context.isMultiline(span)) {
        const left = context.getLeftCharacters(span.offset);
        const right = context.getRightCharacters(span.end());
        printLineParts(left, right, context);
        printLineHighlight(left, span, context);
    } else {
        // TODO(feat): Properly handle multi line tokens/statements
        const border_length = 20;
        setStyle(.{ .Dim, .FgWhite });
        std.debug.print("~" ** border_length ++ "\n", .{});
        setStyle(.{ .Reset, .FgYellow });
        std.debug.print("{s}\n", .{span.in(context)});
        setStyle(.{ .Dim, .FgWhite });
        std.debug.print("~" ** border_length ++ "\n\n", .{});
        setStyle(.{.Reset});
    }
}

fn printLineParts(left: Span, right: Span, context: *const Context) void {
    assert(left.end() <= right.offset);

    printIndent(2);
    setStyle(.{.FgYellow});
    std.debug.print("{s}", .{left.in(context)});
    setStyle(.{.Bold});
    std.debug.print("{s}", .{Span.between(left, right).in(context)});
    setStyle(.{ .Reset, .FgYellow });
    std.debug.print("{s}", .{right.in(context)});
    setStyle(.{.Reset});
    std.debug.print("\n", .{});
}

fn printLineHighlight(left: Span, span: Span, context: *const Context) void {
    assert(left.end() <= span.offset);

    setStyle(.{ .Reset, .FgRed });
    printIndent(2);
    for (0..context.charCount(left)) |_| {
        std.debug.print(" ", .{});
    }
    for (0..context.charCount(span)) |_| {
        std.debug.print("^", .{});
    }
    std.debug.print("\n", .{});
    setStyle(.{.Reset});
}

const Style = enum(u8) {
    Reset = 0,
    Bold = 1,
    Dim = 2,
    Underline = 4,
    FgRed = 31,
    FgYellow = 33,
    FgWhite = 37,
};

fn setStyle(comptime styles: anytype) void {
    inline for (styles) |item| {
        const style: Style = item;
        std.debug.print("\x1b[{}m", .{@intFromEnum(style)});
    }
}
