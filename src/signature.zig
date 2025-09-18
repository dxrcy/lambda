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
/// To ensure hasher is always deterministic.
const HASHER_SEED = 0;

// TODO: Rename `MaxRecursion` (iteration like recursion).
// Update `reduction.ReductionError` as well.
const HashingError = Allocator.Error || error{MaxRecursion};
const Hasher = std.hash.Wyhash;

pub const Signer = struct {
    const Self = @This();

    // TODO: Rename to `prev_index`
    count: usize,
    params: ParamTree,
    queue: term_queue.Queue,

    const Node = union(enum) {
        abstraction: usize,
        application: void,
        local: usize,
        empty: usize,
    };

    pub fn init(allocator: Allocator) Self {
        return Self{
            .count = 0,
            .params = ParamTree.init(allocator),
            .queue = term_queue.Queue.init(allocator, {}),
        };
    }

    pub fn deinit(self: *Self) void {
        self.params.deinit();
        self.queue.deinit();
    }

    fn reset(self: *Self) void {
        self.count = 0;
        self.params.clear();
        self.queue.clearRetainingCapacity();
    }

    /// Returns `null` if iteration limit was reached.
    pub fn sign(
        self: *Self,
        term: *const Term,
        decls: []const Decl,
    ) Allocator.Error!?u64 {
        var hasher = Hasher.init(HASHER_SEED);

        self.hashTermRecursive(&hasher, term, decls) catch |err|
            switch (err) {
                error.MaxRecursion => return null,
                else => |other_err| return other_err,
            };

        return hasher.final();
    }

    /// Traverses terms by BFS.
    fn hashTermRecursive(
        self: *Self,
        hasher: anytype,
        term: *const Term,
        decls: []const Decl,
    ) HashingError!void {
        self.reset();

        try self.queue.add(.{
            .term = term,
            .index = 0,
        });

        var i: usize = 0;
        while (self.queue.removeOrNull()) |entry| : (i += 1) {
            if (i >= MAX_TRAVERSAL_ITERATION) {
                return error.MaxRecursion;
            }

            const expanded = try expandGlobal(entry.term, decls);
            switch (expanded.value) {
                // TODO: Panic
                .unresolved, .global, .group => unreachable,

                .local => |param| {
                    const param_index = self.params.getAncestorIndex(
                        entry.index,
                        param,
                    ) orelse {
                        unreachable; // TODO: Panic
                    };

                    try self.hashNode(hasher, entry.index, .{
                        .local = param_index,
                    });
                },

                .abstraction => |abstr| {
                    try self.params.insert(
                        entry.index,
                        ParamRef.from(abstr.parameter),
                    );

                    try self.hashNode(hasher, entry.index, .{
                        .abstraction = entry.index,
                    });

                    try self.queue.add(.{
                        .term = abstr.body,
                        .index = entry.index * 2 + 1,
                    });
                },

                .application => |appl| {
                    try self.hashNode(
                        hasher,
                        entry.index,
                        .{ .application = {} },
                    );

                    try self.queue.add(.{
                        .term = appl.function,
                        .index = entry.index * 2 + 1,
                    });

                    try self.queue.add(.{
                        .term = appl.argument,
                        .index = entry.index * 2 + 2,
                    });
                },
            }
        }
    }

    fn hashNode(self: *Self, hasher: anytype, index: usize, node: Node) !void {
        // TODO: assert index > count ?
        assert(std.meta.activeTag(node) != .empty);

        if (index > self.count + 1) {
            std.hash.autoHash(hasher, .{ .empty = index - self.count - 1 });
        }

        std.hash.autoHash(hasher, node);
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
) HashingError!*const Term {
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

pub const ParamTree = struct {
    const Self = @This();

    nodes: ArrayList(Node),
    allocator: Allocator,

    const Node = union(enum) {
        empty: void,
        param: struct {
            ref: ParamRef,
            index: usize,
        },
    };

    pub fn init(allocator: Allocator) Self {
        return Self{
            .nodes = ArrayList(Node).empty,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.nodes.deinit(self.allocator);
    }

    pub fn clear(self: *Self) void {
        self.nodes.clearRetainingCapacity();
    }

    pub fn insert(
        self: *Self,
        index: usize,
        param: ParamRef,
    ) Allocator.Error!void {
        if (index >= self.nodes.items.len) {
            try self.nodes.appendNTimes(
                self.allocator,
                .{ .empty = {} },
                index - self.nodes.items.len + 1,
            );
        }

        assert(self.nodes.items.len >= index + 1);
        assert(std.meta.activeTag(self.nodes.items[index]) == .empty);

        self.nodes.items[index] = .{
            .param = .{
                .ref = param,
                .index = index,
            },
        };
    }

    pub fn getAncestorIndex(
        self: *const Self,
        child: usize,
        target: ParamRef,
    ) ?usize {
        var parent = child;
        while (parent != 0) {
            parent = (parent - 1) / 2;

            // Application nodes between a local and its abstraction are not
            // added to tree
            if (parent >= self.nodes.items.len) {
                continue;
            }

            switch (self.nodes.items[parent]) {
                .empty => {},
                .param => |*param| if (param.ref.equals(target)) {
                    return parent;
                },
            }
        }

        return null;
    }
};
