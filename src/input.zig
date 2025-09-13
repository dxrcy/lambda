const std = @import("std");
const fs = std.fs;
const posix = std.posix;

pub const LineReader = struct {
    const Self = @This();
    const FILE_BUFFER_SIZE = 1024;
    const LINE_BUFFER_SIZE = 1024;

    stdin: fs.File,
    stdin_buffer: [FILE_BUFFER_SIZE]u8,
    reader: fs.File.Reader,

    terminal: StdinTerminal,

    line_buffer: [LINE_BUFFER_SIZE]u8,
    length: usize,
    cursor: usize,

    /// Should *not* be unset, once set.
    eof: bool,

    pub fn new() !Self {
        var self = Self{
            .stdin = fs.File.stdin(),
            .reader = undefined,
            .stdin_buffer = undefined,

            .terminal = try StdinTerminal.get(),

            .line_buffer = undefined,
            .length = 0,
            .cursor = 0,

            .eof = false,
        };
        self.reader = self.stdin.reader(&self.stdin_buffer);
        return self;
    }

    /// Returns slice of underlying buffer, which may be overridden on next
    /// read call.
    pub fn getLine(self: *Self) []const u8 {
        return self.line_buffer[0..self.length];
    }

    /// Returns `false` iff **EOF** (iff `self.eof`).
    pub fn readLine(self: *Self) !bool {
        if (self.eof) {
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
        self.length = 0;
        self.cursor = 0;

        while (true) {
            {
                std.debug.print("\r\x1b[K", .{});
                std.debug.print("?- ", .{});
                std.debug.print("{s}", .{self.getLine()});
            }

            const byte = try self.readSingleByte() orelse
                break;

            switch (byte) {
                '\n' => {
                    break;
                },
                // Normal character
                0x20...0x7e => {
                    if (self.cursor < self.length) {
                        // TODO: Insert byte at cursor position
                        // Allow succeeding bytes to be cut off if length>size
                        continue;
                    }
                    if (self.cursor < LINE_BUFFER_SIZE) {
                        self.line_buffer[self.cursor] = byte;
                        self.length += 1;
                        self.cursor += 1;
                    }
                },
                // Backspace, delete
                0x08, 0x7f => {
                    // TODO: Delete at cursor position
                    if (self.length > 0 and self.cursor > 0) {
                        self.length -= 1;
                        self.cursor -= 1;
                    }
                },
                // ESC
                0x1b => {
                    if (try self.readSingleByte() != '[') {
                        continue;
                    }
                    switch (try self.readSingleByte() orelse continue) {
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
                },
                else => {},
            }
        }

        std.debug.print("\n", .{});
    }

    /// Returns `null` and sets `self.eof` iff **EOF**.
    fn readSingleByte(self: *Self) !?u8 {
        var bytes: [1]u8 = undefined;

        while (true) {
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
};

const StdinTerminal = struct {
    const Self = @This();
    const FILENO = posix.STDIN_FILENO;

    /// `null` if stdin is not a terminal.
    /// If `null`, all member functions are no-ops.
    termios: ?posix.termios,

    pub fn get() !Self {
        const termios = posix.tcgetattr(FILENO) catch |err| switch (err) {
            error.NotATerminal => null,
            else => |other_err| return other_err,
        };
        return Self{ .termios = termios };
    }

    /// Disable buffering and echo.
    pub fn enableInputMode(self: *Self) !void {
        if (self.termios) |*termios| {
            termios.lflag.ICANON = false;
            termios.lflag.ECHO = false;
            try setAttr(termios);
        }
    }

    /// Reverses `enableInputMode`.
    pub fn disableInputMode(self: *Self) !void {
        if (self.termios) |*termios| {
            termios.lflag.ICANON = true;
            termios.lflag.ECHO = true;
            try setAttr(termios);
        }
    }

    /// Assumes `termios` is a terminal; does not catch `error.NotATerminal`.
    fn setAttr(termios: *posix.termios) !void {
        posix.tcsetattr(FILENO, .NOW, termios.*) catch |err| switch (err) {
            error.NotATerminal => unreachable,
            else => |other_err| return other_err,
        };
    }
};
