const std = @import("std");
const fs = std.fs;
const Allocator = std.mem.Allocator;
const ArrayList = std.array_list.Managed;

const ReadFileError =
    fs.File.OpenError || std.Io.Reader.Error || Allocator.Error;

const BUFFER_SIZE = 1024;

pub fn readFile(
    path: []const u8,
    allocator: Allocator,
) ReadFileError!ArrayList(u8) {
    const file = try fs.cwd().openFile(path, .{});
    defer file.close();

    var buffer: [BUFFER_SIZE]u8 = undefined;
    var reader = file.reader(&buffer);

    var string = ArrayList(u8).init(allocator);
    while (true) {
        var bytes: [1]u8 = undefined;
        const bytes_read = reader.read(&bytes) catch |err| switch (err) {
            error.EndOfStream => break,
            else => |other_err| return other_err,
        };
        if (bytes_read == 0) {
            break;
        }
        try string.append(bytes[0]);
    }
    return string;
}
