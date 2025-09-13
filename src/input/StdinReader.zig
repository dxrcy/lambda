const Self = @This();

const std = @import("std");
const fs = std.fs;

const BUFFER_SIZE = 1024;

stdin: fs.File,
reader: fs.File.Reader,
buffer: [BUFFER_SIZE]u8,
/// Should *not* be unset, once set.
eof: bool,

pub fn new() Self {
    var self = Self{
        .stdin = fs.File.stdin(),
        .reader = undefined,
        .buffer = undefined,
        .eof = false,
    };
    self.reader = self.stdin.reader(&self.buffer);
    return self;
}

/// Returns `null` and sets `self.eof` iff **EOF**.
/// If `self.eof` is `true`, no read calls will be made.
pub fn readSingleByte(self: *Self) !?u8 {
    if (self.eof) {
        return null;
    }
    while (true) {
        var bytes: [1]u8 = undefined;
        const bytes_read = self.reader.read(&bytes) catch |err|
            switch (err) {
                error.EndOfStream => {
                    self.eof = true;
                    return null;
                },
                else => |other_err| {
                    return other_err;
                },
            };

        if (bytes_read > 0) {
            return bytes[0];
        }
    }
}

/// Set `self.eof` as if a true **EOF** was reached.
pub fn setUserEof(self: *Self) void {
    self.eof = true;
}
