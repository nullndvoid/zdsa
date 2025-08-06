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
    /// Used for Kosaraju's algorithm.
    sccNumber: usize,
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
    /// Used for topoSort.
    currentLabel: usize,

    fn lessThan(context: void, a: u32, b: u32) std.math.Order {
        _ = context;

        return std.math.order(a, b);
    }

    /// Returns the ordering of two vertices by their f(v) such that the standard priority
    /// queue is a max heap.
    fn greaterThan(context: void, a: Vertex, b: Vertex) std.math.Order {
        _ = context;

        return std.math.order(b.toposort, a.toposort);
    }

    /// Returns a new directed graph.
    pub fn init(alloc: std.mem.Allocator) !Digraph {
        return Digraph{
            .vertices = std.ArrayList(Vertex).init(alloc),
            .currentIdx = 0,
            .alloc = alloc,
            .holes = Holes.init(alloc, {}),
            .explored = try std.DynamicBitSet.initEmpty(alloc, 1),
            .currentLabel = 0,
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
            .sccNumber = 0,
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

        self.currentLabel += 1;

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

        self.currentLabel += 1;
    }

    /// Time complexity of O(n + m), where n is the number of vertices and m is the number of edges.
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
        defer queue.deinit();

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

        self.explored.unmanaged.unsetAll();
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

        _ = try V.out.put(W.idx, {});
    }

    /// A recursive DFS helper for topological sorting.
    fn topoSortDFS(self: *Digraph, vertex: *Vertex, currentLabel: *usize) !void {
        self.explored.set(vertex.idx);

        var iter = vertex.out.iterator();
        while (iter.next()) |w| {
            var vtx = self.vertices.items[w.key_ptr.*];
            if (!self.explored.isSet(vtx.idx)) {
                try topoSortDFS(self, &vtx, currentLabel);
            }
        }

        vertex.toposort = @truncate(currentLabel.*);
        currentLabel.* -= 1;
    }

    /// The main public function to start the topological sort.
    pub fn topoSort(self: *Digraph) !void {
        self.explored.unmanaged.unsetAll();
        var currentLabel = self.count();

        for (self.vertices.items) |*v| {
            if (!self.explored.isSet(v.idx)) {
                try self.topoSortDFS(v, &currentLabel);
            }
        }
    }

    pub const TopoSortQueue = std.PriorityQueue(Vertex, void, greaterThan);

    // Build a priority queue from the toposort values -- this should only be called once all vertices have been explored.
    pub fn topoSortQueue(self: *Digraph) !TopoSortQueue {
        var ownedVertices = try self.vertices.clone();
        const ownedVerticesSlice = try ownedVertices.toOwnedSlice();
        const queue = TopoSortQueue.fromOwnedSlice(
            self.alloc,
            ownedVerticesSlice,
            {},
        );

        return queue;
    }

    /// Frees any used resources.
    pub fn deinit(self: *Digraph) void {
        for (self.vertices.items) |*v| {
            v.out.deinit();

            if (v.weights) |*w| {
                w.deinit();
            }
        }
        // Free the vertices array list
        self.vertices.deinit();
        // Free the priority queue for holes
        self.holes.deinit();
        // Free the bitset
        self.explored.deinit();
    }

    /// Returns the transpose of the graph (reversed edges).
    pub fn transpose(self: *const Digraph, alloc: std.mem.Allocator) !Digraph {
        var reverseGraph = try Digraph.init(alloc);

        // First, copy all vertices to the new graph. O(V).
        try reverseGraph.vertices.ensureTotalCapacity(self.vertices.items.len);
        for (self.vertices.items) |v| {
            var vCopy = v;
            vCopy.out = std.AutoArrayHashMap(usize, void).init(alloc);

            if (v.weights) |w_orig| {
                vCopy.weights = try w_orig.clone();
            }

            try reverseGraph.vertices.append(vCopy);
        }

        // Copy holes and currentIdx.
        reverseGraph.holes = self.holes;
        reverseGraph.currentIdx = self.currentIdx;

        // Ensure explored bitset is large enough.
        try reverseGraph.explored.resize(self.vertices.items.len, false);

        for (self.vertices.items) |v| {
            const vIdx = v.idx;
            var it = v.out.iterator();
            while (it.next()) |entry| {
                const w = entry.key_ptr.*; // Edge from vIdx -> w

                try reverseGraph.vertices.items[w].out.put(vIdx, {});
            }
        }

        return reverseGraph;
    }

    /// Performs a depth first search on the graph from `startVertex`.
    /// This returns a slice of `Vertex` in the order they were explored.
    pub fn dfs(self: *Digraph, startVertex: *Vertex) ![]Vertex {
        const maybeS = self.getVertex(startVertex);
        if (maybeS == null)
            return Error.InvalidVertex;
        const S = maybeS.?;
        var stack = try RingBuffer(Vertex).initCapacity(self.alloc, self.count());
        defer stack.deinit();

        try stack.pushFront(S.*);

        var queue = RingBuffer(Vertex).init(self.alloc);
        defer queue.deinit();

        while (stack.popFront()) |v| {
            self.explored.set(v.idx);
            try queue.pushBack(v);

            for (v.out.keys()) |idx| {
                if (self.explored.isSet(idx)) continue;

                try stack.pushFront(self.vertices.items[idx]);
            }
        }

        const ownedSlice = try self.alloc.alloc(Vertex, queue.buffer.len);
        @memcpy(ownedSlice, queue.buffer);

        return ownedSlice;
    }

    /// Returns a set containing the SCCs in the graph, that is to say, a set of
    /// *maximal sets of vertices, called V, in which for any two vertices $v_1, v_2 \in V$,
    /// there exists a two way path between them.*
    pub fn kosaraju(self: *Digraph) !void {
        // Pass 1: DFS on G to compute finish times.
        try self.topoSort();

        // Pass 2: Create a priority queue from G's vertices ordered by finish time.
        var vertices_by_ft = try self.topoSortQueue();
        defer vertices_by_ft.deinit();

        // Reset explored set for the second pass.
        self.explored.unmanaged.unsetAll();

        // Pass 3: Create the transpose graph.
        var rev = try self.transpose(self.alloc);
        defer rev.deinit();

        var sccNumber: u32 = 0;

        // Iterate through vertices in decreasing order of finish times.
        while (vertices_by_ft.removeOrNull()) |v_orig| {
            // We get a vertex from the original graph, which holds the correct finish time.
            // We only care about its index.
            const start_idx = v_orig.idx;
            if (self.explored.isSet(start_idx)) {
                continue;
            }

            // Now, perform a DFS on the transposed graph `rev`,
            // starting from `start_idx`. This will find one SCC.
            var stack = std.ArrayList(u32).init(self.alloc);
            defer stack.deinit();

            try stack.append(start_idx);
            self.explored.set(start_idx);

            while (stack.pop()) |curr_idx| {
                // Assign the SCC number to the vertex in the original graph.
                self.vertices.items[curr_idx].sccNumber = sccNumber;

                // Get the corresponding vertex from the transposed graph.
                var rev_v = &rev.vertices.items[curr_idx];

                // And traverse its outgoing edges in the transposed graph.
                var iter = rev_v.out.iterator();
                while (iter.next()) |entry| {
                    const neighbor_idx = entry.key_ptr.*;
                    if (!self.explored.isSet(neighbor_idx)) {
                        try stack.append(@truncate(neighbor_idx));
                        self.explored.set(neighbor_idx);
                    }
                }
            }

            sccNumber += 1;
        }
    }

    /// Returns the count of `Vertex`'es in the `Digraph`.
    pub fn count(self: *const Digraph) usize {
        return self.vertices.items.len - self.holes.items.len;
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) std.testing.expect(false) catch @panic("Memory leaked!");
    }

    var graph = try Digraph.init(alloc);
    defer graph.deinit();

    var A = try graph.addVertex("A");
    var B = try graph.addVertex("B");
    var C = try graph.addVertex("C");
    var D = try graph.addVertex("D");
    var E = try graph.addVertex("E");
    var F = try graph.addVertex("F");

    try graph.connect(&A, &B);
    try graph.connect(&B, &C);
    try graph.connect(&D, &C);
    try graph.connect(&C, &D);
    try graph.connect(&D, &A);
    try graph.connect(&D, &E);
    try graph.connect(&E, &F);

    try graph.bfs(&A);

    // Let's try Kosaraju's and see how many bugs we can dredge up.
    try graph.kosaraju();

    for (graph.vertices.items) |v| {
        std.debug.print("{s} is in SCC#{d}\n", .{ v.name, v.sccNumber });
    }
}
