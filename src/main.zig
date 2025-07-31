const std = @import("std");
const fs = std.fs;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const Statements = @import("Statements.zig");
const Lexer = @import("Lexer.zig");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const filepath = "example";

    const text = try readFile(filepath, allocator);
    defer text.deinit();

    var stmts = Statements.new(text.items);
    var i: usize = 0;
    while (stmts.next()) |stmt| {
        var tokens = Lexer.new(text.items, stmt);
        while (tokens.next()) |token| {
            while (i < text.items.len) : (i += 1) {
                if (i >= token.offset) {
                    i += token.length;
                    break;
                }
                std.debug.print("{c}", .{text.items[i]});
            }
            std.debug.print("\x1b[3{}m", .{i % 6 + 1});
            std.debug.print("{s}", .{token.in(text.items)});
            std.debug.print("\x1b[0m", .{});
        }
    }
    std.debug.print("\n", .{});
}

const Tokenizer = struct {
    const Self = @This();

    text: []const u8,
    index: usize,

    pub fn new(text: []const u8) Self {
        return .{
            .text = text,
            .index = 0,
        };
    }

    pub fn next(self: *Self) ?[]const u8 {
        self.advanceUntilNonwhitespace();
        if (self.isEmpty()) {
            return null;
        }

        const start = self.index;
        while (self.peekChar()) |char| {
            if (isAnyWhitespace(char)) {
                break;
            }
            self.index += 1;
        }

        return self.text[start..self.index];
    }

    fn advanceUntilNonwhitespace(self: *Self) void {
        while (self.peekChar()) |char| {
            if (!isAnyWhitespace(char)) {
                break;
            }
            self.index += 1;
        }
    }

    fn peekChar(self: *const Self) ?u8 {
        if (self.isEmpty()) {
            return null;
        }
        return self.text[self.index];
    }

    fn isEmpty(self: *const Self) bool {
        return self.index >= self.text.len;
    }

    fn isAnyWhitespace(char: u8) bool {
        return switch (char) {
            ' ', '\t'...'\r' => true,
            else => false,
        };
    }
};

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
