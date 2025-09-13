const std = @import("std");
const fs = std.fs;
const posix = std.posix;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const Context = @import("Context.zig");
const Reporter = @import("Reporter.zig");
const Span = @import("Span.zig");
const utils = @import("utils.zig");

const Parser = @import("parse/Parser.zig");
const Statements = @import("parse/Statements.zig");
const Tokenizer = @import("parse/Tokenizer.zig");

const model = @import("model.zig");
const Decl = model.Decl;
const Query = model.Query;

const symbols = @import("symbols.zig");
const LocalStore = symbols.LocalStore;

const resolve = @import("resolve.zig");
const debug = @import("debug.zig");

pub fn main() !u8 {
    // pub fn main() Allocator.Error!void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = std.process.args();
    _ = args.next();

    defer Reporter.Output.flush();

    const filepath = args.next() orelse {
        return Reporter.reportFatal(
            "no filepath argument was provided",
            "",
            .{},
        );
    };

    // TODO: Include filepath in report
    var text = utils.readFile(filepath, allocator) catch |err| {
        return Reporter.reportFatal(
            "failed to read file",
            "{}",
            .{err},
        );
    };
    defer text.deinit(allocator);

    const context = Context{
        .filepath = filepath,
        .text = text.items,
    };

    if (!std.unicode.utf8ValidateSlice(context.text)) {
        // To include context filepath
        // TODO: Use `reportFatal`
        Reporter.report(
            "file contains invalid UTF-8 bytes",
            "",
            .{},
            .{ .file = &context },
        );
        if (Reporter.checkFatal()) |code|
            return code;
    }

    var decls = ArrayList(Decl).empty;
    defer decls.deinit(allocator);

    var queries = ArrayList(Query).empty;
    defer queries.deinit(allocator);

    // TODO: Separate term storage into
    // - terms in declarations
    // - temporary terms (file queries, repl queries)
    // And destroy temporaries after their use

    var term_allocator = std.heap.ArenaAllocator.init(gpa.allocator());
    defer term_allocator.deinit();

    {
        var statements = Statements.new(&context);
        while (statements.next()) |span| {
            var parser = Parser.new(span);
            const stmt = try parser.tryStatement(term_allocator.allocator()) orelse {
                continue;
            };
            switch (stmt) {
                .declaration => |decl| {
                    try decls.append(allocator, decl);
                },
                .query => |query| {
                    try queries.append(allocator, query);
                },
            }
        }
    }

    if (Reporter.checkFatal()) |code|
        return code;

    {
        symbols.checkDeclarationCollisions(decls.items);

        // PERF: Reuse all instances of local store in this function
        var locals = LocalStore.init(allocator);
        defer locals.deinit();

        for (decls.items) |*entry| {
            std.debug.assert(locals.isEmpty());
            try symbols.patchSymbols(entry.term, &locals, decls.items);
        }
        std.debug.assert(locals.isEmpty());
    }

    {
        var locals = LocalStore.init(allocator);
        defer locals.deinit();

        for (queries.items) |*query| {
            std.debug.assert(locals.isEmpty());
            try symbols.patchSymbols(query.term, &locals, decls.items);
        }
        std.debug.assert(locals.isEmpty());
    }

    if (Reporter.checkFatal()) |code|
        return code;

    // debug.printDeclarations(decls.items, &context);
    // debug.printQueries(queries.items, &context);

    // std.debug.print("Results:\n", .{});
    // std.debug.print("\n", .{});
    {
        for (queries.items) |*query| {
            const query_span = query.term.span.?;

            const result = resolve.resolveTerm(
                query.term,
                0,
                decls.items,
                term_allocator.allocator(),
            ) catch |err| switch (err) {
                error.MaxRecursion => {
                    Reporter.report(
                        "recursion limit reached when expanding query",
                        "check for any reference cycles in declarations",
                        .{},
                        .{ .query = query_span },
                    );
                    continue;
                },
                else => |other_err| return other_err,
            };

            std.debug.print("?- ", .{});
            debug.printSpanInline(query_span.string());
            std.debug.print("\n", .{});
            std.debug.print("-> ", .{});
            debug.printTermExpr(result, decls.items);
            std.debug.print("\n", .{});
            std.debug.print("\n", .{});
        }
    }

    // PERF: Don't append temporary query lines
    // Use a separate temporary string
    // This is not important at this stage

    // Storage for all stdin text (including non-persistant statements)
    var stdin_text = ArrayList(u8).empty;
    defer stdin_text.deinit(allocator);

    const BUFFER_SIZE = 4;

    const stdin = std.fs.File.stdin();

    var buffer: [BUFFER_SIZE]u8 = undefined;
    const reader = stdin.reader(&buffer);

    var stdin_context = Context{
        .filepath = null,
        .text = stdin_text.items,
    };

    const terminal = try StdinTerminal.get();

    // TODO: Create `new` method
    var line_reader = LineReader{
        .buffer = undefined,
        .length = 0,
        .cursor = 0,

        .eof = false,

        .reader = reader,
        .terminal = terminal,
    };

    while (true) {
        Reporter.clearCount();

        if (!try line_reader.readLine()) {
            break; // EOF
        }

        const text_line_start = stdin_text.items.len;
        try stdin_text.appendSlice(allocator, line_reader.getLine());

        const text_line = stdin_text.items[text_line_start..stdin_text.items.len];
        try stdin_text.append(allocator, '\n');

        // Reassign pointer and length in case of resize or relocation
        stdin_context.text = stdin_text.items;

        const line_span = Span.new(text_line_start, text_line.len, &stdin_context);

        if (!std.unicode.utf8ValidateSlice(text_line)) {
            // To include context filepath
            Reporter.report(
                "input contains invalid UTF-8 bytes",
                "",
                .{},
                .{ .stdin = {} },
            );
            continue;
        }

        var parser = Parser.new(line_span);

        const stmt = try parser.tryStatement(term_allocator.allocator()) orelse {
            continue;
        };
        switch (stmt) {
            .declaration => {
                std.debug.print("unimplemented\n", .{});
            },
            .query => |query| {
                {
                    var locals = LocalStore.init(allocator);
                    defer locals.deinit();

                    std.debug.assert(locals.isEmpty());
                    try symbols.patchSymbols(query.term, &locals, decls.items);

                    std.debug.assert(locals.isEmpty());
                }

                if (Reporter.getCount() > 0) {
                    continue;
                }

                // debug.printTermAll("Query", query.term, decls.items);

                {
                    const query_span = query.term.span.?;

                    const result = resolve.resolveTerm(
                        query.term,
                        0,
                        decls.items,
                        term_allocator.allocator(),
                    ) catch |err| switch (err) {
                        error.MaxRecursion => {
                            Reporter.report(
                                "recursion limit reached when expanding query",
                                "check for any reference cycles in declarations",
                                .{},
                                .{ .query = query_span },
                            );
                            continue;
                        },
                        else => |other_err| return other_err,
                    };

                    std.debug.print("-> ", .{});
                    debug.printTermExpr(result, decls.items);
                    std.debug.print("\n", .{});
                    std.debug.print("\n", .{});
                    // debug.printTermAll("Result", result, decls.items);
                }
            },
        }
    }

    std.debug.print("end.\n", .{});
    return 0;
}

