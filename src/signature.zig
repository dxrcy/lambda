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

const Hasher = std.hash.Wyhash;
const SigningError = Allocator.Error || error{DepthCutoff};

pub const Signer = struct {
    const Self = @This();

    prev_index: usize,
    params: ParamTree,
    queue: NodeQueue.Queue,

    const Node = union(enum) {
        abstraction: usize,
        application: void,
        local: usize,
        empty: usize,
    };

    pub fn init(allocator: Allocator) Self {
        return Self{
            .prev_index = 0,
            .params = ParamTree.init(allocator),
            .queue = NodeQueue.Queue.init(allocator, {}),
        };
    }

    pub fn deinit(self: *Self) void {
        self.params.deinit();
        self.queue.deinit();
    }

    fn reset(self: *Self) void {
        self.prev_index = 0;
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
        self.hashTerm(&hasher, term, decls) catch |err|
            switch (err) {
                error.DepthCutoff => return null,
                else => |other_err| return other_err,
            };
        return hasher.final();
    }

    /// Traverses terms by BFS.
    fn hashTerm(
        self: *Self,
        hasher: anytype,
        term: *const Term,
        decls: []const Decl,
    ) SigningError!void {
        self.reset();

        try self.queue.add(.{
            .term = term,
            .index = 0,
            .parent = null,
        });

        var i: usize = 0;
        while (self.queue.removeOrNull()) |entry| : (i += 1) {
            if (i >= MAX_TRAVERSAL_ITERATION) {
                return error.DepthCutoff;
            }

            const expanded = try expandGlobal(entry.term, decls);

            if (entry.parent) |parent| {
                switch (parent.node) {
                    .local, .empty => unreachable,
                    .abstraction => std.debug.print("A", .{}),
                    .application => std.debug.print("P", .{}),
                }
                std.debug.print("{}", .{parent.index});
                std.debug.print(" -> ", .{});
                switch (expanded.value) {
                    .unresolved, .global, .group => unreachable,
                    .local => std.debug.print("L", .{}),
                    .abstraction => std.debug.print("A", .{}),
                    .application => std.debug.print("P", .{}),
                }
                std.debug.print("{}", .{entry.index});
                std.debug.print("\n", .{});

                switch (expanded.value) {
                    .local => |param| {
                        const param_index = self.params.getAncestorIndex(
                            entry.index,
                            param,
                        ) orelse unreachable;
                        std.debug.print(
                            "L{} -> A{}\n",
                            .{ entry.index, param_index },
                        );
                    },
                    else => {},
                }
            }

            switch (expanded.value) {
                .unresolved => std.debug.panic("symbol should have been resolved already", .{}),
                .global => std.debug.panic("global should have been expanded already", .{}),
                .group => std.debug.panic("group should have been flattened already", .{}),

                .local => |param| {
                    const param_index = self.params.getAncestorIndex(
                        entry.index,
                        param,
                    ) orelse {
                        std.debug.panic("parameter should exist in tree matching local binding", .{});
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

                    const parent = NodeQueue.Item.Parent{
                        .node = .{ .abstraction = entry.index },
                        .index = entry.index,
                    };

                    try self.queue.add(.{
                        .term = abstr.body,
                        .index = entry.index * 2 + 1,
                        .parent = parent,
                    });
                },

                .application => |appl| {
                    try self.hashNode(
                        hasher,
                        entry.index,
                        .{ .application = {} },
                    );

                    const parent = NodeQueue.Item.Parent{
                        .node = .{ .application = {} },
                        .index = entry.index,
                    };

                    try self.queue.add(.{
                        .term = appl.function,
                        .index = entry.index * 2 + 1,
                        .parent = parent,
                    });

                    try self.queue.add(.{
                        .term = appl.argument,
                        .index = entry.index * 2 + 2,
                        .parent = parent,
                    });
                },
            }
        }
    }

    fn hashNode(self: *Self, hasher: anytype, index: usize, node: Node) !void {
        assert(index >= self.prev_index);
        assert(std.meta.activeTag(node) != .empty);

        if (index > self.prev_index + 1) {
            std.hash.autoHash(hasher, .{ .empty = index - self.prev_index - 1 });
        }

        std.hash.autoHash(hasher, node);
        self.prev_index = index;
    }
};

fn expandGlobal(
    initial_term: *const Term,
    decls: []const Decl,
) SigningError!*const Term {
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
    return error.DepthCutoff;
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

const NodeQueue = struct {
    pub const Item = struct {
        term: *const Term,
        index: usize,
        parent: ?Parent,

        const Parent = struct {
            node: Signer.Node,
            index: usize,
        };
    };

    pub const Queue = std.PriorityQueue(Item, void, compare);

    fn compare(_: void, a: Item, b: Item) std.math.Order {
        return std.math.order(a.index, b.index);
    }
};
