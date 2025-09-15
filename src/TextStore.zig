const Self = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const assert = std.debug.assert;

files: FilesText,
input: ArrayList(u8),
/// Used for all allocations within this container.
allocator: Allocator,

const FilesText = struct {
    entries: ArrayList(Entry),
    text: ArrayList(u8),

    const Entry = struct {
        /// Used for reporting errors.
        /// Lifetime must exceed that of `FilesText` instance.
        path: []const u8,
        /// Do NOT use slice, since address of text can change.
        span: FreeSpan,
    };

    pub fn init() @This() {
        return @This(){
            .entries = ArrayList(Entry).empty,
            .text = ArrayList(u8).empty,
        };
    }

    pub fn deinit(self: *@This(), allocator: Allocator) void {
        self.entries.deinit(allocator);
        self.text.deinit(allocator);
    }

    pub fn get(self: *const @This(), index: usize) *const Entry {
        assert(index < self.entries.items.len);
        return &self.entries.items[index];
    }

    pub fn append(
        self: *@This(),
        path: []const u8,
        text: []const u8,
        allocator: Allocator,
    ) Allocator.Error!usize {
        const start = self.text.items.len;
        try self.text.appendSlice(allocator, text);
        const end = self.text.items.len;

        const index = self.entries.items.len;
        try self.entries.append(allocator, .{
            .path = path,
            .span = FreeSpan.fromBounds(start, end),
        });

        return index;
    }
};

// TODO: Rename
pub const FreeSpan = struct {
    offset: usize,
    length: usize,

    pub fn end(self: @This()) usize {
        return self.offset + self.length;
    }

    pub fn fromBounds(start: usize, span_end: usize) @This() {
        // FIXME: Should this be `<`?
        assert(start <= span_end);
        return .{
            .offset = start,
            .length = span_end - start,
        };
    }

    pub fn addOffset(self: @This(), offset: usize) @This() {
        return .{
            .offset = self.offset + offset,
            .length = self.length,
        };
    }

    /// Spans must be in-order and non-overlapping.
    pub fn join(left: @This(), right: @This()) @This() {
        assert(left.end() <= right.offset);
        return .{
            .offset = left.offset,
            .length = right.end() - left.offset,
        };
    }

    pub fn in(self: @This(), text: []const u8) []const u8 {
        assert(self.offset < text.len);
        assert(self.offset + self.length <= text.len);
        return text[self.offset..][0..self.length];
    }
};

// TODO: Rename
pub const SourceSpan = struct {
    source: Source,
    // TODO: Rename
    free: FreeSpan,

    pub fn end(self: @This()) usize {
        return self.free.end();
    }

    pub fn fromBounds(start: usize, span_end: usize, source: Source) @This() {
        return .{
            .source = source,
            .free = FreeSpan.fromBounds(start, span_end),
        };
    }

    pub fn addOffset(self: @This(), offset: usize) @This() {
        return .{
            .free = self.free.addOffset(offset),
            .source = self.source,
        };
    }

    /// Spans must be in-order, non-overlapping, and from the same source.
    pub fn join(left: @This(), right: @This()) @This() {
        assert(left.source.equals(right.source));
        return .{
            .free = left.free.join(right.free),
            .source = left.source,
        };
    }

    pub fn in(self: @This(), text: *const Self) []const u8 {
        return self.free.in(text.getSourceText(self.source));
    }
};

pub const Source = union(enum) {
    file: usize,
    input: void,

    pub fn equals(self: @This(), other: @This()) bool {
        switch (self) {
            .file => |index| switch (other) {
                .file => |other_index| return index == other_index,
                .input => return false,
            },
            .input => switch (other) {
                .file => return false,
                .input => return true,
            },
        }
    }
};

pub fn init(allocator: Allocator) Self {
    return Self{
        .files = FilesText.init(),
        .input = ArrayList(u8).empty,
        .allocator = allocator,
    };
}

pub fn deinit(self: *Self) void {
    self.files.deinit(self.allocator);
    self.input.deinit(self.allocator);
}

pub fn addFile(
    self: *Self,
    path: []const u8,
    text: []const u8,
) Allocator.Error!Source {
    const index = try self.files.append(path, text, self.allocator);
    return Source{ .file = index };
}

// TODO: Rename
pub fn get(self: *const Self, source: Source, index: usize) u8 {
    const text = self.getSourceText(source);
    return text[index];
}

pub fn getSourceText(self: *const Self, source: Source) []const u8 {
    return switch (source) {
        .file => |index| self.files.get(index).span.in(self.files.text.items),
        .input => self.input.items,
    };
}
