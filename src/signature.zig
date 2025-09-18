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

/// Returns `null` if recursion limit was reached.
pub fn generateTermSignature(
    term: *const Term,
    allocator: Allocator,
    decls: []const Decl,
) Allocator.Error!?Signature {
    // TODO: Reuse local store
    // TODO: Don't use same allocator
    var params = ParamTree.init(allocator);
    defer params.deinit();

    var sig = Signature.init(allocator);

    sig.appendTerm(term, decls, &params) catch |err|
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
        abstraction: usize,
        application: void,
        local: usize,
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
        params: *ParamTree,
    ) SignatureError!void {
        // TODO: Caller passes in
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
                    const param_index = params.getAncestorIndex(
                        entry.index,
                        param,
                    ) orelse {
                        unreachable; // TODO: Panic
                    };
                    try self.appendNode(entry.index, .{
                        .local = param_index,
                    });
                },

                .abstraction => |abstr| {
                    try params.insert(
                        entry.index,
                        ParamRef.from(abstr.parameter),
                    );

                    try self.appendNode(entry.index, .{
                        .abstraction = entry.index,
                    });

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
