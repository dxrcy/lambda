const Self = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const assert = std.debug.assert;

const TextStore = @import("TextStore.zig");
const FreeSpan = TextStore.FreeSpan;

entries: ArrayList(Entry),
text: ArrayList(u8),

const Entry = struct {
    /// Used for reporting errors.
    /// Lifetime must exceed that of `FilesText` instance.
    path: []const u8,
    /// Do NOT use slice, since address of text can change.
    span: FreeSpan,
};

pub fn init() Self {
    return Self{
        .entries = ArrayList(Entry).empty,
        .text = ArrayList(u8).empty,
    };
}

pub fn deinit(self: *Self, allocator: Allocator) void {
    self.entries.deinit(allocator);
    self.text.deinit(allocator);
}

pub fn get(self: *const Self, index: usize) *const Entry {
    assert(index < self.entries.items.len);
    return &self.entries.items[index];
}

pub fn append(
    self: *Self,
    path: []const u8,
    string: []const u8,
    allocator: Allocator,
) Allocator.Error!usize {
    const start = self.text.items.len;
    try self.text.appendSlice(allocator, string);
    const end = self.text.items.len;

    const index = self.entries.items.len;
    try self.entries.append(allocator, .{
        .path = path,
        .span = FreeSpan.fromBounds(start, end),
    });

    return index;
}