const StdinTerminal = struct {
    const Self = @This();
    const FILENO = posix.STDIN_FILENO;

    /// `null` if stdin is not a terminal.
    /// If `null`, all member functions are no-ops.
    termios: ?posix.termios,

    pub fn get() !Self {
        const termios = posix.tcgetattr(FILENO) catch |err| switch (err) {
            error.NotATerminal => null,
            else => |other_err| return other_err,
        };
        return Self{ .termios = termios };
    }

    /// Disable buffering and echo.
    pub fn enableInputMode(self: *Self) !void {
        if (self.termios) |*termios| {
            termios.lflag.ICANON = false;
            termios.lflag.ECHO = false;
            try setAttr(termios);
        }
    }

    /// Reverses `enableInputMode`.
    pub fn disableInputMode(self: *Self) !void {
        if (self.termios) |*termios| {
            termios.lflag.ICANON = true;
            termios.lflag.ECHO = true;
            try setAttr(termios);
        }
    }

    /// Assumes `termios` is a terminal; does not catch `error.NotATerminal`.
    fn setAttr(termios: *posix.termios) !void {
        posix.tcsetattr(FILENO, .NOW, termios.*) catch |err| switch (err) {
            error.NotATerminal => unreachable,
            else => |other_err| return other_err,
        };
    }
};

