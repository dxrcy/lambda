const Self = @This();
const std = @import("std");

const Context = @import("../Context.zig");
const Span = @import("../Span.zig");

span: Span,
kind: Kind,

pub fn new(span: Span, context: *const Context) Self {
    return .{
        .span = span,
        .kind = Kind.from(span.in(context)),
    };
}

pub const Kind = enum {
    Backslash,
    Dot,
    Equals,
    ParenLeft,
    ParenRight,
    Query,
    Ident,

    pub fn from(slice: []const u8) Kind {
        const Candidate = struct { []const u8, Kind };
        const KEYWORDS = [_]Candidate{
            .{ "\\", .Backslash },
            .{ ".", .Dot },
            .{ ":=", .Equals },
            .{ "(", .ParenLeft },
            .{ ")", .ParenRight },
            .{ "?", .Query },
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
            .ParenLeft => "`(`",
            .ParenRight => "`)`",
            .Query => "`?`",
            .Ident => "<identifier>",
        };
    }
};
