const Self = @This();

const std = @import("std");

const StdinReader = @import("StdinReader.zig");
const StdinTerminal = @import("StdinTerminal.zig");
const LineBuffer = @import("LineBuffer.zig");

const MAX_LINE_LENGTH = 1024;

reader: StdinReader,
terminal: StdinTerminal,
line: LineBuffer,

pub fn new() !Self {
    return Self{
        .reader = StdinReader.new(),
        .terminal = try StdinTerminal.get(),
        .line = LineBuffer.new(),
    };
}

/// Returns slice of underlying buffer, which may be overridden on next
/// read call.
pub fn getLine(self: *const Self) []const u8 {
    return self.line.get();
}

/// Returns `false` iff **EOF** (iff `self.eof`).
pub fn readLine(self: *Self) !bool {
    if (self.reader.eof) {
        return false;
    }
    try self.terminal.enableInputMode();
    try self.readLineInner();
    try self.terminal.disableInputMode();
    return true;
}

// Assumes `self.terminal` has input mode enabled.
// Assumes `self.eof` is `false`.
fn readLineInner(self: *Self) !void {
    self.line.clear();

    // TODO: Use stdin

    while (true) {
        std.debug.print("\r\x1b[K", .{});
        std.debug.print("?- ", .{});
        std.debug.print("{s}", .{self.line.get()});

        if (try self.readNextSequence()) {
            break;
        }
    }

    std.debug.print("\n", .{});
}

/// Returns `true` if **EOF** *or* **EOL**, or `false` if there are still
/// characters to read in the current line.
fn readNextSequence(self: *Self) !bool {
    const byte = try self.reader.readSingleByte() orelse
        return true;

    switch (byte) {
        '\n' => {
            return true;
        },
        // Normal character
        0x20...0x7e => {
            self.line.insert(byte);
            return false;
        },
        // Backspace, delete
        // FIXME: `Delete` key inserts `~`
        0x08, 0x7f => {
            self.line.remove();
            return false;
        },
        // ^D (EOT/EOF)
        0x04 => {
            self.reader.setUserEof();
            return true;
        },
        // ESC
        0x1b => {
            if (try self.reader.readSingleByte() != '[') {
                return true;
            }
            const command = try self.reader.readSingleByte() orelse
                return true;
            switch (command) {
                'A' => {
                    // TODO: Go up in history
                },
                'B' => {
                    // TODO: Go down in history
                },
                'C' => {
                    // TODO: Move right in line
                },
                'D' => {
                    // TODO: Move left in line
                },
                else => {},
            }
            return false;
        },
        else => return false,
    }
}
