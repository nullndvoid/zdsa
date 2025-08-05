const std = @import("std");
const RingBuffer = @import("RingBuffer.zig").RingBuffer;

const Vertex = struct {
    /// The name of the `Vertex`.
    name: []const u8,
    out: std.AutoArrayHashMap(usize, void),
    weights: ?std.ArrayList(u32),
    /// The number in which the vertex appears in the list of all vertices.
    idx: u32,
    /// Whether or not the vertex has been removed from the graph.
    dead: bool,
    /// Used in toposort to assign values to vertices. Also used by Kosaraju's algorithm.
    toposort: u32,
};

const Digraph = struct {
    const Holes = std.PriorityQueue(u32, void, lessThan);

    pub const Error = error{InvalidVertex};

    /// A list of all vertices in G = (V, E). The set of all edges is encapsulated
    /// within the `out` fields of each vertex `v` in V.
    vertices: std.ArrayList(Vertex),
    currentIdx: u32,
    holes: Holes,
    /// A copy of the allocator passed in.
    alloc: std.mem.Allocator,
    /// Used to mark vertices as explored. Could maybe move this but cache locality is nice.
    explored: std.DynamicBitSet,

    fn lessThan(context: void, a: u32, b: u32) std.math.Order {
        _ = context;

        return std.math.order(a, b);
    }

    /// Returns a new directed graph.
    pub fn init(alloc: std.mem.Allocator) !Digraph {
        return Digraph{
            .vertices = std.ArrayList(Vertex).init(alloc),
            .currentIdx = 0,
            .alloc = alloc,
            .holes = Holes.init(alloc, {}),
            .explored = try std.DynamicBitSet.initEmpty(alloc, 1),
        };
    }

    /// Adds a new `Vertex` to the graph, returning a copy to the caller.
    pub fn addVertex(self: *Digraph, name: []const u8) !Vertex {
        var v = Vertex{
            .dead = false,
            .idx = self.currentIdx,
            .name = name,
            .out = std.AutoArrayHashMap(usize, void).init(self.alloc),
            .toposort = 0,
            .weights = null,
        };

        if (self.holes.removeOrNull()) |hole| {
            v.idx = hole;
            self.vertices.items[hole] = v;
        } else {
            self.currentIdx += 1;
            try self.vertices.append(v);
        }

        // We should probably just double this when we nearly hit the capacity? We could use currentIdx?
        if (self.currentIdx + 1 >= self.explored.capacity())
            try self.explored.resize(self.explored.capacity() * 2, false);

        return v;
    }

    pub fn removeVertex(self: *Digraph, vertex: *Vertex) void {
        for (self.vertices.items) |*v| {
            v.out.swapRemove(vertex.idx);
        }

        // Now store the index on a queue of holes to be clobbered if not the last index.
        if (vertex.idx != self.currentIdx - 1) {
            self.holes.add(vertex.idx);
        } else {
            self.currentIdx -= 1;
        }

        // Mark the vertex as dead. If we wanted a count of vertices, we can exclude
        // dead ones or whatever.
        self.vertices.items[vertex.idx].dead = true;
        vertex.dead = true;
    }

    // A weird iterative version of BFS. Time complexity is supposed to be O(n + m),
    // where n is the number of vertices and m is the number of edges.
    //
    // I need this explaining to me.
    pub fn bfs(self: *Digraph, startVertex: *Vertex) !void {
        const maybeS = self.getVertex(startVertex);
        if (maybeS == null)
            return Error.InvalidVertex;

        const s = maybeS.?;

        // We keep a queue of vertices to check.
        var queue = try RingBuffer(Vertex).initCapacity(
            self.alloc,
            self.vertices.items.len - self.holes.items.len,
        );

        try queue.pushBack(s.*);

        while (queue.popFront()) |*v| {
            // Mark as visited and queue the out connections.
            self.explored.set(v.idx);
            std.debug.print("Visited: {s}, out: {any}\n", .{ v.name, v.out.keys() });
            var iter = v.out.iterator();
            while (iter.next()) |w| {
                const vtx = self.vertices.items[w.key_ptr.*];
                if (!self.explored.isSet(vtx.idx))
                    try queue.pushBack(vtx);
            }
        }

        self.explored = try std.DynamicBitSet.initEmpty(
            self.alloc,
            self.vertices.items.len,
        );
    }

    // The pointer will be invalidated on updates to the arraylist containing
    // the vertices, so it shall only be considered valid inside member functions.
    fn getVertex(self: *Digraph, vPtr: *Vertex) ?*Vertex {
        if (vPtr.dead or vPtr.idx >= self.vertices.items.len) {
            return null;
        }

        return &self.vertices.items[vPtr.idx];
    }

    /// Connects v to w with an arc (directed v -> w).
    pub fn connect(self: *Digraph, v: *Vertex, w: *Vertex) !void {
        const maybeV = self.getVertex(v);
        const maybeW = self.getVertex(w);
        if (maybeV == null or maybeW == null) {
            return Error.InvalidVertex;
        }

        const V = maybeV.?;
        const W = maybeW.?;

        _ = try V.out.fetchPut(W.idx, {});
    }

    pub fn topoSort(self: *Digraph, startVertex: *Vertex, currentLabel: usize) !void {
        // The vertex is probably from another, larger graph.
        const maybeS = self.getVertex(startVertex);
        if (maybeS == null)
            return .InvalidVertex;

        const s = maybeS.?;

        self.explored.set(s.idx);

        while (startVertex.out.iterator().next()) |w| {
            const vtx = self.vertices.items[w.value_ptr.*];
            if (!self.explored.isSet(vtx.idx))
                topoSort(self, vtx, currentLabel - 1);
        }

        s.toposort = currentLabel;
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();

    var graph = try Digraph.init(alloc);
    var A = try graph.addVertex("A");
    var B = try graph.addVertex("B");
    var C = try graph.addVertex("C");
    var D = try graph.addVertex("D");

    try graph.connect(&A, &B);
    try graph.connect(&B, &C);
    try graph.connect(&D, &C);
    try graph.connect(&C, &D);
    try graph.connect(&D, &A);

    try graph.bfs(&A);
}
