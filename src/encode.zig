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
        // TODO: Remove
        unset: void,
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

        var locals = LocalStore.init(allocator);
        defer locals.deinit();

        try self.insertTerm(0, term, decls, &locals);

        return self;
    }

    // TODO: Add depth parameter
    fn insertTerm(
        self: *Self,
        index: usize,
        term: *const Term,
        decls: []const Decl,
        locals: *LocalStore,
    ) !void {
        switch (term.value) {
            // TODO: Handle these kinds
            .unresolved => unreachable,

            // Expand global
            .global => |global| {
                try self.insertTerm(index, decls[global].term, decls, locals);
            },

            // Flatten group
            .group => |inner| {
                try self.insertTerm(index, inner, decls, locals);
            },

            .local => |param| {
                const id = locals.get(param) orelse {
                    // TODO: Panic
                    unreachable;
                };
                try self.insertItem(index, .{ .local = id });
            },

            .abstraction => |abstr| {
                const id = try locals.push(ParamRef.from(abstr.parameter));
                try self.insertItem(index, .{ .abstraction = id });
                try self.insertTerm(2 * index + 1, abstr.body, decls, locals);
                try self.insertItem(2 * index + 2, .{ .empty = 1 });
            },

            .application => |appl| {
                try self.insertItem(index, .{ .application = {} });
                try self.insertTerm(2 * index + 1, appl.function, decls, locals);
                try self.insertTerm(2 * index + 2, appl.argument, decls, locals);
            },
        }
    }

    fn insertItem(self: *Self, index: usize, item: Item) !void {
        if (index < self.items.items.len) {
            self.items.items[index] = item;
            return;
        }

        if (index > self.items.items.len) {
            for (self.items.items.len..index) |_| {
                try self.items.append(self.allocator, .{ .unset = {} });
            }
        }

        try self.items.append(self.allocator, item);
    }
};

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
