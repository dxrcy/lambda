const Self = @This();

const std = @import("std");
const assert = std.debug.assert;

const TextStore = @import("../TextStore.zig");

const HistoryList = @import("HistoryList.zig");
const LineBuffer = @import("LineBuffer.zig");

live: LineBuffer,
history: HistoryList,

/// Horizontal cursor position (byte index).
cursor: usize,
/// `null` if `live` input is currently active.
/// Lower number means a more recent history entry (`0` being the latest).
scrollback: ?usize,

text: *const TextStore,

pub fn new(text: *const TextStore) Self {
    return Self{
        .live = LineBuffer.new(),
        .history = HistoryList.new(),
        .cursor = 0,
        .scrollback = null,
        .text = text,
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
    if (self.scrollback) |scrollback| {
        return self.history.get(scrollback).in(self.text);
    } else {
        return self.live.get();
    }
}

pub fn becomeLive(self: *Self) void {
    const scrollback = self.scrollback orelse
        return;

    const historic = self.history.get(scrollback).in(self.text);
    self.live.copyFrom(historic);
    self.scrollback = null;

    self.resetCursor();
}

pub fn historyBack(self: *Self) void {
    if (self.history.length == 0) {
        return;
    }

    if (self.scrollback) |*scrollback| {
        if (scrollback.* + 1 < self.history.length) {
            scrollback.* += 1;
        }
    } else {
        self.scrollback = 0;
    }

    self.resetCursor();
}

pub fn historyForward(self: *Self) void {
    const scrollback = self.scrollback orelse
        return;

    self.scrollback =
        if (scrollback == 0)
            null
        else
            scrollback - 1;

    self.resetCursor();
}

pub fn getLatestHistory(self: *const Self) ?[]const u8 {
    const scrollback = self.scrollback orelse
        return null;
    return self.history.get(scrollback).in(self.text);
}
