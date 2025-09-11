const std = @import("std");
const io = std.io;
const assert = std.debug.assert;

const Context = @import("Context.zig");
const Span = @import("Span.zig");

var accumulated_count: usize = 0;

/// Call `flush` at the end of public functions.
pub const Output = struct {
    var stderr = io.bufferedWriter(io.getStdErr().writer());

    fn print(comptime format: []const u8, args: anytype) void {
        stderr.writer().print(format, args) catch |err| {
            std.debug.panic("failed to write to buffered stderr: {}", .{err});
        };
    }

    pub fn flush() void {
        stderr.flush() catch |err| {
            std.debug.panic("failed to flush buffered stderr: {}", .{err});
        };
    }
};

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
    query: Span,
};

// TODO(refactor): Rename
pub fn checkFatal() void {
    if (accumulated_count == 0) {
        return;
    }
    reportFatal(
        "unable to continue",
        "{} errors occurred",
        .{accumulated_count},
    );
}

pub fn reportFatal(
    comptime kind: []const u8,
    comptime description: []const u8,
    args: anytype,
) noreturn {
    printErrorHeading(kind);
    printErrorDescription(description, args);
    Output.flush();
    std.process.exit(1);
}

pub fn report(
    comptime kind: []const u8,
    comptime description: []const u8,
    args: anytype,
    layout: Layout,
    context: *const Context,
) void {
    accumulated_count += 1;
    printErrorHeading(kind);
    printErrorDescription(description, args);

    defer Output.flush();

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
        .query => |query| {
            printSpan("query", query, context);
        },
    }
}

fn printErrorHeading(comptime kind: []const u8) void {
    comptime assert(kind.len > 0);

    setStyle(.{ .Bold, .Underline, .FgRed });
    Output.print("Error", .{});
    setStyle(.{ .Reset, .Bold, .FgRed });
    Output.print(": ", .{});
    setStyle(.{ .Reset, .FgRed });
    Output.print(kind, .{});
    Output.print(".\n", .{});
    setStyle(.{.Reset});
}

fn printErrorDescription(comptime description: []const u8, args: anytype) void {
    if (description.len == 0) {
        return;
    }

    setStyle(.{.FgRed});
    printIndent(1);
    Output.print(description, args);
    Output.print(".\n", .{});
    setStyle(.{.Reset});
}

fn printIndent(comptime depth: usize) void {
    const INDENT = " " ** 4;
    Output.print(INDENT ** depth, .{});
}

fn printLabel(comptime format: []const u8, args: anytype) void {
    setStyle(.{ .FgWhite, .Dim });
    printIndent(1);
    Output.print(format, args);
    setStyle(.{.Reset});
}

fn printFileLabel(comptime label: []const u8, context: *const Context) void {
    printLabel("({s}) {s}\n", .{
        context.filepath,
        label,
    });
}

fn printSpan(
    comptime label: []const u8,
    span: Span,
    context: *const Context,
) void {
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
        Output.print("~" ** border_length ++ "\n", .{});
        setStyle(.{ .Reset, .FgYellow });
        Output.print("{s}\n", .{span.in(context)});
        setStyle(.{ .Dim, .FgWhite });
        Output.print("~" ** border_length ++ "\n\n", .{});
        setStyle(.{.Reset});
    }
}

fn printLineParts(left: Span, right: Span, context: *const Context) void {
    assert(left.end() <= right.offset);

    printIndent(2);
    setStyle(.{.FgYellow});
    Output.print("{s}", .{left.in(context)});
    setStyle(.{.Bold});
    Output.print("{s}", .{Span.between(left, right).in(context)});
    setStyle(.{ .Reset, .FgYellow });
    Output.print("{s}", .{right.in(context)});
    setStyle(.{.Reset});
    Output.print("\n", .{});
}

fn printLineHighlight(left: Span, span: Span, context: *const Context) void {
    assert(left.end() <= span.offset);

    setStyle(.{ .Reset, .FgRed });
    printIndent(2);
    for (0..context.charCount(left)) |_| {
        Output.print(" ", .{});
    }
    for (0..context.charCount(span)) |_| {
        Output.print("^", .{});
    }
    Output.print("\n", .{});
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
        Output.print("\x1b[{}m", .{@intFromEnum(style)});
    }
}
