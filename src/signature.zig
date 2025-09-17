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

const MAX_TRAVERSAL_ITERATION = 200;
const MAX_EXPAND_ITERATION = 200;

// TODO: Rename `MaxRecursion` (iteration like recursion).
// Update `reduction.ReductionError` as well.
const SignatureError = Allocator.Error || error{MaxRecursion};

const LocalId = usize;

/// Returns `null` if recursion limit was reached.
pub fn generateTermSignature(
    term: *const Term,
    allocator: Allocator,
    decls: []const Decl,
) Allocator.Error!?Signature {
    // TODO: Reuse local store
    // TODO: Don't use same allocator
    var locals = LocalStore.init(allocator);
    defer locals.deinit();

    var sig = Signature.init(allocator);

    sig.appendTerm(term, decls, &locals) catch |err|
        switch (err) {
            error.MaxRecursion => return null,
            else => |other_err| return other_err,
        };

    return sig;
}

// TODO: Hash signature data?
pub const Signature = struct {
    const Self = @This();

    nodes: ArrayList(Node),
    count: usize,
    allocator: Allocator,

    const Node = union(enum) {
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
            .nodes = ArrayList(Node).empty,
            .count = 0,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.nodes.deinit(self.allocator);
    }

    pub fn equals(left: *const Self, right: *const Self) bool {
        if (left.nodes.items.len != right.nodes.items.len) {
            return false;
        }
        for (left.nodes.items, right.nodes.items) |left_item, right_item| {
            if (!left_item.equals(right_item)) {
                return false;
            }
        }
        return true;
    }

    /// Traverses terms by BFS.
    fn appendTerm(
        self: *Self,
        term: *const Term,
        decls: []const Decl,
        locals: *LocalStore,
    ) SignatureError!void {
        var queue = term_queue.Queue.init(self.allocator, {});
        defer queue.deinit();

        try queue.add(.{
            .term = term,
            .index = 0,
        });

        var i: usize = 0;
        while (queue.removeOrNull()) |entry| : (i += 1) {
            if (i >= MAX_TRAVERSAL_ITERATION) {
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
                    try self.appendNode(entry.index, .{ .local = id });
                },

                .abstraction => |abstr| {
                    const id = try locals.push(ParamRef.from(abstr.parameter));
                    try self.appendNode(entry.index, .{ .abstraction = id });
                    try queue.add(.{
                        .term = abstr.body,
                        .index = entry.index * 2 + 1,
                    });
                },

                .application => |appl| {
                    try self.appendNode(entry.index, .{ .application = {} });
                    try queue.add(.{
                        .term = appl.function,
                        .index = entry.index * 2 + 1,
                    });
                    try queue.add(.{
                        .term = appl.argument,
                        .index = entry.index * 2 + 2,
                    });
                },
            }
        }
    }

    fn appendNode(self: *Self, index: usize, node: Node) !void {
        assert(std.meta.activeTag(node) != .empty);
        if (index > self.count + 1) {
            try self.nodes.append(self.allocator, .{
                .empty = index - self.count - 1,
            });
        }
        try self.nodes.append(self.allocator, node);
        self.count = index;
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
) SignatureError!*const Term {
    var term = initial_term;
    for (0..MAX_EXPAND_ITERATION) |_| {
        term = switch (term.value) {
            .unresolved => std.debug.panic("symbol should have been resolved already", .{}),
            .global => |global| decls[global].term,
            // Flatten group
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
