const Self = @This();

offset: usize,
length: usize,

pub fn new(offset: usize, length: usize) Self {
    return .{
        .offset = offset,
        .length = length,
    };
}

pub fn fromBounds(start: usize, end: usize) Self {
    return .{
        .offset = start,
        .length = end - start,
    };
}

pub fn withOffset(self: Self, offset: usize) Self {
    return .{
        .offset = self.offset + offset,
        .length = self.length,
    };
}

pub fn in(self: *const Self, text: []const u8) []const u8 {
    return text[self.offset..][0..self.length];
}
