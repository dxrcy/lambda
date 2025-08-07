const std = @import("std");

const Context = @import("Context.zig");
const Span = @import("Span.zig");

var count: usize = 0;

pub const Layout = union(enum) {
    token: Span,
    statement: Span,
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
    const indent = " " ** 4;

    setStyle(.{.Dim});
    std.debug.print(indent ** 1 ++ "({s}:{}) {s}:\n", .{
        context.filepath,
        context.startingLineOf(span),
        label,
    });
    setStyle(.{.Reset});

    // TODO(feat): Properly handle multi line tokens/statements
    if (context.isMultiline(span)) {
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
    } else {
        std.debug.print(indent ** 2, .{});

        const left = context.getLeftCharacters(span);
        const right = context.getRightCharacters(span);
        setStyle(.{.FgYellow});
        std.debug.print("{s}", .{left.in(context.text)});
        setStyle(.{.Bold});
        std.debug.print("{s}", .{span.in(context.text)});
        setStyle(.{ .Reset, .FgYellow });
        std.debug.print("{s}", .{right.in(context.text)});
        std.debug.print("\n", .{});

        setStyle(.{ .Reset, .FgRed });
        std.debug.print(indent ** 2, .{});
        for (0..left.length) |_| {
            std.debug.print(" ", .{});
        }
        for (0..span.length) |_| {
            std.debug.print("^", .{});
        }
        std.debug.print("\n", .{});
        setStyle(.{.Reset});
    }
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