const LineReader = struct {
    const Self = @This();
    const BUFFER_SIZE = 1024;

    reader: fs.File.Reader,
    terminal: StdinTerminal,

    buffer: [BUFFER_SIZE]u8,
    length: usize,
    cursor: usize,

    /// Should *not* be unset, once set.
    eof: bool,

    /// Returns slice of underlying buffer, which may be overridden on next
    /// read call.
    pub fn getLine(self: *Self) []const u8 {
        return self.buffer[0..self.length];
    }

    /// Returns `false` iff **EOF** (iff `self.eof`).
    pub fn readLine(self: *Self) !bool {
        if (self.eof) {
            return false;
        }
        try self.terminal.enableInputMode();
        try self.readLineInner();
        try self.terminal.disableInputMode();
        return true;
    }

    // Assumes `self.terminal` has input mode enabled.
    // Assumes `self.eof` is `false`.
    fn readLineInner(self: *Self) !void {
        self.length = 0;
        self.cursor = 0;

        while (true) {
            {
                std.debug.print("\r\x1b[K", .{});
                std.debug.print("?- ", .{});
                std.debug.print("{s}", .{self.getLine()});
            }

            const byte = try self.readSingleByte() orelse
                break;

            switch (byte) {
                '\n' => {
                    break;
                },
                // Normal character
                0x20...0x7e => {
                    if (self.cursor < self.length) {
                        // TODO: Insert byte at cursor position
                        // Allow succeeding bytes to be cut off if length>size
                        continue;
                    }
                    if (self.cursor < BUFFER_SIZE) {
                        self.buffer[self.cursor] = byte;
                        self.length += 1;
                        self.cursor += 1;
                    }
                },
                // Backspace, delete
                0x08, 0x7f => {
                    // TODO: Delete at cursor position
                    if (self.length > 0 and self.cursor > 0) {
                        self.length -= 1;
                        self.cursor -= 1;
                    }
                },
                // ESC
                0x1b => {
                    if (try self.readSingleByte() != '[') {
                        continue;
                    }
                    switch (try self.readSingleByte() orelse continue) {
                        'A' => {
                            // TODO: Go up in history
                        },
                        'B' => {
                            // TODO: Go down in history
                        },
                        'C' => {
                            // TODO: Move right in line
                        },
                        'D' => {
                            // TODO: Move left in line
                        },
                        else => {},
                    }
                },
                else => {},
            }
        }

        std.debug.print("\n", .{});
    }

    /// Returns `null` and sets `self.eof` iff **EOF**.
    fn readSingleByte(self: *Self) !?u8 {
        var bytes: [1]u8 = undefined;

        while (true) {
            const bytes_read = self.reader.read(&bytes) catch |err|
                switch (err) {
                    error.EndOfStream => {
                        self.eof = true;
                        return null;
                    },
                    else => |other_err| {
                        return other_err;
                    },
                };

            if (bytes_read > 0) {
                return bytes[0];
            }
        }
    }
};

fn readLineAndAppend(
    reader: *fs.File.Reader,
    terminal: *StdinTerminal,
    text: *ArrayList(u8),
    allocator: Allocator,
) !?[]const u8 {
    const start = text.items.len;
    try terminal.enableInputMode();

    // TODO: Why is there an initial zero-byte read ? Remove if possible.
    // Not breaking anything though...

    while (true) {
        const byte = try readSingleByte(reader) orelse
            return null;

        switch (byte) {
            '\n' => {
                break;
            },
            0x20...0x7e => {
                std.debug.print("{c}", .{byte});
                try text.append(allocator, byte);
            },
            0x08, 0x7f => {
                // TODO: Delete character
            },
            0x1b => {
                if (try readSingleByte(reader) != '[') {
                    continue;
                }
                switch (try readSingleByte(reader) orelse continue) {
                    'A' => {
                        // TODO: Go up in history
                    },
                    'B' => {
                        // TODO: Go down in history
                    },
                    'C' => {
                        // TODO: Move right in line
                    },
                    'D' => {
                        // TODO: Move left in line
                    },
                    else => {},
                }
            },
            else => {},
        }
    }

    try terminal.disableInputMode();
    std.debug.print("\n", .{});

    if (start != text.items.len) {
        try text.append(allocator, '\n');
    }
    return text.items[start..text.items.len];
}

fn readSingleByte(reader: *fs.File.Reader) !?u8 {
    var bytes: [1]u8 = undefined;

    while (true) {
        const bytes_read = reader.read(&bytes) catch |err| switch (err) {
            error.EndOfStream => {
                return null;
            },
            else => |other_err| {
                return other_err;
            },
        };

        if (bytes_read > 0) {
            return bytes[0];
        }
    }
}
