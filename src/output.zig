const std = @import("std");
const fs = std.fs;

const BUFFER_SIZE = 1024;

var SINGLETON: ?Stream = null;

pub const Stream = struct {
    file: fs.File,
    writer: fs.File.Writer,
    buffer: [BUFFER_SIZE]u8,
};

pub fn init() void {
    if (SINGLETON != null) {
        std.debug.panic("tried to reinitialize output singleton", .{});
    }
    // I think it has to be done like this, due to internal references
    SINGLETON = Stream{
        .file = std.fs.File.stdout(),
        .writer = undefined,
        .buffer = undefined,
    };
    SINGLETON.?.writer = SINGLETON.?.file.writer(&SINGLETON.?.buffer);
}

pub fn print(comptime format: []const u8, args: anytype) void {
    getWriter().interface.print(format, args) catch |err| {
        std.debug.panic("failed to write output: {}", .{err});
    };
    // TODO: Obviously don't flush here...
    flush();
}

pub fn flush() void {
    getWriter().interface.flush() catch |err| {
        std.debug.panic("failed to flush output: {}", .{err});
    };
}

fn getWriter() *fs.File.Writer {
    // Maybe it's dangerous to return `writer.interface`...why risk it?
    return &(SINGLETON orelse {
        std.debug.panic(
            "tried to access output singleton before initialization",
            .{},
        );
    }).writer;
}
