const Self = @This();

const std = @import("std");
const assert = std.debug.assert;

const Utf8Error = error{Utf8Error};

value: u32,
length: u2,

pub fn fromSliceStart(bytes: []const u8) Utf8Error!Self {
    assert(bytes.len > 0);
    unreachable;
}

pub fn fromByte(byte: u8) Utf8Error!Self {
    _ = byte;
    unreachable;
}
