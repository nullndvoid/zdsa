const std = @import("std");
const zdsa = @import("zdsa");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();
    defer {
        if (gpa.deinit() == .leak) @panic("Memory leak detected");
    }

    // var cands = [_]u8{ 1, 5, 6, 2, 9, 8, 7, 4, 11, 10, 20 };
    // const sums = try twoSum(alloc, cands[0..], 12);

    // for (sums) |p| {
    //     std.debug.print("{d} + {d} = 12\n", .{ p.a, p.b });
    // }
    // defer alloc.free(sums);

    var G = try zdsa.graph.Digraph.init(alloc);
    defer G.deinit();

    // Let's create some test vertices and run some algorithms on them.
    const A = try G.addVertex("A");
    const B = try G.addVertex("B");
    const C = try G.addVertex("C");
    const D = try G.addVertex("D");

    try G.connect(A, B, 12);
    try G.connect(B, A, 7);
    try G.connect(B, D, 2);
    try G.connect(C, A, 4);
    try G.connect(B, C, 6);
    try G.connect(C, D, 2);
    try G.connect(A, D, 9);
    try G.connect(A, C, 1);
    try G.connect(D, B, 1);

    // Let's find the strongly connected components.
    try G.kosaraju();
    // ... And the shortest paths from A to all other nodes.
    try G.djikstra(A);

    for (G.vertices.items) |*v| {
        std.debug.print("* {s} is in SCC #{d}.\n", .{ v.name, v.sccNumber });

        if (v.prev == null) continue;
        // TODO: Make an iterator struct to collect the path. Also, this is just a singly linked list.
        std.debug.print("The shortest path from A to {s} is: {f}\n", .{ v.name, v.distance });
    }
}

const Pair = packed struct { a: u8, b: u8 };

/// Given a list of candidates and a `target`, returns a list of pairs that sum to `target`.
/// Caller must free the returned slice when done with it.
///
/// # Computational Complexity
///
/// O(n) solution.
pub fn twoSum(alloc: std.mem.Allocator, cands: []u8, target: u16) ![]Pair {
    // Form a hash table with all of the candidates.
    var hashmap = std.AutoHashMap(u8, void).init(alloc);
    defer hashmap.deinit();

    for (cands) |c| {
        try hashmap.put(c, {});
    }

    var out = std.ArrayList(Pair).init(alloc);

    for (cands) |c| {
        if (c > target) continue;
        const y = target - @as(u16, @intCast(c));
        const yAsU8: u8 = @truncate(y);

        const res = hashmap.get(yAsU8);
        if (res == null) continue;

        try out.append(Pair{ .a = c, .b = yAsU8 });

        // Now remove this `c` from the hashmap to avoid double counting.
        if (hashmap.remove(c) == false) try std.testing.expect(false);
    }

    const ret = try out.toOwnedSlice();

    return ret;
}
