const std = @import("std");

/// A wrapper type used for type safety. Use `Digraph.createVertex` to make a new
/// `Vertex`.
pub const VertexId = struct {
    id: u32,
};

/// The distance between a source vertex and "this one".
pub const Distance = union(enum) { Infinite, Finite: u32 };

/// A `Vertex` in a graph. Stores a name, although I may make this generic over
/// other data types later. Also stores some extra metadata used by graph traversal
/// algorithms.
const Vertex = struct {
    /// The name of the `Vertex`.
    name: []const u8,
    /// The value is the weight of the edge. This will be 0 for unweighted graphs.
    out: std.AutoArrayHashMap(u32, u32),
    _id: VertexId,
    /// The previous `Vertex` in the shortest path.
    prev: ?VertexId,
    /// TODO: The hop distance if graph is unweighted, or distance from a source
    /// node set after calling `Digraph.dijkstra`.
    distance: u32,
    /// If the vertex was removed from the graph.
    dead: bool,
    /// The f(v) value assigned in a topological sort of the `Digraph`.
    toposort: u32,
    /// What SCC the node resides in, set after calling `Digraph.kosaraju`.
    sccNumber: usize,

    pub fn getId(self: *const Vertex) VertexId {
        return self._id;
    }

    pub fn setId(self: *Vertex, newId: VertexId) void {
        self._id = newId;
    }
};

