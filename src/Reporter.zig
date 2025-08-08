const std = @import("std");
const assert = std.debug.assert;

const Context = @import("Context.zig");
const Span = @import("Span.zig");

const INDENT = " " ** 4;

var count: usize = 0;

pub const Layout = union(enum) {
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

pub fn report(comptime format: []const u8, args: anytype, layout: Layout, context: *const Context) void {
    count += 1;

    setStyle(.{ .Bold, .FgRed });
    std.debug.print("Error: ", .{});
    setStyle(.{ .Reset, .FgRed });
    std.debug.print(format, args);
    std.debug.print(".\n", .{});
    setStyle(.{.Reset});

    switch (layout) {
        .token => |token| {
            reportSpan("token", token, context);
        },
        .statement => |stmt| {
            reportSpan("statement", stmt, context);
        },
        .statement_end => |stmt| {
            reportSpan("end of statement", Span.new(stmt.end(), 0), context);
            reportSpan("statement", stmt, context);
        },
        .statement_token => |value| {
            reportSpan("token", value.token, context);
            reportSpan("statement", value.statement, context);
        },
        .symbol_reference => |value| {
            reportSpan("declaration", value.declaration, context);
            reportSpan("reference", value.reference, context);
        },
    }
}

fn reportSpan(comptime label: []const u8, span: Span, context: *const Context) void {
    setStyle(.{.Dim});
    std.debug.print(INDENT ** 1 ++ "({s}:{}) {s}:\n", .{
        context.filepath,
        context.startingLineOf(span),
        label,
    });
    setStyle(.{.Reset});

    if (span.length == 0) {
        const line = context.getSingleLine(span.offset);
        printLineParts(line, Span.new(line.end(), 0), context);
        printLineHighlight(line, Span.new(line.end(), 1));
    } else if (!context.isMultiline(span)) {
        const left = context.getLeftCharacters(span.offset);
        const right = context.getRightCharacters(span.end());
        printLineParts(left, right, context);
        printLineHighlight(left, span);
    } else {
        // TODO(feat): Properly handle multi line tokens/statements
        const border_length = 20;
        setStyle(.{ .Dim, .FgWhite });
        std.debug.print("~" ** border_length ++ "\n", .{});
        setStyle(.{ .Reset, .FgYellow });
        std.debug.print("{s}\n", .{
            span.in(context.text),
        });
        setStyle(.{ .Dim, .FgWhite });
        std.debug.print("~" ** border_length ++ "\n\n", .{});
        setStyle(.{.Reset});
    }
}

fn printLineParts(left: Span, right: Span, context: *const Context) void {
    assert(left.end() <= right.offset);

    std.debug.print(INDENT ** 2, .{});
    setStyle(.{.FgYellow});
    std.debug.print("{s}", .{left.in(context.text)});
    setStyle(.{.Bold});
    std.debug.print("{s}", .{Span.between(left, right).in(context.text)});
    setStyle(.{ .Reset, .FgYellow });
    std.debug.print("{s}", .{right.in(context.text)});
    setStyle(.{.Reset});
    std.debug.print("\n", .{});
}

fn printLineHighlight(left: Span, span: Span) void {
    assert(left.end() <= span.offset);

    setStyle(.{ .Reset, .FgRed });
    std.debug.print(INDENT ** 2, .{});
    for (0..left.length) |_| {
        std.debug.print(" ", .{});
    }
    for (0..span.length) |_| {
        std.debug.print("^", .{});
    }
    std.debug.print("\n", .{});
    setStyle(.{.Reset});
}

const Style = enum(u8) {
    Reset = 0,
    Bold = 1,
    Dim = 2,
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
