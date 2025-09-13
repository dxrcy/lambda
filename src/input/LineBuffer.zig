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