/// A directed graph. Optionally stores edge weights, although I haven't yet
/// sorted this out.
pub const Digraph = struct {
    /// Simply a min-heap of indexes used to fill holes with lower indexes in
    /// the `vertices`.
    const Holes = std.PriorityQueue(VertexId, void, lessThan);

    /// Errors returned from the public API.
    pub const Error = error{
        /// The vertex ID passed in was invalid.
        InvalidVertex,
        /// The vertex was deleted from the graph.
        VertexIsDead,
    };

    /// Set if Kosaraju's has not been applied yet, or if the graph was mutated.
    kosarajuDirty: bool = true,
    topoSortDirty: bool = true,
    djikstraDirty: bool = true,

    /// A list of vertices in the `Digraph`.
    vertices: std.ArrayList(Vertex),
    /// The current index, just a counter for assigning IDs to vertices.
    currentIdx: u32,
    /// A list of holes in the arraylist, used to avoid shifting elements around
    /// since arcs/edges use vertex IDs (indices) to refer to connected vertices.
    holes: Holes,
    /// A copy of the `std.mem.Allocator` for later use.
    alloc: std.mem.Allocator,
    /// A bitset of explored vertices, used by some traversal algorithms.
    explored: std.DynamicBitSet,

    /// Returns a new directed graph. User is responsible for calling `deinit`
    /// when no longer required.
    pub fn init(alloc: std.mem.Allocator) !Digraph {
        return Digraph{
            .vertices = std.ArrayList(Vertex).init(alloc),
            .currentIdx = 0,
            .alloc = alloc,
            .holes = Holes.init(alloc, {}),
            .explored = try std.DynamicBitSet.initEmpty(alloc, 0),
        };
    }

    /// Adds a new `Vertex` to the directed graph.
    pub fn addVertex(self: *Digraph, name: []const u8) !VertexId {
        var id: VertexId = .{ .id = 0 };
        const owned_name = try self.alloc.dupe(u8, name);

        // Update the flags just so we know when data is out of date.
        self.djikstraDirty = true;
        self.kosarajuDirty = true;
        self.topoSortDirty = true;

        var v = Vertex{
            .distance = 0,
            .prev = null,
            .dead = false,
            ._id = undefined,
            .name = owned_name,
            .out = std.AutoArrayHashMap(u32, u32).init(self.alloc),
            .toposort = 0,
            .sccNumber = 0,
        };

        if (self.holes.removeOrNull()) |hole| {
            id = hole;
            v.setId(id);
            self.vertices.items[id.id] = v;
        } else {
            id = .{ .id = self.currentIdx };
            v.setId(id);
            try self.vertices.append(v);
            self.currentIdx += 1;
        }

        if (id.id >= self.explored.capacity()) {
            try self.explored.resize(id.id + 1, false);
        }

        return id;
    }

    /// Removes a `Vertex` from the graph.
    pub fn removeVertex(self: *Digraph, id: VertexId) !void {
        _ = try self.getVertexById(id);

        for (self.vertices.items) |*v| {
            _ = v.out.swapRemove(id.id);
        }

        if (id.id == self.currentIdx - 1) {
            self.currentIdx -= 1;
        } else {
            try self.holes.add(id);
        }

        self.vertices.items[id.id].dead = true;
    }

    /// Connects two vertices with an arc (v, w) and optional weight. This is
    /// unidirectional.
    ///
    /// # Note
    ///
    /// If a weight is not given, 0 is assigned.
    pub fn connect(self: *Digraph, v_id: VertexId, w_id: VertexId, weight: ?u32) !void {
        const edgeWeight = weight orelse 0;

        const V = try self.getVertexById(v_id);
        const W = try self.getVertexById(w_id);

        try V.out.put(W.getId().id, edgeWeight);
    }

    /// A helper function to get a `*Vertex` by it's `VertexId`.
    ///
    /// # Errors
    ///
    /// Returns an error if the vertex was invalid, or dead (deleted from the graph).
    pub fn getVertexById(self: *Digraph, id: VertexId) !*Vertex {
        if (id.id >= self.vertices.items.len) {
            return Error.InvalidVertex;
        }
        const v = &self.vertices.items[id.id];
        if (v.dead) {
            return Error.VertexIsDead;
        }
        return v;
    }

    /// Performs a breadth-first search on the graph from the `Vertex` referred
    /// to by `start_id`. This has a time complexity of O(n + m).
    pub fn bfs(self: *Digraph, start_id: VertexId) !void {
        const s = try self.getVertexById(start_id);

        var queue = std.ArrayList(VertexId).init(self.alloc);
        defer queue.deinit();

        try queue.append(s.getId());
        self.explored.set(s.getId().id);

        var i: usize = 0;
        while (i < queue.items.len) {
            const v_id = queue.items[i];
            i += 1;

            const v = &self.vertices.items[v_id.id];
            // std.debug.print("Visited: {s}, out: {any}\n", .{ v.name, v.out.keys() });

            var iter = v.out.iterator();
            while (iter.next()) |w| {
                const neighbor_id = w.key_ptr.*;
                if (!self.explored.isSet(neighbor_id)) {
                    self.explored.set(neighbor_id);
                    try queue.append(.{ .id = neighbor_id });
                }
            }
        }

        self.explored.unmanaged.unsetAll();
    }

    /// Performs a depth-first search of the graph, starting at the `Vertex`
    /// referred to by `start_id`. This has a time complexity of O(n + m), where
    /// `n` is the number of nodes in the graph, and `m` is the number of edges.
    pub fn dfs(self: *Digraph, start_id: VertexId) ![]Vertex {
        const S = try self.getVertexById(start_id);

        var stack = std.ArrayList(VertexId).init(self.alloc);
        defer stack.deinit();
        var result = std.ArrayList(Vertex).init(self.alloc);

        self.explored.unmanaged.unsetAll();

        try stack.append(S.getId());
        self.explored.set(S.getId().id);

        while (stack.pop()) |v_id| {
            const v = self.vertices.items[v_id.id];
            try result.append(v);

            var iter = v.out.iterator();
            while (iter.next()) |entry| {
                const neighbor_id = entry.key_ptr.*;
                if (!self.explored.isSet(neighbor_id)) {
                    self.explored.set(neighbor_id);
                    try stack.append(.{ .id = neighbor_id });
                }
            }
        }

        return result.toOwnedSlice();
    }

    /// Frees allocated memory for the graph. Attempting to use the graph after
    /// this is undefined behavior.
    pub fn deinit(self: *Digraph) void {
        for (self.vertices.items) |*v| {
            self.alloc.free(v.name);
            v.out.deinit();
        }
        self.vertices.deinit();
        self.holes.deinit();
        self.explored.deinit();
    }

    /// A recursive DFS implementation for use by `kosaraju`. This numbers vertices
    /// with f(v) values. This is not necessarily a valid topoSort if a graph contains
    /// cycles, however this is good enough for Kosaraju's algorithm.
    ///
    /// This function has a time complexity of O(n + m), where `n` is the number of
    /// vertices in the graph, and `m` is the number of edges.
    fn topoSortDFS(self: *Digraph, vertex_id: VertexId, currentLabel: *usize) !void {
        self.explored.set(vertex_id.id);

        var vertex = try self.getVertexById(vertex_id);

        var iter = vertex.out.iterator();
        while (iter.next()) |w| {
            const neighbor_id = VertexId{ .id = w.key_ptr.* };
            if (!self.explored.isSet(neighbor_id.id)) {
                try self.topoSortDFS(neighbor_id, currentLabel);
            }
        }

        vertex.toposort = @truncate(currentLabel.*);
        currentLabel.* -= 1;
    }

    /// Topologically sorts the whole graph. This ensures every `Vertex` has an
    /// assigned `toposort` value. This function has a time complexity of O(n + m).
    pub fn topoSort(self: *Digraph) !void {
        self.explored.unmanaged.unsetAll();
        var currentLabel = self.count();

        for (self.vertices.items) |*v| {
            if (!v.dead and !self.explored.isSet(v.getId().id)) {
                try self.topoSortDFS(v.getId(), &currentLabel);
            }
        }
    }

    /// A min-heap priority queue where dequeueing will yield vertices in decreasing order of finishing time.
    pub const TopoSortQueue = std.PriorityQueue(Vertex, void, minTopoSort);

    /// Returns an increasing order priority queue sorting vertices by f(v) (`toposort` field).
    pub fn topoSortQueue(self: *Digraph) !TopoSortQueue {
        var ownedVertices = try self.vertices.clone();
        const ownedVerticesSlice = try ownedVertices.toOwnedSlice();
        return TopoSortQueue.fromOwnedSlice(self.alloc, ownedVerticesSlice, {});
    }

    /// Reverses the arc directions in the graph. This function has a time
    /// complexity of O(n + m), since every vertex is processed just once, and
    /// each edge is examined once only.
    pub fn transpose(self: *const Digraph, alloc: std.mem.Allocator) !Digraph {
        var reverseGraph = try Digraph.init(alloc);
        try reverseGraph.vertices.ensureTotalCapacity(self.vertices.items.len);

        for (self.vertices.items) |v| {
            var vCopy = v;
            vCopy.name = try alloc.dupe(u8, v.name);
            vCopy.out = std.AutoArrayHashMap(u32, u32).init(alloc);

            try reverseGraph.vertices.append(vCopy);
        }

        const holes = try alloc.dupe(VertexId, self.holes.items);
        reverseGraph.holes = Holes.fromOwnedSlice(alloc, holes, {});

        reverseGraph.currentIdx = self.currentIdx;
        try reverseGraph.explored.resize(self.explored.capacity(), false);

        for (self.vertices.items) |v| {
            if (v.dead) continue;
            const v_id = v.getId().id;

            var it = v.out.iterator();
            while (it.next()) |entry| {
                const w_id = entry.key_ptr.*;
                const w_weight = entry.value_ptr.*;
                try reverseGraph.vertices.items[w_id].out.put(v_id, w_weight);
            }
        }

        return reverseGraph;
    }

    /// Finds strongly connected components in the `Digraph`.
    ///
    /// # More Info
    ///
    /// * [SCC Wikipedia Article](https://en.wikipedia.org/wiki/Strongly_connected_component)
    ///
    /// # Computational complexity
    ///
    /// This is a linear-time, O(n + m) algorithm.
    ///
    /// # Errors
    ///
    /// Typically returns an error if allocations failed, i.e. OOM.
    pub fn kosaraju(self: *Digraph) !void {
        try self.topoSort();
        var vertices_by_ft = try self.topoSortQueue();
        defer vertices_by_ft.deinit();

        self.explored.unmanaged.unsetAll();

        var rev = try self.transpose(self.alloc);
        defer rev.deinit();

        var sccNumber: u32 = 0;
        while (vertices_by_ft.removeOrNull()) |v_orig| {
            const start_id = v_orig.getId().id;
            if (self.vertices.items[start_id].dead or self.explored.isSet(start_id)) {
                continue;
            }

            var stack = std.ArrayList(u32).init(self.alloc);
            defer stack.deinit();

            try stack.append(start_id);
            self.explored.set(start_id);

            while (stack.pop()) |curr_id| {
                self.vertices.items[curr_id].sccNumber = sccNumber;

                const rev_v = &rev.vertices.items[curr_id];
                var iter = rev_v.out.iterator();
                while (iter.next()) |entry| {
                    const neighbor_id = entry.key_ptr.*;
                    if (!self.explored.isSet(neighbor_id)) {
                        self.explored.set(neighbor_id);
                        try stack.append(neighbor_id);
                    }
                }
            }
            sccNumber += 1;
        }
    }

    /// Returns the number of vertices in the graph.
    pub fn count(self: *const Digraph) usize {
        return self.vertices.items.len - self.holes.items.len;
    }

    /// Used for assigning new vertices to `Holes`. I prefer that the start of the
    /// array stays full, not that this matters much. This is a comparator function
    /// for a min-heap.
    fn lessThan(context: void, a: VertexId, b: VertexId) std.math.Order {
        _ = context;
        return std.math.order(a.id, b.id);
    }

    /// Used for returning vertices with smaller f(v) values. A min-heap comparator
    /// function.
    fn minTopoSort(context: void, a: Vertex, b: Vertex) std.math.Order {
        _ = context;
        return std.math.order(a.toposort, b.toposort);
    }

    fn djikstra(self: *Digraph, source: VertexId) !void {
        // Reset as per uni pseudocode.
        self.explored.unmanaged.unsetAll();

        var sourceVertex = try self.getVertexById(source);
    }
};
