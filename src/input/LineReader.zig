const Self = @This();

const std = @import("std");
const assert = std.debug.assert;

const TextStore = @import("../text/TextStore.zig");
const SourceSpan = TextStore.SourceSpan;

const output = @import("../output.zig");

const LineView = @import("LineView.zig");
const StdinReader = @import("StdinReader.zig");
const StdinTerminal = @import("StdinTerminal.zig");

pub const NewError = StdinTerminal.Error;
pub const ReadError = StdinTerminal.Error || StdinReader.Error;

const PROMPT = "?- ";

// TODO: Rename
view: LineView,
reader: StdinReader,
terminal: StdinTerminal,

pub fn new(text: *const TextStore) StdinTerminal.Error!Self {
    return Self{
        .view = LineView.new(text),
        .reader = StdinReader.new(),
        .terminal = try StdinTerminal.get(),
    };
}

/// Returns slice of underlying buffer, which may be overridden on next
/// read call.
pub fn getLine(self: *const Self) []const u8 {
    return std.mem.trim(u8, self.view.get(), " ");
}

/// Use persistant `Span` to keep valid reference after buffer is overwritten.
pub fn appendHistory(self: *Self, span: SourceSpan) void {
    const value = span.in(self.view.text);
    if (value.len == 0) {
        return;
    }
    if (self.view.getLatestHistory()) |latest| {
        if (std.mem.eql(u8, latest, value)) {
            return;
        }
    }
    self.view.history.append(span);
}

/// Returns `false` iff **EOF** was reached *at any point* before input was
/// confirmed (eg. by `Return` key).
/// Note that a non-terminal stdin reader may implement different behaviour.
pub fn readLine(self: *Self) ReadError!bool {
    if (self.reader.eof) {
        return false;
    }
    try self.terminal.enableInputMode();
    try self.readLineInner();
    try self.terminal.disableInputMode();
    return !self.reader.eof;
}

// Assumes `self.terminal` has input mode enabled.
// Assumes `self.reader.eof` is `false`.
fn readLineInner(self: *Self) StdinReader.Error!void {
    assert(!self.reader.eof);

    self.view.clear();

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

/// Returns `false` if there are still characters to read in the current line,
/// ie. **EOF** has not yet been reached, and input has not yet been confirmed
/// (eg. by `Return` key).
fn readNextSequence(self: *Self) StdinReader.Error!bool {
    const byte = try self.reader.readSingleByte() orelse
        return true;

    switch (byte) {
        '\n' => {
            self.view.becomeLive();
            return true;
        },
        // Normal character
        0x20...0x7e => {
            self.view.insert(byte);
        },
        // Backspace, delete
        // FIXME: `Delete` key inserts `~`
        0x08, 0x7f => {
            self.view.remove();
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
                'A' => self.view.historyBack(),
                'B' => self.view.historyForward(),
                'C' => self.view.seek(.right),
                'D' => self.view.seek(.left),
                else => {},
            }
        },
        else => {
            // TODO: Support unicode characters
            if (byte > 0x7f) {
                self.view.insert('#');
            }
        },
    }

    return false;
}
