const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const assert = std.debug.assert;

const TextStore = @import("text/TextStore.zig");

const model = @import("model.zig");
const Decl = model.Decl;
const ParamRef = model.ParamRef;
const Term = model.Term;

const Reporter = @import("Reporter.zig");

const MAX_ENCODE_ITERATION = 200;
const MAX_GLOBAL_EXPAND = 200;

// TODO: Rename `MaxRecursion` (iteration like recursion).
// Update `reduction.ReductionError` as well.
const EncodeError = Allocator.Error || error{MaxRecursion};

const LocalId = usize;

// TODO: Rename "encode*" to "fingerprint*"

/// Returns `null` if recursion limit was reached.
pub fn encodeTerm(
    term: *const Term,
    allocator: Allocator,
    decls: []const Decl,
) Allocator.Error!?TermTree {
    var fingerprint = TermTree.init(allocator);

    // TODO: Reuse local store
    // TODO: Don't use same allocator
    var locals = LocalStore.init(allocator);
    defer locals.deinit();

    fingerprint.insertTerm(term, decls, &locals) catch |err|
        switch (err) {
            error.MaxRecursion => return null,
            else => |other_err| return other_err,
        };

    return fingerprint;
}

// TODO: Rename
pub const TermTree = struct {
    const Self = @This();

    // TODO: Rename `nodes` and `Node`
    items: ArrayList(Item),
    allocator: Allocator,

    const Item = union(enum) {
        abstraction: LocalId,
        application: void,
        local: LocalId,
        empty: usize,

        pub fn equals(left: @This(), right: @This()) bool {
            if (std.meta.activeTag(left) != std.meta.activeTag(right)) {
                return false;
            }
            return switch (left) {
                .abstraction => |abstr| abstr == right.abstraction,
                .application => true,
                .local => |local| local == right.local,
                .empty => |length| length == right.empty,
            };
        }
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

    pub fn equals(left: *const Self, right: *const Self) bool {
        if (left.items.items.len != right.items.items.len) {
            return false;
        }
        for (left.items.items, right.items.items) |left_item, right_item| {
            if (!left_item.equals(right_item)) {
                return false;
            }
        }
        return true;
    }

    /// Traverses terms by BFS.
    fn insertTerm(
        self: *Self,
        term: *const Term,
        decls: []const Decl,
        locals: *LocalStore,
    ) EncodeError!void {
        var queue = term_queue.Queue.init(self.allocator, {});
        defer queue.deinit();

        try queue.add(.{
            .term = term,
            .index = 0,
        });

        var i: usize = 0;
        while (queue.removeOrNull()) |entry| : (i += 1) {
            if (i >= MAX_ENCODE_ITERATION) {
                return error.MaxRecursion;
            }

            const expanded = try expandGlobal(entry.term, decls);
            switch (expanded.value) {
                // TODO: Panic
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
) EncodeError!*const Term {
    var term = initial_term;
    for (0..MAX_GLOBAL_EXPAND) |_| {
        term = switch (term.value) {
            .unresolved => std.debug.panic("symbol should have been resolved already", .{}),
            .global => |global| decls[global].term,
            .group => |inner| inner,
            .local, .application, .abstraction => {
                return term;
            },
        };
    }
    return error.MaxRecursion;
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
