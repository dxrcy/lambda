const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const assert = std.debug.assert;

const TextStore = @import("text/TextStore.zig");
const SourceSpan = TextStore.SourceSpan;

const model = @import("model.zig");
const Decl = model.Decl;
const ParamRef = model.ParamRef;
const Term = model.Term;

const LocalId = usize;

pub const TermTree = struct {
    const Self = @This();

    items: ArrayList(Item),
    allocator: Allocator,

    const Item = union(enum) {
        abstraction: LocalId,
        application: void,
        local: LocalId,
        empty: usize,
    };

    fn init(allocator: Allocator) Self {
        return Self{
            .items = ArrayList(Item).empty,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.items.deinit(self.allocator);
    }

    pub fn encodeTerm(
        term: *const Term,
        allocator: Allocator,
        decls: []const Decl,
    ) !Self {
        var self = Self.init(allocator);

        // TODO: Reuse local store
        // TODO: Don't use same allocator
        var locals = LocalStore.init(allocator);
        defer locals.deinit();

        try self.insertTerm(term, decls, &locals);

        return self;
    }

    /// Bfs.
    fn insertTerm(
        self: *Self,
        term: *const Term,
        decls: []const Decl,
        locals: *LocalStore,
    ) !void {
        var queue = term_queue.Queue.init(self.allocator, {});
        defer queue.deinit();

        try queue.add(.{
            .term = term,
            .index = 0,
        });

        // TODO: Add iteration limit
        while (queue.removeOrNull()) |entry| {
            switch (expandGlobal(entry.term, decls).value) {
                .unresolved, .global, .group => unreachable,

                .local => |param| {
                    const id = locals.get(param) orelse {
                        unreachable; // TODO: Panic
                    };
                    try self.insertItem(entry.index, .{ .local = id });
                },

                .abstraction => |abstr| {
                    const id = try locals.push(ParamRef.from(abstr.parameter));
                    try self.insertItem(entry.index, .{ .abstraction = id });
                    try queue.add(.{
                        .term = abstr.body,
                        .index = 2 * entry.index + 1,
                    });
                },

                .application => |appl| {
                    try self.insertItem(entry.index, .{ .application = {} });
                    try queue.add(.{
                        .term = appl.function,
                        .index = 2 * entry.index + 1,
                    });
                    try queue.add(.{
                        .term = appl.argument,
                        .index = 2 * entry.index + 2,
                    });
                },
            }
        }
    }

    fn insertItem(self: *Self, index: usize, item: Item) !void {
        if (index > self.items.items.len) {
            try self.items.append(self.allocator, .{
                .empty = index - self.items.items.len,
            });
        }
        try self.items.append(self.allocator, item);
    }
};

const term_queue = struct {
    pub const Item = struct {
        term: *const Term,
        index: usize,
    };

    const Queue = std.PriorityQueue(Item, void, compare);

    fn compare(_: void, _: Item, _: Item) std.math.Order {
        return std.math.Order.eq;
    }
};

// TODO: Add iteration limit
fn expandGlobal(
    initial_term: *const Term,
    decls: []const Decl,
) *const Term {
    var term = initial_term;
    while (true) {
        term = switch (term.value) {
            .unresolved => std.debug.panic("symbol should have been resolved already", .{}),
            .global => |global| decls[global].term,
            .group => |inner| inner,
            .local, .application, .abstraction => {
                return term;
            },
        };
    }
}

pub const LocalStore = struct {
    const Self = @This();

    entries: ArrayList(ParamRef),
    allocator: Allocator,

    pub fn init(allocator: Allocator) Self {
        return .{
            .entries = ArrayList(ParamRef).empty,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.entries.deinit(self.allocator);
    }

    pub fn isEmpty(self: *const Self) bool {
        return self.entries.items.len == 0;
    }

    pub fn push(self: *Self, param: ParamRef) Allocator.Error!usize {
        const id = self.entries.items.len;
        try self.entries.append(self.allocator, param);
        return id;
    }

    pub fn pop(self: *Self) void {
        _ = self.entries.pop();
    }

    pub fn get(self: *Self, param: ParamRef) ?LocalId {
        for (self.entries.items, 0..) |entry, i| {
            if (entry.equals(param)) {
                return i;
            }
        }
        return null;
    }
};
