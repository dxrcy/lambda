const std = @import("std");

const Span = @import("Span.zig");

var count: usize = 0;

pub fn isEmpty() bool {
    return count == 0;
}

pub fn report(comptime format: []const u8, args: anytype, span: Span, text: []const u8) void {
    count += 1;

    std.debug.print("Error: ", .{});
    std.debug.print(format, args);
    std.debug.print(".\n", .{});

    std.debug.print("\"{s}\"\n", .{span.in(text)});
}
