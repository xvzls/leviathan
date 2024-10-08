const std = @import("std");

pub const Node = struct {
    parent: ?*Node,
    keys: [3]u64,
    values: [3]*anyopaque,
    childs: [4]?*Node,

    nkeys: u8
};

allocator: std.mem.Allocator,
parent: *Node,

pub fn create_node(allocator: std.mem.Allocator) !*Node {
    const new_node = try allocator.create(Node);
    new_node.parent = null;
    @memset(&new_node.childs, null);
    new_node.nkeys = 0;

    return new_node;
}

pub fn init(allocator: std.mem.Allocator) !*BTree {
    const new_btree = try allocator.create(BTree);
    errdefer allocator.destroy(new_btree);
    new_btree.* = .{
        .allocator = allocator,
        .parent = try create_node(allocator)
    };

    return new_btree;
}

pub usingnamespace @import("search.zig");
pub usingnamespace @import("insert.zig");
pub usingnamespace @import("delete.zig");

pub fn release(self: *BTree) !void {
    if (self.parent.nkeys > 0) return error.BTreeHasElements;

    const allocator = self.allocator;
    allocator.destroy(self.parent);
    allocator.destroy(self);
}

const BTree = @This();
