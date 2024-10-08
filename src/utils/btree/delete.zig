const std = @import("std");

const BTree = @import("btree.zig");
const Node = BTree.Node;

const search = @import("search.zig");

inline fn delete_from_left(node: *?*Node, key: *u64, value: **anyopaque) *Node {
    var node_with_bigger_value: *Node = undefined;
    value.* = search.find_max_from_node(node.*.?, key, &node_with_bigger_value).?;

    node_with_bigger_value.nkeys -= 1;
    if (node_with_bigger_value.nkeys == 0) {
        const p_node = node_with_bigger_value.parent.?;
        const p_last_node = &p_node.childs[p_node.nkeys];
        const rem_child = node_with_bigger_value.childs[0];
        if (p_last_node.* == node_with_bigger_value) {
            p_last_node.* = rem_child;
        }else{
            node.* = rem_child;
        }
        if (rem_child) |child| child.parent = p_node;
    }

    return node_with_bigger_value;
}

inline fn delete_from_right(node: *?*Node, key: *u64, value: **anyopaque) *Node {
    var node_with_smaller_value: *Node = undefined;
    value.* = search.find_min_from_node(node.*.?, key, &node_with_smaller_value).?;

    const nkeys = node_with_smaller_value.nkeys - 1;
    node_with_smaller_value.nkeys = nkeys;

    if (nkeys == 0) {
        const p_node = node_with_smaller_value.parent.?;
        const p_first_node = &p_node.childs[0];
        const rem_child = node_with_smaller_value.childs[1];
        if (p_first_node.* == node_with_smaller_value) {
            p_first_node.* = rem_child;
        }else{
            node.* = rem_child;
        }
        if (rem_child) |child| child.parent = p_node;
    }else{
        const keys = &node_with_smaller_value.keys;
        const values = &node_with_smaller_value.values;
        const childs = &node_with_smaller_value.childs;
        for (0..nkeys) |i| {
            keys[i] = keys[i + 1];
            values[i] = values[i + 1];
            childs[i] = childs[i + 1];
        }
        childs[nkeys] = childs[nkeys + 1];
    }

    return node_with_smaller_value;
}

// TODO: Cuando eliminas el elemento mayor o menor tambien tiene hijos en el otro lado, recuerda pasarlos
inline fn delete_func(
    allocator: std.mem.Allocator, node: *?*Node, func: anytype,
    keys: []u64, values: []*anyopaque, index: usize
) void {
    var key: u64 = undefined;
    var value: *anyopaque = undefined;
    const child: *Node = func(node, &key, &value);
    if (child.nkeys == 0) {
        allocator.destroy(child);
    }

    keys[index] = key;
    values[index] = value;
}

inline fn delete_key_from_node(
    allocator: std.mem.Allocator, node: *Node, keys: []u64,
    values: []*anyopaque, childs: []?*Node, index: usize
) void {
    const left_child = &childs[index];
    const right_child = &childs[index + 1];
    if (left_child.* != null) {
        delete_func(allocator, left_child, delete_from_left, keys, values, index);
        return;
    }else if (right_child.* != null) {
        delete_func(allocator, right_child, delete_from_right, keys, values, index);
        return;
    }

    const nkeys = node.nkeys - 1;
    node.nkeys = nkeys;

    if (nkeys == 0) {
        const p_node = node.parent orelse return;

        for (p_node.childs[0..(p_node.nkeys + 1)]) |*child| {
            if (child.* == node) {
                allocator.destroy(node);
                child.* = null;
                break;
            }
        }
    }else{
        for (index..nkeys) |i| {
            keys[i] = keys[i + 1];
            values[i] = values[i + 1];
            childs[i] = childs[i + 1];
        }
        childs[nkeys] = childs[nkeys + 1];
    }
}

pub fn delete(self: *BTree, key: u64) ?*anyopaque {
    var node: *Node = undefined;
    const value = search.search(self, key, &node);
    if (value == null) return null;

    const keys = &node.keys;
    const values = &node.values;
    const childs = &node.childs;

    const nkeys = node.nkeys;
    for (0..nkeys) |i| {
        if (key == keys[i]) {
            delete_key_from_node(self.allocator, node, keys, values, childs, i);
            break;
        }
    }

    return value;
}

pub fn pop(self: *BTree, key: ?*u64) ?*anyopaque {
    var node: *Node = undefined;
    const value = search.find_max(self, key, &node);
    if (value == null) return null;

    const keys = &node.keys;
    const values = &node.values;
    const childs = &node.childs;
    delete_key_from_node(self.allocator, node, keys, values, childs, node.nkeys - 1);

    return value;
}
