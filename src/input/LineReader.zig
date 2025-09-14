const Self = @This();

const std = @import("std");
const assert = std.debug.assert;

const Span = @import("../Span.zig");
const output = @import("../output.zig");

const History = @import("History.zig");
const StdinReader = @import("StdinReader.zig");
const StdinTerminal = @import("StdinTerminal.zig");
const LineBuffer = @import("LineBuffer.zig");
const LineView = @import("LineView.zig");

pub const NewError = StdinTerminal.Error;
pub const ReadError = StdinTerminal.Error || StdinReader.Error;

const MAX_LINE_LENGTH = 1024;
const PROMPT = "?- ";

reader: StdinReader,
terminal: StdinTerminal,

line: LineBuffer,
view: LineView,
/// `history.index` is irrelevant if `view.isBuffer()`.
history: History,

pub fn new() StdinTerminal.Error!Self {
    var self = Self{
        .reader = StdinReader.new(),
        .terminal = try StdinTerminal.get(),

        .line = LineBuffer.new(),
        .view = undefined,
        .history = History.new(),
    };
    self.view = LineView.fromBuffer(&self.line);
    return self;
}

/// Returns `false` iff **EOF**.
pub fn readLine(self: *Self) ReadError!bool {
    if (self.reader.eof) {
        return false;
    }
    try self.terminal.enableInputMode();
    try self.readLineInner();
    try self.terminal.disableInputMode();
    return true;
}

/// Returns slice of underlying buffer, which may be overridden on next
/// read call.
pub fn getLine(self: *const Self) []const u8 {
    return std.mem.trim(u8, self.view.get(), " ");
}

/// Use persistant `Span` to keep valid reference after buffer is overwritten.
pub fn appendHistory(self: *Self, span: Span) void {
    if (span.string().len == 0) {
        return;
    }
    if (self.history.getLatest()) |latest| {
        if (std.mem.eql(u8, latest, span.string())) {
            return;
        }
    }
    self.history.append(span);
}

// Assumes `self.terminal` has input mode enabled.
// Assumes `self.eof` is `false`.
fn readLineInner(self: *Self) StdinReader.Error!void {
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
    output.print("\r\x1b[K", .{});
    output.print(PROMPT, .{});
    output.print("{s}", .{self.view.get()});
    output.print("\x1b[{}G", .{self.view.cursor + PROMPT.len + 1});
}

fn printEnd(_: *const Self) void {
    output.print("\n", .{});
}

/// Returns `true` if **EOF** *or* **EOL**, or `false` if there are still
/// characters to read in the current line.
fn readNextSequence(self: *Self) StdinReader.Error!bool {
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
            self.history.length -| 1
        else
            self.history.index -| 1;

    self.view = LineView.fromSlice(self.history.getActive());
}

fn nextHistory(self: *Self) void {
    if (self.view.isBuffer()) {
        return;
    }

    // Last item, switch to buffer
    if (self.history.index + 1 >= self.history.length) {
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
