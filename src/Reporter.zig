const std = @import("std");
const io = std.io;
const assert = std.debug.assert;

const Context = @import("Context.zig");
const Span = @import("Span.zig");

var accumulated_count: usize = 0;

/// Call `flush` at the end of public functions.
pub const Output = struct {
    const BUFFER_SIZE = 4096;

    var writer = std.fs.File.stderr().writer(&buffer);
    var buffer: [BUFFER_SIZE]u8 = undefined;

    fn print(comptime format: []const u8, args: anytype) void {
        writer.interface.print(format, args) catch |err| {
            std.debug.panic("failed to write to buffered stderr: {}", .{err});
        };
    }

    pub fn flush() void {
        writer.interface.flush() catch |err| {
            std.debug.panic("failed to flush buffered stderr: {}", .{err});
        };
    }
};

pub const Layout = union(enum) {
    file: *const Context,
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

pub fn getCount() usize {
    return accumulated_count;
}
pub fn clearCount() void {
    accumulated_count = 0;
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
) void {
    accumulated_count += 1;
    printErrorHeading(kind);
    printErrorDescription(description, args);

    defer Output.flush();

    switch (layout) {
        .file => |context| {
            printLabel("bytes in file", null, context);
        },
        .token => |token| {
            printSpan("token", token);
        },
        .statement => |stmt| {
            printSpan("statement", stmt);
        },
        .statement_end => |stmt| {
            printSpan("end of statement", Span.new(stmt.end(), 0, stmt.context));
            printSpan("statement", stmt);
        },
        .statement_token => |value| {
            printSpan("token", value.token);
            printSpan("statement", value.statement);
        },
        .symbol_reference => |value| {
            printSpan("initial declaration", value.declaration);
            printSpan("redeclaration", value.reference);
        },
        .query => |query| {
            printSpan("query", query);
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

fn printLabel(comptime label: []const u8, span: ?Span, context: *const Context) void {
    setStyle(.{ .FgWhite, .Dim });
    printIndent(1);

    Output.print("({s}:", .{context.filepath orelse ""});
    if (span) |span_unwrapped| {
        Output.print("{}", .{Context.startingLineOf(span_unwrapped)});
    }
    Output.print(") {s}\n", .{label});

    setStyle(.{.Reset});
}

fn printSpan(comptime label: []const u8, span: Span) void {
    printLabel(label, span, span.context);

    if (span.length == 0) {
        const line = span.context.getSingleLine(span.offset);
        printLineParts(line, Span.new(line.end(), 0, line.context));
        printLineHighlight(line, Span.new(line.end(), 1, line.context));
    } else if (!Context.isMultiline(span)) {
        const left = span.context.getLeftCharacters(span.offset);
        const right = span.context.getRightCharacters(span.end());
        printLineParts(left, right);
        printLineHighlight(left, span);
    } else {
        // TODO(feat): Properly handle multi line tokens/statements
        const border_length = 20;
        setStyle(.{ .Dim, .FgWhite });
        Output.print("~" ** border_length ++ "\n", .{});
        setStyle(.{ .Reset, .FgYellow });
        Output.print("{s}\n", .{span.string()});
        setStyle(.{ .Dim, .FgWhite });
        Output.print("~" ** border_length ++ "\n\n", .{});
        setStyle(.{.Reset});
    }
}

fn printLineParts(left: Span, right: Span) void {
    assert(left.context == right.context);
    assert(left.end() <= right.offset);

    printIndent(2);
    setStyle(.{.FgYellow});
    Output.print("{s}", .{left.string()});
    setStyle(.{.Bold});
    Output.print("{s}", .{Span.between(left, right).string()});
    setStyle(.{ .Reset, .FgYellow });
    Output.print("{s}", .{right.string()});
    setStyle(.{.Reset});
    Output.print("\n", .{});
}

fn printLineHighlight(left: Span, span: Span) void {
    assert(left.end() <= span.offset);

    setStyle(.{ .Reset, .FgRed });
    printIndent(2);
    for (0..Context.charCount(left)) |_| {
        Output.print(" ", .{});
    }
    for (0..Context.charCount(span)) |_| {
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
