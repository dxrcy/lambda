const std = @import("std");

const Context = @import("Context.zig");
const Span = @import("Span.zig");

var count: usize = 0;

pub fn isEmpty() bool {
    return count == 0;
}

pub fn report(comptime format: []const u8, args: anytype, span: Span, context: *const Context) void {
    count += 1;

    std.debug.print("Error: ", .{});
    std.debug.print(format, args);
    std.debug.print(".\n", .{});

    std.debug.print("\tin \"{s}\", line {}\n", .{ context.filepath, context.startingLineOf(span) });
    std.debug.print("\t\"{s}\"\n", .{span.in(context.text)});
}
