const std = @import("std");
const graph = @import("graph.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();
    defer {
        if (gpa.deinit() == .leak) @panic("Memory leak detected");
    }

    var G = try graph.Digraph.init(alloc);
    defer G.deinit();

    // Let's create some test vertices and run some algorithms on them.
    const labubu = try G.addVertex("Labubu");
    const dubaiChocolate = try G.addVertex("Dubai chocolate");
    const matcha = try G.addVertex("Matcha");

    // It's very easy to connect vertices. Note that these are arcs, not edges.
    try G.connect(labubu, dubaiChocolate);
    try G.connect(matcha, dubaiChocolate);
    try G.connect(dubaiChocolate, dubaiChocolate);
    try G.connect(matcha, labubu);

    // Let's find the strongly connected components.
    try G.kosaraju();

    for (G.vertices.items) |*v| {
        std.debug.print("* {s} is in SCC #{d}.\n", .{ v.name, v.sccNumber });
    }
}
