const Self = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const assert = std.debug.assert;
const unicode = std.unicode;

pub const FreeSpan = @import("FreeSpan.zig");
pub const SourceSpan = @import("SourceSpan.zig");
const FileText = @import("FileText.zig");

files: FileText,
input: ArrayList(u8),
/// Used for all allocations within this container.
allocator: Allocator,

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
        .files = FileText.init(),
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

/// Adds `'\n'` after line.
/// Returned span references appended line, *NOT* including `'\n'`.
pub fn appendInput(
    self: *Self,
    string: []const u8,
) Allocator.Error!SourceSpan {
    const start = self.input.items.len;
    try self.input.appendSlice(self.allocator, string);
    const end = self.input.items.len;
    try self.input.append(self.allocator, '\n');

    return SourceSpan.fromBounds(start, end, .{ .input = {} });
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

pub fn getSourcePath(self: *const Self, source: Source) ?[]const u8 {
    return switch (source) {
        .file => |index| self.files.get(index).path,
        .input => null,
    };
}

pub fn startingLineOf(self: *const Self, span: SourceSpan) usize {
    const text = self.getSourceText(span.source);
    assert(span.free.end() < text.len);

    var line: usize = 1;
    for (text, 0..) |char, i| {
        if (char == '\n') {
            line += 1;
        }
        if (i >= span.free.offset) {
            break;
        }
    }
    return line;
}

/// Assumes valid UTF-8.
pub fn charCount(self: *const Self, span: SourceSpan) usize {
    return unicode.utf8CountCodepoints(span.in(self)) catch {
        std.debug.panic("string is not valid UTF-8", .{});
    };
}

pub fn isMultiline(self: *const Self, span: SourceSpan) bool {
    const text = self.getSourceText(span.source);
    assert(span.free.end() < text.len);

    for (span.free.offset..span.free.end()) |i| {
        if (text[i] == '\n') {
            return true;
        }
    }
    return false;
}

pub fn getSingleLine(
    self: *const Self,
    index: usize,
    source: Source,
) SourceSpan {
    return self.getLeftCharacters(index, source)
        .join(self.getRightCharacters(index, source));
}

pub fn getLeftCharacters(
    self: *const Self,
    index: usize,
    source: Source,
) SourceSpan {
    const text = self.getSourceText(source);
    assert(index < text.len);

    var start = index;
    while (start > 0) : (start -= 1) {
        if (text[start - 1] == '\n') {
            break;
        }
    }
    while (start < index) : (start += 1) {
        if (!std.ascii.isWhitespace(text[start])) {
            break;
        }
    }

    return SourceSpan.fromBounds(start, index, source);
}

pub fn getRightCharacters(
    self: *const Self,
    index: usize,
    source: Source,
) SourceSpan {
    const text = self.getSourceText(source);
    assert(index < text.len);

    var end = index;
    while (end < text.len) : (end += 1) {
        if (text[end] == '\n') {
            break;
        }
    }
    while (end > index) : (end -= 1) {
        if (!std.ascii.isWhitespace(text[end - 1])) {
            break;
        }
    }

    return SourceSpan.fromBounds(index, end, source);
}
