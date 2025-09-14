const Self = @This();

const std = @import("std");
const assert = std.debug.assert;

const HistoryList = @import("HistoryList.zig");
const LineBuffer = @import("LineBuffer.zig");

live: LineBuffer,
history: HistoryList,

/// `null` if `live` input is currently active.
/// Higher number means a more recent history entry.
// TODO: Invert direction
// TODO: Rename
history_index: ?usize,
/// Horizontal cursor position (byte index).
cursor: usize,

pub fn new() Self {
    return Self{
        .live = LineBuffer.new(),
        .history = HistoryList.new(),
        .history_index = null,
        .cursor = 0,
    };
}

pub fn seek(self: *Self, direction: enum { left, right }) void {
    switch (direction) {
        .left => if (self.cursor > 0) {
            self.cursor -= 1;
        },
        .right => if (self.cursor < self.get().len) {
            self.cursor += 1;
        },
    }
}

pub fn seekTo(self: *Self, position: usize) void {
    assert(position <= self.get().len);
    self.cursor = position;
}

fn resetCursor(self: *Self) void {
    self.cursor = self.get().len;
}

pub fn clear(self: *Self) void {
    self.becomeLive();
    self.live.clear();
    self.cursor = 0;
}

pub fn insert(self: *Self, byte: u8) void {
    self.becomeLive();
    if (self.live.insert(byte, self.cursor)) {
        self.cursor += 1;
    }
}

pub fn remove(self: *Self) void {
    self.becomeLive();
    self.live.remove(self.cursor);
    self.cursor -|= 1;
}

pub fn get(self: *const Self) []const u8 {
    if (self.history_index) |index| {
        return self.history.get(index);
    } else {
        return self.live.get();
    }
}

pub fn becomeLive(self: *Self) void {
    const index = self.history_index orelse
        return;

    self.live.copyFrom(self.history.get(index));
    self.history_index = null;
    self.resetCursor();
}

pub fn historyBack(self: *Self) void {
    if (self.history.length == 0) {
        return;
    }

    if (self.history_index) |*index| {
        index.* -|= 1;
    } else {
        self.history_index = self.history.length - 1;
    }
    self.resetCursor();
}

pub fn historyForward(self: *Self) void {
    const index = &(self.history_index orelse
        return);

    if (index.* + 1 >= self.history.length) {
        self.history_index = null;
    } else {
        index.* += 1;
    }
    self.resetCursor();
}

pub fn getLatestHistory(self: *const Self) ?[]const u8 {
    const index = self.history_index orelse
        return null;
    return self.history.get(index);
}
