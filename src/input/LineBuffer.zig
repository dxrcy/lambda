const Self = @This();

const MAX_LENGTH = 256;

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
    if (self.cursor >= MAX_LENGTH) {
        return;
    }

    // Shift characters up
    if (self.length > 0) {
        var i: usize = self.length - 1;
        while (i > self.cursor) : (i -= 1) {
            self.buffer[i] = self.buffer[i - 1];
        }
    }

    self.buffer[self.cursor] = byte;
    self.cursor += 1;
    // Cut off any overflowing characters
    if (self.length + 1 <= MAX_LENGTH) {
        self.length += 1;
    }
}

pub fn remove(self: *Self) void {
    if (self.length == 0 or self.cursor == 0) {
        return;
    }

    // Shift characters down
    if (self.cursor < self.length) {
        for (self.cursor..self.length) |i| {
            self.buffer[i - 1] = self.buffer[i];
        }
    }

    self.length -= 1;
    self.cursor -= 1;
}

pub fn seek(self: *Self, direction: enum { left, right }) void {
    switch (direction) {
        .left => {
            if (self.cursor > 0) {
                self.cursor -= 1;
            }
        },
        .right => {
            if (self.cursor < self.length) {
                self.cursor += 1;
            }
        },
    }
}
