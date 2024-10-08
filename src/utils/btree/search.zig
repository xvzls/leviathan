const BTree = @import("btree.zig");
const Node = BTree.Node;

pub fn search(self: *BTree, key: u64, node: ?**Node) ?*anyopaque {
    var current_node: *Node = self.parent;
    var value: ?*anyopaque = null;
    loop: while (true) {
        const nkeys = current_node.nkeys;
        if (nkeys == 0) break;

        for (
            current_node.keys[0..nkeys], current_node.values[0..nkeys],
            current_node.childs[0..nkeys]
        ) |k, v, ch| {
            if (k == key) {
                value = v;
                break :loop;
            }else if (k > key) {
                current_node = ch orelse break :loop;
                continue :loop;
            }
        }
        current_node = current_node.childs[nkeys] orelse break;
    }

    if (node) |v| {
        v.* = current_node;
    }
    return value;
}

pub inline fn find_max_from_node(node: *Node, key: ?*u64, ret_node: ?**Node) ?*anyopaque {
    var current_node: *Node = node;
    while (true) {
        const nkeys = current_node.nkeys;
        if (nkeys == 0) break;
        current_node = current_node.childs[nkeys] orelse break;
    }

    if (ret_node) |v| {
        v.* = current_node;
    }

    const nkeys = current_node.nkeys;
    if (nkeys == 0) return null;

    if (key) |k| k.* = current_node.keys[nkeys - 1];
    return current_node.values[nkeys - 1];
}

pub fn find_max(self: *BTree, key: ?*u64, node: ?**Node) ?*anyopaque {
    return find_max_from_node(self.parent, key, node);
}

pub inline fn find_min_from_node(node: *Node, key: ?*u64, ret_node: ?**Node) ?*anyopaque {
    var current_node: *Node = node;
    while (true) {
        if (current_node.nkeys == 0) break;
        current_node = current_node.childs[0] orelse break;
    }

    if (ret_node) |v| {
        v.* = current_node;
    }
    if (current_node.nkeys == 0) return null;
    if (key) |k| k.* = current_node.keys[0];
    return current_node.values[0];
}

pub fn find_min(self: *BTree, key: ?*u64, node: ?**Node) ?*anyopaque {
    return find_min_from_node(self.parent, key, node);
}
