const Self = @This();

const std = @import("std");
const io = std.io;
const assert = std.debug.assert;

const TextStore = @import("text/TextStore.zig");
const FreeSpan = TextStore.FreeSpan;
const Source = TextStore.Source;
const SourceSpan = TextStore.SourceSpan;

const ExitCode = u8;

const PROGRAM_EXIT_CODE = 1;

count: usize,

pub fn new() Self {
    return Self{
        .count = 0,
    };
}

// TODO: Use `output` module (using stderr)

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
    source: Source,
    token: SourceSpan,
    statement: SourceSpan,
    statement_end: SourceSpan,
    statement_token: struct {
        statement: SourceSpan,
        token: SourceSpan,
    },
    symbol_reference: struct {
        declaration: SourceSpan,
        reference: SourceSpan,
    },
    query: SourceSpan,
};

pub fn clear(self: *Self) void {
    self.count = 0;
}

// TODO: Rename
pub fn checkFatal(self: *Self) ?ExitCode {
    if (self.count == 0) {
        return null;
    }
    return self.reportFatal(
        "unable to continue",
        "{} errors occurred",
        .{self.count},
    );
}

pub fn reportFatal(
    self: *Self,
    comptime kind: []const u8,
    comptime description: []const u8,
    args: anytype,
) ExitCode {
    _ = self;
    printErrorHeading(kind);
    printErrorDescription(description, args);
    Output.flush();
    return PROGRAM_EXIT_CODE;
}

pub fn report(
    self: *Self,
    comptime kind: []const u8,
    comptime description: []const u8,
    args: anytype,
    layout: Layout,
    text: *const TextStore,
) void {
    self.count += 1;
    printErrorHeading(kind);
    printErrorDescription(description, args);

    defer Output.flush();

    switch (layout) {
        .source => |source| {
            if (text.getSourcePath(source) != null) {
                printSourceFileLabel("bytes in file", source, text);
            }
        },
        .token => |token| {
            printSpan("token", token, text);
        },
        .statement => |stmt| {
            printSpan("statement", stmt, text);
        },
        .statement_end => |stmt| {
            const end = SourceSpan.new(stmt.free.end(), 0, stmt.source);
            printSpan("end of statement", end, text);
            printSpan("statement", stmt, text);
        },
        .statement_token => |value| {
            printSpan("token", value.token, text);
            printSpan("statement", value.statement, text);
        },
        .symbol_reference => |value| {
            printSpan("initial declaration", value.declaration, text);
            printSpan("redeclaration", value.reference, text);
        },
        .query => |query| {
            printSpan("query", query, text);
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

fn printSourceFileLabel(
    comptime label: []const u8,
    source: Source,
    text: *const TextStore,
) void {
    const path = text.getSourcePath(source) orelse
        std.debug.panic("expected `Source.file`\n", .{});

    setStyle(.{ .FgWhite, .Dim });
    printIndent(1);
    Output.print("({s}) {s}\n", .{ path, label });
    setStyle(.{.Reset});
}

fn printSourceLineLabel(
    comptime label: []const u8,
    span: SourceSpan,
    text: *const TextStore,
) void {
    const path = text.getSourcePath(span.source) orelse "";
    const line = text.startingLineOf(span);

    setStyle(.{ .FgWhite, .Dim });
    printIndent(1);
    Output.print("({s}:{}) {s}\n", .{ path, line, label });
    setStyle(.{.Reset});
}

fn printSpan(
    comptime label: []const u8,
    span: SourceSpan,
    text: *const TextStore,
) void {
    printSourceLineLabel(label, span, text);

    if (span.free.length == 0) {
        const line = text.getSingleLine(span.free.offset, span.source);
        printLineParts(
            line,
            SourceSpan.new(line.free.end(), 0, line.source),
            text,
        );
        printLineHighlight(
            line,
            SourceSpan.new(line.free.end(), 1, line.source),
            text,
        );
    } else if (!text.isMultiline(span)) {
        const left = text.getLeftCharacters(span.free.offset, span.source);
        const right = text.getRightCharacters(span.free.end(), span.source);
        printLineParts(left, right, text);
        printLineHighlight(left, span, text);
    } else {
        // NOTE: Assumes the span contains the entire statement
        // This is fine, it works well enough right now

        setStyle(.{.FgYellow});
        var line_start = true;
        for (span.in(text)) |ch| {
            if (line_start) {
                printIndent(2);
            }
            line_start = false;
            Output.print("{c}", .{ch});
            if (ch == '\n') {
                line_start = true;
            }
        }
        Output.print("\n", .{});
        setStyle(.{.Reset});

        setStyle(.{ .Reset, .FgRed });
        printIndent(2);
        for (0..maxLineWidth(span.in(text))) |_| {
            Output.print("^", .{});
        }
        Output.print("\n", .{});
        setStyle(.{.Reset});
    }
}

fn printLineParts(
    left: SourceSpan,
    right: SourceSpan,
    text: *const TextStore,
) void {
    assert(left.source.equals(right.source));
    assert(left.free.end() <= right.free.offset);

    printIndent(2);
    setStyle(.{.FgYellow});
    Output.print("{s}", .{left.in(text)});
    setStyle(.{.Bold});
    Output.print("{s}", .{SourceSpan.between(left, right).in(text)});
    setStyle(.{ .Reset, .FgYellow });
    Output.print("{s}", .{right.in(text)});
    setStyle(.{.Reset});
    Output.print("\n", .{});
}

fn printLineHighlight(
    left: SourceSpan,
    span: SourceSpan,
    text: *const TextStore,
) void {
    assert(left.free.end() <= span.free.offset);

    setStyle(.{ .Reset, .FgRed });
    printIndent(2);
    for (0..text.charCount(left)) |_| {
        Output.print(" ", .{});
    }
    for (0..text.charCount(span)) |_| {
        Output.print("^", .{});
    }
    Output.print("\n", .{});
    setStyle(.{.Reset});
}

fn maxLineWidth(value: []const u8) usize {
    var line_width: usize = 0;
    var max: usize = 0;

    for (value) |ch| {
        if (ch == '\n') {
            line_width = 0;
            continue;
        }

        line_width += 1;
        if (line_width > max) {
            max = line_width;
        }
    }

    return max;
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
