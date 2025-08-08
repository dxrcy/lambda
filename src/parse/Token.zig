const Self = @This();
const std = @import("std");
const Span = @import("../Span.zig");

span: Span,
kind: Kind,

pub fn new(text: []const u8, span: Span) Self {
    return .{
        .span = span,
        .kind = Kind.from(span.in(text)),
    };
}

pub const Kind = enum {
    Backslash,
    Dot,
    Equals,
    ParenLeft,
    ParenRight,
    Ident,
    Invalid,

    pub fn from(slice: []const u8) Kind {
        const Candidate = struct { []const u8, Kind };
        const KEYWORDS = [_]Candidate{
            .{ "\\", .Backslash },
            .{ ".", .Dot },
            .{ "=", .Equals },
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
            .Equals => "`=`",
            .ParenLeft => "`(`",
            .ParenRight => "`)`",
            .Ident => "<identifier>",
            .Invalid => "<invalid token>",
        };
    }
};
