const Self = @This();
const std = @import("std");

const Span = @import("../Span.zig");

span: Span,
kind: Kind,

pub fn new(span: Span) Self {
    return .{
        .span = span,
        .kind = Kind.from(span.string()),
    };
}

pub const Kind = enum {
    // TODO: Rename variants
    Backslash,
    Dot,
    Equals,
    Inspect,
    ParenLeft,
    ParenRight,
    Ident,

    pub fn from(slice: []const u8) Kind {
        const Candidate = struct { []const u8, Kind };
        const KEYWORDS = [_]Candidate{
            .{ "\\", .Backslash },
            .{ ".", .Dot },
            .{ ":=", .Equals },
            .{ ":", .Inspect },
            .{ "(", .ParenLeft },
            .{ ")", .ParenRight },
        };
        for (KEYWORDS) |symbol| {
            if (std.mem.eql(u8, symbol[0], slice)) {
                return symbol[1];
            }
        }
        return .Ident;
    }

    pub fn display(self: Kind) []const u8 {
        return switch (self) {
            .Backslash => "`\\`",
            .Dot => "`.`",
            .Equals => "`:=`",
            .Inspect => "`:`",
            .ParenLeft => "`(`",
            .ParenRight => "`)`",
            .Ident => "<identifier>",
        };
    }
};
