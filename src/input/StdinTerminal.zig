const Self = @This();

const std = @import("std");
const posix = std.posix;

pub const Error = posix.UnexpectedError;

const FILENO = posix.STDIN_FILENO;

// TODO: When non-terminal stdin is properly implemented, throw if `NotATerminal`

/// `null` if stdin is not a terminal.
/// If `null`, all member functions are no-ops.
termios: ?posix.termios,

pub fn get() Error!Self {
    const termios = posix.tcgetattr(FILENO) catch |err| switch (err) {
        error.NotATerminal => null,
        else => |other_err| return other_err,
    };
    return Self{ .termios = termios };
}

/// Disable buffering and echo.
pub fn enableInputMode(self: *Self) Error!void {
    if (self.termios) |*termios| {
        termios.lflag.ICANON = false;
        termios.lflag.ECHO = false;
        try setAttr(termios);
    }
}

/// Reverses `enableInputMode`.
pub fn disableInputMode(self: *Self) Error!void {
    if (self.termios) |*termios| {
        termios.lflag.ICANON = true;
        termios.lflag.ECHO = true;
        try setAttr(termios);
    }
}

/// Assumes `termios` is a terminal; does not catch `error.NotATerminal`.
fn setAttr(termios: *posix.termios) Error!void {
    posix.tcsetattr(FILENO, .NOW, termios.*) catch |err| switch (err) {
        error.NotATerminal => unreachable,
        error.ProcessOrphaned => unreachable,
        else => |other_err| return other_err,
    };
}
