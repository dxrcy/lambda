const Self = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const assert = std.debug.assert;

const History = @import("History.zig");
const StdinReader = @import("StdinReader.zig");
const StdinTerminal = @import("StdinTerminal.zig");
const LineBuffer = @import("LineBuffer.zig");
const LineView = @import("LineView.zig");

const Span = @import("../Span.zig");

const MAX_LINE_LENGTH = 1024;
const PROMPT = "?- ";

reader: StdinReader,
terminal: StdinTerminal,

line: LineBuffer,
view: LineView,

/// `history.index` is irrelevant if `view.isBuffer()`.
history: History,

pub fn new(allocator: Allocator) !Self {
    var self = Self{
        .reader = StdinReader.new(),
        .terminal = try StdinTerminal.get(),

        .line = LineBuffer.new(),
        .view = undefined,

        .history = History.new(allocator),
    };
    self.view = LineView.fromBuffer(&self.line);
    return self;
}

/// Returns slice of underlying buffer, which may be overridden on next
/// read call.
pub fn getLine(self: *const Self) []const u8 {
    return self.view.get();
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

pub fn appendHistory(self: *Self, span: Span) Allocator.Error!void {
    // TODO: Check if previous item is identical
    if (span.string().len > 0) {
        try self.history.append(span);
    }
}

// Assumes `self.terminal` has input mode enabled.
// Assumes `self.eof` is `false`.
fn readLineInner(self: *Self) !void {
    self.ensureNonhistoric();
    self.view.clear();

    // TODO: Use stdout

    while (true) {
        self.printPrompt();
        if (try self.readNextSequence()) {
            break;
        }
    }

    self.printEnd();
}

fn printPrompt(self: *const Self) void {
    std.debug.print("\r\x1b[K", .{});
    std.debug.print(PROMPT, .{});
    std.debug.print("{s}", .{self.view.get()});
    std.debug.print("\x1b[{}G", .{self.view.cursor + PROMPT.len + 1});
}

fn printEnd(_: *const Self) void {
    std.debug.print("\n", .{});
}

/// Returns `true` if **EOF** *or* **EOL**, or `false` if there are still
/// characters to read in the current line.
fn readNextSequence(self: *Self) !bool {
    const byte = try self.reader.readSingleByte() orelse
        return true;

    switch (byte) {
        '\n' => {
            self.ensureNonhistoric();
            return true;
        },
        // Normal character
        0x20...0x7e => {
            self.ensureNonhistoric();
            self.view.insert(byte);
            return false;
        },
        // Backspace, delete
        // FIXME: `Delete` key inserts `~`
        0x08, 0x7f => {
            self.ensureNonhistoric();
            self.view.remove();
            return false;
        },
        // ^D (EOT/EOF)
        0x04 => {
            self.ensureNonhistoric();
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
                    self.previousHistory();
                },
                'B' => {
                    self.nextHistory();
                },
                'C' => {
                    self.view.seek(.right);
                },
                'D' => {
                    self.view.seek(.left);
                },
                else => {},
            }
            return false;
        },
        else => return false,
    }
}

fn previousHistory(self: *Self) void {
    self.history.index =
        if (self.view.isBuffer())
            self.history.items.items.len -| 1
        else
            self.history.index -| 1;

    self.view = LineView.fromSlice(self.history.getActive());
}

fn nextHistory(self: *Self) void {
    if (self.view.isBuffer()) {
        return;
    }

    // Last item, switch to buffer
    if (self.history.index + 1 >= self.history.items.items.len) {
        self.view = LineView.fromBuffer(&self.line);
        return;
    }

    self.history.index += 1;
    self.view = LineView.fromSlice(self.history.getActive());
    self.resetCursor();
}

/// If historic item is focused, copy string into current line and update view.
fn ensureNonhistoric(self: *Self) void {
    if (self.view.isBuffer()) {
        return;
    }

    self.line.copyFrom(self.history.getActive());
    self.view = LineView.fromBuffer(&self.line);
}

fn resetCursor(self: *Self) void {
    self.view.seekTo(self.getLine().len);
}
