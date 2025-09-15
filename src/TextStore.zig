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

    pub fn fromBounds(start: usize, span_end: usize) @This() {
        // FIXME: Should this be `<`?
        assert(start <= span_end);
        return .{
            .offset = start,
            .length = span_end - start,
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

    pub fn fromBounds(start: usize, span_end: usize, source: Source) @This() {
        return .{
            .source = source,
            .free = FreeSpan.fromBounds(start, span_end),
        };
    }

    pub fn in(self: @This(), text: *const Self) []const u8 {
        return self.free.in(text.getSourceText(self.source));
    }
};

pub const Source = union(enum) {
    file: usize,
    input: void,
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
