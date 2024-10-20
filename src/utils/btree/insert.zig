const std = @import("std");

const BTree = @import("btree.zig");
const Node = BTree.Node;

const search = @import("search.zig").search;

inline fn insert_in_empty_node(node: *Node, key: u64, value: *anyopaque) void {
    node.keys[0] = key;
    node.values[0] = value;
    node.nkeys = 1;
}

pub fn do_insertion(node: *Node, key: u64, value: *anyopaque, new_child: ?*Node) void {
    if (new_child) |ch| {
        ch.parent = node;
    }

    const nkeys = node.nkeys;
    if (nkeys == 0) {
        insert_in_empty_node(node, key, value);
        node.childs[1] = new_child;
        return;
    }

    defer node.nkeys += 1;


    const keys = &node.keys;
    const values = &node.values;
    const childs = &node.childs;
    for (0..nkeys) |index| {
        if (key < keys[index]) {
            var i: usize = nkeys;
            while (i > index) : (i -= 1) {
                keys[i] = keys[i - 1];
                values[i] = values[i - 1];
                childs[i + 1] = childs[i];
            }
            
            keys[index] = key;
            values[index] = value;
            childs[index + 1] = new_child;
            return;
        }
    }
    keys[nkeys] = key;
    values[nkeys] = value;
    childs[nkeys + 1] = new_child;
}

inline fn change_parent(new_parent: *Node) void {
    for (new_parent.childs) |node| {
        if (node) |v| {
            v.parent = new_parent;
        }
    }
}

inline fn split_root_node(
    keys: []u64, values: []*anyopaque, childs: []?*Node,
    child_node1: *Node, child_node2: *Node
) void {
    insert_in_empty_node(child_node1, keys[0], values[0]);
    insert_in_empty_node(child_node2, keys[2], values[2]);

    @memcpy(child_node1.childs[0..2], childs[0..2]);
    @memcpy(child_node2.childs[0..2], childs[2..4]);

    change_parent(child_node1);
    change_parent(child_node2);

    keys[0] = keys[1];
    values[0] = values[1];
    childs[0] = child_node1;
    childs[1] = child_node2;

    @memset(childs[2..], null);
}

inline fn split_node(
    keys: []u64, values: []*anyopaque, childs: []?*Node,
    parent: *Node, new_child: *Node
) void {
    insert_in_empty_node(new_child, keys[2], values[2]);
    new_child.childs[0] = childs[2];
    new_child.childs[1] = childs[3];

    change_parent(new_child);

    @memset(childs[2..], null);
    do_insertion(parent, keys[1], values[1], new_child);
}

pub fn split_nodes(allocator: std.mem.Allocator, node: *Node) void {
    var current_node = node;
    while (current_node.nkeys == 3) {
        const keys = &current_node.keys;
        const values = &current_node.values;
        const childs = &current_node.childs;

        const new_node1 = BTree.create_node(allocator) catch unreachable;
        const parent = current_node.parent;
        if (parent) |p_node| {
            split_node(keys, values, childs, p_node, new_node1);
            change_parent(current_node);
            new_node1.parent = p_node;
        }else{
            const new_node2 = BTree.create_node(allocator) catch unreachable;
            split_root_node(keys, values, childs, new_node1, new_node2);
            new_node1.parent = current_node;
            new_node2.parent = current_node;
        }
        current_node.nkeys = 1;

        current_node = parent orelse break;
    }
}

pub inline fn insert_in_node(allocator: std.mem.Allocator, node: *Node, key: u64, value: *anyopaque) void {
    do_insertion(node, key, value, null);
    split_nodes(allocator, node);
}

pub fn insert(self: *BTree, key: u64, value: *anyopaque) bool {
    const allocator = self.allocator;

    var node: *Node = self.parent;
    if (node.nkeys > 0) {
        const value2 = search(self, key, &node);
        if (value2 != null) {
            return false;
        }
    }

    insert_in_node(allocator, node, key, value);

    return true;
}
