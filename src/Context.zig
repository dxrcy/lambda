const Self = @This();

const Span = @import("Span.zig");

filepath: []const u8,
text: []const u8,

pub fn startingLineOf(self: *const Self, span: Span) isize {
    if (span.offset >= self.text.len) {
        return -1;
    }

    var line: isize = 1;
    for (self.text, 0..) |char, i| {
        if (char == '\n') {
            line += 1;
        }
        if (i >= span.offset) {
            break;
        }
    }
    return line;
}
