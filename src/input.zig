const std = @import("std");
const fs = std.fs;
const posix = std.posix;

// TODO: Add explicit error variants to return types

const LineBuffer = struct {
    const Self = @This();
    const MAX_LENGTH = 1024;

    buffer: [MAX_LENGTH]u8,
    length: usize,
    cursor: usize,

    pub fn new() Self {
        return Self{
            .buffer = undefined,
            .length = 0,
            .cursor = 0,
        };
    }

    pub fn get(self: *const Self) []const u8 {
        return self.buffer[0..self.length];
    }

    pub fn clear(self: *Self) void {
        self.length = 0;
        self.cursor = 0;
    }

    pub fn insert(self: *Self, byte: u8) void {
        if (self.cursor < self.length) {
            // TODO: Insert byte at cursor position
            // Allow succeeding bytes to be cut off if length>size
            return;
        }
        if (self.cursor < MAX_LENGTH) {
            self.buffer[self.cursor] = byte;
            self.length += 1;
            self.cursor += 1;
        }
    }

    pub fn remove(self: *Self) void {
        // TODO: Delete at cursor position
        if (self.length > 0 and self.cursor > 0) {
            self.length -= 1;
            self.cursor -= 1;
        }
    }

    // TODO: Move cursor left/right
};

pub const LineReader = struct {
    const Self = @This();
    const MAX_LINE_LENGTH = 1024;

    reader: StdinReader,
    terminal: StdinTerminal,
    line: LineBuffer,
    /// Should *not* be unset, once set.
    // TODO: Move to another struct?
    eof: bool,

    pub fn new() !Self {
        return Self{
            .reader = StdinReader.new(),
            .terminal = try StdinTerminal.get(),
            .line = LineBuffer.new(),
            .eof = false,
        };
    }

    /// Returns slice of underlying buffer, which may be overridden on next
    /// read call.
    pub fn getLine(self: *const Self) []const u8 {
        return self.line.get();
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
        self.line.clear();

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
        const byte = try self.readSingleByte() orelse
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
            0x08, 0x7f => {
                self.line.remove();
                return false;
            },
            // ESC
            0x1b => {
                if (try self.readSingleByte() != '[') {
                    return true;
                }
                const command = try self.readSingleByte() orelse
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

    /// Returns `null` and sets `self.eof` iff **EOF**.
    fn readSingleByte(self: *Self) !?u8 {
        return try self.reader.readSingleByte() orelse {
            self.eof = true;
            return null;
        };
    }
};

const StdinReader = struct {
    const Self = @This();
    const BUFFER_SIZE = 1024;

    stdin: fs.File,
    reader: fs.File.Reader,
    buffer: [BUFFER_SIZE]u8,

    pub fn new() Self {
        var self = Self{
            .stdin = fs.File.stdin(),
            .reader = undefined,
            .buffer = undefined,
        };
        self.reader = self.stdin.reader(&self.buffer);
        return self;
    }

    /// Returns `null` iff **EOF**.
    fn readSingleByte(self: *Self) !?u8 {
        var bytes: [1]u8 = undefined;

        while (true) {
            const bytes_read = self.reader.read(&bytes) catch |err|
                switch (err) {
                    error.EndOfStream => {
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
