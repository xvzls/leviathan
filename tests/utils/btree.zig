const BTree = @import("leviathan").utils.BTree;

const std = @import("std");

const allocator = std.testing.allocator;

test "Create and release" {
    const new_btree = try BTree.init(allocator);
    defer new_btree.release() catch unreachable;

    try std.testing.expectEqual(0, new_btree.parent.nkeys);
    try std.testing.expectEqual(null, new_btree.parent.parent);
    for (new_btree.parent.childs) |v| try std.testing.expectEqual(null, v);
}

test "Inserting elements and removing" {
    const new_btree = try BTree.init(allocator);
    defer new_btree.release() catch unreachable;

    for (0..20) |v| {
        const value: *anyopaque = @ptrFromInt((v + 1) * 23);
        const inserted = new_btree.insert(v, value);
        try std.testing.expect(inserted);
    }

    for (0..20) |v| {
        const value = new_btree.search(v, null);
        try std.testing.expectEqual((v + 1) * 23, @intFromPtr(value));
    }

    for (0..20) |v| {
        const value = new_btree.delete(v);
        try std.testing.expectEqual((v + 1) * 23, @intFromPtr(value));
    }
}

test "Inserting in random order, searching and removing" {
    const new_btree = try BTree.init(allocator);
    defer new_btree.release() catch unreachable;

    var values: [30]u64 = undefined;
    for (&values, 0..) |*v, i| v.* = i * 3;

    const randpgr = std.crypto.random;
    randpgr.shuffle(u64, &values);

    for (values) |v| {
        const value: *anyopaque = @ptrFromInt((v + 1) * 23);
        const inserted = new_btree.insert(v, value);
        try std.testing.expect(inserted);
    }

    randpgr.shuffle(u64, &values);

    for (values) |v| {
        const value = new_btree.search(v, null);
        try std.testing.expectEqual((v + 1) * 23, @intFromPtr(value));
    }

    randpgr.shuffle(u64, &values);
    for (values) |v| {
        const value = new_btree.delete(v);
        try std.testing.expectEqual((v + 1) * 23, @intFromPtr(value));
    }
}
