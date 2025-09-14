const std = @import("std");
const fs = std.fs;

var SINGLETON: ?FileWriter = null;

const FileWriter = struct {
    const BUFFER_SIZE = 1024;

    file: fs.File,
    writer: fs.File.Writer,
    buffer: [BUFFER_SIZE]u8,
};

pub fn init() void {
    if (SINGLETON != null) {
        std.debug.panic("tried to reinitialize output singleton", .{});
    }
    // I think it has to be done like this, due to internal references
    SINGLETON = FileWriter{
        .file = std.fs.File.stdout(),
        .writer = undefined,
        .buffer = undefined,
    };
    SINGLETON.?.writer = SINGLETON.?.file.writer(&SINGLETON.?.buffer);
}

fn getWriter() *std.Io.Writer {
    if (SINGLETON) |*stream| {
        return &stream.writer.interface;
    } else {
        std.debug.panic(
            "tried to access output singleton before initialization",
            .{},
        );
    }
}

pub fn print(comptime format: []const u8, args: anytype) void {
    getWriter().print(format, args) catch |err| {
        std.debug.panic("failed to write output: {}", .{err});
    };
    // TODO: Obviously don't flush here...
    flush();
}

pub fn flush() void {
    getWriter().flush() catch |err| {
        std.debug.panic("failed to flush output: {}", .{err});
    };
}
