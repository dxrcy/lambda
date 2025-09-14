const Self = @This();

const std = @import("std");
const assert = std.debug.assert;

const LineBuffer = @import("LineBuffer.zig");
const History = @import("History.zig");

live: LineBuffer,
// TODO: Integrate history into this struct
history: History,
is_live: bool,
cursor: usize,

pub fn new() Self {
    return Self{
        .live = LineBuffer.new(),
        .history = History.new(),
        .cursor = 0,
        .is_live = true,
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
    if (self.is_live) {
        return self.live.get();
    } else {
        return self.history.getActive();
    }
}

pub fn becomeLive(self: *Self) void {
    if (self.is_live) {
        return;
    }

    self.live.copyFrom(self.history.getActive());
    self.is_live = true;
    self.resetCursor();
}

pub fn historyBack(self: *Self) void {
    if (self.history.length == 0) {
        return;
    }

    if (self.is_live) {
        self.is_live = false;
        self.history.index = self.history.length - 1;
    } else {
        self.history.index -|= 1;
    }
    self.resetCursor();
}

pub fn historyForward(self: *Self) void {
    if (self.is_live) {
        return;
    }

    if (self.history.index + 1 >= self.history.length) {
        self.is_live = true;
    } else {
        self.history.index += 1;
    }
    self.resetCursor();
}
