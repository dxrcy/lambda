const std = @import("std");
const fs = std.fs;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const Statements = @import("Statements.zig");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const filepath = "example";

    const text = try readFile(filepath, allocator);
    defer text.deinit();

    var stmts = Statements.new(text.items);
    while (stmts.next()) |stmt| {
        std.debug.print("----------\n{s}\n", .{stmt});
    }
    std.debug.print("----------\n", .{});
}

const String = ArrayList(u8);

fn readFile(path: []const u8, allocator: Allocator) !String {
    const BUFFER_SIZE = 1024;

    const file = try fs.cwd().openFile(path, .{});
    defer file.close();

    const reader = file.reader();
    var buf: [BUFFER_SIZE]u8 = undefined;

    var string = String.init(allocator);
    while (true) {
        const bytes_read = try reader.read(&buf);
        if (bytes_read == 0) {
            break;
        }
        try string.appendSlice(buf[0..bytes_read]);
    }
    return string;
}
