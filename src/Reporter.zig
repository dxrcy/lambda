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

    std.debug.print("Error: ", .{});
    std.debug.print(format, args);
    std.debug.print(".\n", .{});

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
    std.debug.print(indent ** 1 ++ "({s}:{}) {s}:\n", .{
        context.filepath,
        context.startingLineOf(span),
        label,
    });
    // TODO(feat): Print entire line and highlight span
    std.debug.print(indent ** 2 ++ "\"{s}\"\n", .{
        span.in(context.text),
    });
}
