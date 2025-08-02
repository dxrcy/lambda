const std = @import("std");
const fs = std.fs;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const ReadFileError = fs.File.OpenError || fs.File.ReadError || Allocator.Error;

const BUFFER_SIZE = 1024;

pub fn readFile(
    path: []const u8,
    allocator: Allocator,
) ReadFileError!ArrayList(u8) {
    const file = try fs.cwd().openFile(path, .{});
    defer file.close();

    const reader = file.reader();
    var buf: [BUFFER_SIZE]u8 = undefined;

    var string = ArrayList(u8).init(allocator);
    while (true) {
        const bytes_read = try reader.read(&buf);
        if (bytes_read == 0) {
            break;
        }
        try string.appendSlice(buf[0..bytes_read]);
    }
    return string;
}
