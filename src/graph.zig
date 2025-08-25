const std = @import("std");

/// A wrapper type used for type safety. Use `Digraph.createVertex` to make a new
/// `Vertex`.
pub const VertexId = struct {
    id: u32,
};

/// The distance between a source vertex and "this one".
pub const Distance = union(enum) {
    Infinite,
    Finite: u32,

    /// Returns the ordering of this and another distance.
    pub fn cmp(self: *const Distance, other: Distance) std.math.Order {
        const Order = std.math.Order;

        return switch (self.*) {
            .Infinite => switch (other) {
                .Infinite => Order.eq,
                .Finite => |_| Order.gt,
            },
            .Finite => |v| switch (other) {
                .Infinite => Order.lt,
                .Finite => |o| std.math.order(v, o),
            },
        };
    }

    /// Used by std.fmt to print as a string. Use with {f}.
    pub fn format(
        self: *const Distance,
        // Kill Andrew Kelley or whoever made this decision to use {f},
        // not that I would normally care.
        //
        //       comptime fmt: []const u8,
        //       _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        switch (self.*) {
            .Finite => |d| try writer.print("{d}", .{d}),
            .Infinite => try writer.writeAll("∞"),
        }
    }

    /// Whether or not the distance is set to Infinite.
    pub inline fn isInfinite(self: *const Distance) bool {
        return switch (self.*) {
            .Infinite => true,
            else => false,
        };
    }
};

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
    distance: Distance = .Infinite,
    /// If the vertex was removed from the graph.
    dead: bool,
    /// The f(v) value assigned in a topological sort of the `Digraph`.
    toposort: u32,
    /// What SCC the node resides in, set after calling `Digraph.kosaraju`.
    sccNumber: usize,
    /// The next vertex in a path as found by DFS/BFS.
    next: ?*Vertex = null,

    /// I want to imply that this field is private, so the getter might just look nicer.
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
    lastSourceVertex: ?VertexId = null,

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
            .vertices = std.ArrayList(Vertex).empty,
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
            .distance = .Infinite,
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
            try self.vertices.append(self.alloc, v);
            self.currentIdx += 1;
        }

        if (id.id >= self.explored.capacity()) {
            try self.explored.resize(id.id + 1, false);
        }

        return id;
    }

    /// A wrapper type for a pair (vertex, edge weight).
    pub const VertexAndWeight = struct { vertex: *Vertex, weight: u32 };

    pub const EdgeIterator = struct {
        const Self = @This();

        graph: *const Digraph,
        vertex: *Vertex,
        iter: std.AutoArrayHashMap(u32, u32).Iterator,

        pub fn init(graph: *const Digraph, vertex: VertexId) !Self {
            var v = try graph.getVertexById(vertex);
            const iter = v.out.iterator();

            return Self{
                .vertex = v,
                .iter = iter,
                .graph = graph,
            };
        }

        pub fn next(self: *Self) ?VertexAndWeight {
            const n = self.iter.next();
            if (n == null) return null;

            const vertexId = VertexId{ .id = n.?.key_ptr.* };
            const vertex = self.graph.getVertexById(vertexId) catch return null;

            const edgeWeight = n.?.value_ptr.*;

            return VertexAndWeight{ .vertex = vertex, .weight = edgeWeight };
        }

        // TODO: Test this works and add to the standard library.
        pub fn peek(self: *Self) ?VertexAndWeight {
            const vals = self.iter.values;
            const keys = self.iter.keys;

            if (self.iter.index + 1 >= self.iter.len) return null;

            const nextIdx = self.iter.index + 1;

            const val = VertexId{ .id = vals[nextIdx] };
            const key = keys[nextIdx];

            const vtx = self.graph.getVertexById(val) catch return null;

            return VertexAndWeight{ .vertex = vtx, .weight = key };
        }
    };

    pub fn dfsTo(self: *const Digraph, source: VertexId, sink: VertexId, alloc: std.mem.Allocator) !?[]VertexId {
        // A map to store the path: edgeTo[child] = parent
        var edgeTo = std.HashMap(VertexId, VertexId, std.hash_map.AutoContext(VertexId), 80).init(alloc);
        defer edgeTo.deinit();

        // Stack for the iterative DFS.
        var stack = std.ArrayList(VertexId).empty;
        defer stack.deinit(alloc);

        // Use a separate set to track visited nodes to avoid re-visiting. TODO: Make this a bitset.
        var visited = std.HashMap(VertexId, void, std.hash_map.AutoContext(VertexId), 80).init(alloc);
        defer visited.deinit();

        try stack.append(alloc, source);
        try visited.put(source, {});

        while (stack.pop()) |V| {
            if (V.id == sink.id) {
                // --- Path Found: Reconstruct it from the edgeTo map ---
                var path = std.ArrayList(VertexId).empty;

                var current = sink;
                while (true) {
                    try path.append(alloc, current);
                    if (current.id == source.id) break;
                    current = edgeTo.get(current).?;
                }

                // The path is currently sink -> source, so we reverse it
                std.mem.reverse(VertexId, path.items);
                return try path.toOwnedSlice(alloc);
            }

            var edges = try EdgeIterator.init(self, V);
            while (edges.next()) |e| {
                const W = e.vertex.getId();
                if (!visited.contains(W)) {
                    try visited.put(W, {});
                    try edgeTo.put(W, V); // Record that we reached W from V
                    try stack.append(alloc, W);
                }
            }
        }

        // Sink was not reached
        return null;
    }

    /// Flips an edge in this graph.
    pub fn flipEdge(self: *Digraph, v: VertexId, w: VertexId) !void {
        try self.connect(w, v, self.getWeight(v, w));
        _ = try self.disconnect(v, w);
    }

    pub fn getWeight(self: *const Digraph, v: VertexId, w: VertexId) ?u32 {
        var V = self.getVertexById(v) catch unreachable;

        return V.out.get(w.id);
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
    pub fn getVertexById(self: *const Digraph, id: VertexId) !*Vertex {
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

        var queue = std.ArrayList(VertexId).empty;
        defer queue.deinit(self.alloc);

        try queue.append(self.alloc, s.getId());
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
                    try queue.append(self.alloc, .{ .id = neighbor_id });
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

        var stack = std.ArrayList(VertexId).empty;
        defer stack.deinit(self.alloc);
        var result = std.ArrayList(Vertex).empty;

        self.explored.unmanaged.unsetAll();

        try stack.append(self.alloc, S.getId());
        self.explored.set(S.getId().id);

        while (stack.pop()) |v_id| {
            const v = self.vertices.items[v_id.id];
            try result.append(self.alloc, v);

            var iter = v.out.iterator();
            while (iter.next()) |entry| {
                const neighbor_id = entry.key_ptr.*;
                if (!self.explored.isSet(neighbor_id)) {
                    self.explored.set(neighbor_id);
                    try stack.append(self.alloc, .{ .id = neighbor_id });
                }
            }
        }

        return result.toOwnedSlice(self.alloc);
    }

    /// Frees allocated memory for the graph. Attempting to use the graph after
    /// this is undefined behavior.
    pub fn deinit(self: *Digraph) void {
        for (self.vertices.items) |*v| {
            self.alloc.free(v.name);
            v.out.deinit();
        }
        self.vertices.deinit(self.alloc);
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
        if (self.topoSortDirty) return;

        self.topoSortDirty = false;

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
        var ownedVertices = try self.vertices.clone(self.alloc);
        const ownedVerticesSlice = try ownedVertices.toOwnedSlice(self.alloc);
        return TopoSortQueue.fromOwnedSlice(self.alloc, ownedVerticesSlice, {});
    }

    /// Reverses the arc directions in the graph. This function has a time
    /// complexity of O(n + m), since every vertex is processed just once, and
    /// each edge is examined once only.
    pub fn transpose(self: *const Digraph, alloc: std.mem.Allocator) !Digraph {
        var reverseGraph = try Digraph.init(alloc);
        try reverseGraph.vertices.ensureTotalCapacity(alloc, self.vertices.items.len);

        for (self.vertices.items) |v| {
            var vCopy = v;
            vCopy.name = try alloc.dupe(u8, v.name);
            vCopy.out = std.AutoArrayHashMap(u32, u32).init(alloc);

            try reverseGraph.vertices.append(self.alloc, vCopy);
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
        if (!self.kosarajuDirty) return;

        self.kosarajuDirty = false;

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

            var stack = std.ArrayList(u32).empty;
            defer stack.deinit(self.alloc);

            try stack.append(self.alloc, start_id);
            self.explored.set(start_id);

            while (stack.pop()) |curr_id| {
                self.vertices.items[curr_id].sccNumber = sccNumber;

                const rev_v = &rev.vertices.items[curr_id];
                var iter = rev_v.out.iterator();
                while (iter.next()) |entry| {
                    const neighbor_id = entry.key_ptr.*;
                    if (!self.explored.isSet(neighbor_id)) {
                        self.explored.set(neighbor_id);
                        try stack.append(self.alloc, neighbor_id);
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

    /// Return the ordering of two vertices such that a min heap is formed.
    fn minDistance(context: void, a: IdDistancePair, b: IdDistancePair) std.math.Order {
        _ = context;

        return a.dist.cmp(b.dist);
    }

    /// Used for sorting rather than using copies of vertices.
    const IdDistancePair = struct { id: VertexId, dist: Distance };

    /// Finds the shortest paths to all nodes from a source node.
    pub fn djikstra(self: *Digraph, source: VertexId) !void {
        if (!self.djikstraDirty) {
            if (self.lastSourceVertex) |s| if (s.id == source.id) return;
        }

        // Reset X and init distances as per uni pseudocode.
        self.explored.unmanaged.unsetAll();

        var sourceVertex = try self.getVertexById(source);

        self.lastSourceVertex = source;

        var queue = std.PriorityQueue(
            IdDistancePair,
            void,
            minDistance,
        ).init(self.alloc, {});

        defer queue.deinit();

        // Clear out state.
        for (self.vertices.items) |*v| {
            v.distance = .Infinite;
            v.prev = null;
        }

        sourceVertex.distance = .{ .Finite = 0 };

        // Initialise the queue with just the source vertex.
        try queue.add(.{
            .dist = sourceVertex.distance,
            .id = source,
        });

        while (queue.removeOrNull()) |w| {
            var wVertex = try self.getVertexById(w.id);

            // Skip stale entries in our queue.
            if (w.dist.cmp(wVertex.distance).compare(.gt)) {
                continue;
            }

            // A path is finalised when we pull it out of the queue. Think of
            // this as the frontier.
            self.explored.set(w.id.id);

            var iter = wVertex.out.iterator();
            while (iter.next()) |e| {
                const Y = VertexId{ .id = e.key_ptr.* };
                const edgeWeight = e.value_ptr.*;

                if (self.explored.isSet(Y.id)) continue;

                const prevDist = if (!wVertex.distance.isInfinite())
                    wVertex.distance.Finite
                else
                    0;

                const len = Distance{ .Finite = edgeWeight + prevDist };

                var y = try self.getVertexById(Y);
                if (y.distance.cmp(len).compare(.lt)) continue;

                y.distance = len;

                // Update the queue and previous pointer.
                try queue.add(IdDistancePair{ .id = Y, .dist = len });
                y.prev = wVertex.getId();
            }
        }
    }

    pub fn fordFulkerson(self: *const Digraph, source: VertexId, sink: VertexId) !usize {
        var residual = try self.clone();
        defer residual.deinit();

        var flow: usize = 0;
        const alloc = residual.alloc;

        pathfinder: while (true) {

            // Find a path on G_residual using DFS.
            const maybePath = try residual.dfsTo(source, sink, alloc);
            if (maybePath == null)
                break;

            const path = maybePath.?;
            defer alloc.free(path);

            // Reconstruct path and find bottleneck capacity
            var path_bottleneck: u32 = std.math.maxInt(u32);
            // const current = source;

            for (path, 0..) |V, idx| {
                // Handle last vertex.
                if (idx + 1 >= path.len) break;

                const W = path[idx + 1];

                const capacity = residual.getWeight(V, W) orelse 0;

                if (capacity == 0) continue :pathfinder;

                path_bottleneck = @min(path_bottleneck, capacity);
            }

            // Now fixup residual graph.
            for (path, 0..) |V, idx| {
                if (idx + 1 >= path.len) break;
                const W = path[idx + 1];

                const capacity = residual.getWeight(V, W).?;
                const leftoverCapacity = capacity - path_bottleneck;

                // If leftover capacity is 0, flip the edge.
                if (leftoverCapacity == 0) {
                    try residual.flipEdge(V, W);
                } else {
                    try residual.connect(W, V, path_bottleneck);
                    try residual.connect(V, W, leftoverCapacity);
                }
            }

            flow += path_bottleneck;
        }

        return flow;
    }

    /// Disconnects `v` from `w` by deleting the edge. Returns whether
    /// or not the removal worked.
    pub fn disconnect(self: *Digraph, v: VertexId, w: VertexId) !bool {
        const V = try self.getVertexById(v);

        return V.out.swapRemove(w.id);
    }

    /// Returns a copy of this `Digraph`. O(n) time complexity.
    pub fn clone(self: *const Digraph) !Digraph {
        var copy = try Digraph.init(self.alloc);

        copy.currentIdx = self.currentIdx;
        copy.djikstraDirty = self.djikstraDirty;
        copy.kosarajuDirty = self.kosarajuDirty;
        copy.topoSortDirty = self.topoSortDirty;
        copy.lastSourceVertex = self.lastSourceVertex;

        copy.explored = try self.explored.clone(copy.alloc);

        const holes = try copy.alloc.dupe(VertexId, self.holes.items);
        copy.holes = Digraph.Holes.fromOwnedSlice(copy.alloc, holes, {});

        try copy.vertices.ensureTotalCapacity(self.alloc, self.vertices.items.len);

        for (self.vertices.items) |original_v| {
            var v_copy = original_v;

            v_copy.name = try copy.alloc.dupe(u8, original_v.name);
            v_copy.out = try original_v.out.clone();
            v_copy.next = null;
            v_copy.prev = null;
            v_copy.distance = .Infinite;

            try copy.vertices.append(self.alloc, v_copy);
        }

        return copy;
    }
};

test "dfsTo" {
    const alloc = std.testing.allocator;
    var G = try Digraph.init(alloc);
    defer G.deinit();

    const A = try G.addVertex("A");
    const B = try G.addVertex("B");
    const C = try G.addVertex("C");
    const D = try G.addVertex("D");

    // try G.connect(A, D, 1);
    try G.connect(A, B, 2);
    try G.connect(C, B, 2);
    try G.connect(C, D, 2);
    try G.connect(B, C, 1);

    const path = try G.dfsTo(A, D, alloc);
    try std.testing.expect(path != null);
    defer alloc.free(path.?);

    const lastId = path.?[path.?.len - 1];
    const lastVtx = try G.getVertexById(lastId);

    try std.testing.expectEqualStrings("D", lastVtx.name);
}

test "kosaraju" {
    const alloc = std.testing.allocator;
    var G = try Digraph.init(alloc);
    defer G.deinit();

    const A = try G.addVertex("A");
    const B = try G.addVertex("B");
    const C = try G.addVertex("C");
    const D = try G.addVertex("D");

    try G.connect(A, B, null);
    try G.connect(B, C, null);
    try G.connect(C, A, null);
    try G.connect(D, C, null);

    try G.kosaraju();

    const a = try G.getVertexById(A);
    const d = try G.getVertexById(D);

    try std.testing.expect(a.sccNumber != d.sccNumber);

    const c = try G.getVertexById(C);

    try std.testing.expect(a.sccNumber == c.sccNumber);
}

test "fordFulkerson" {
    const alloc = std.testing.allocator;
    var G = try Digraph.init(alloc);
    defer G.deinit();

    const A = try G.addVertex("A");
    const B = try G.addVertex("B");
    const C = try G.addVertex("C");

    try G.connect(A, B, 12);
    try G.connect(B, C, 2);
    try G.connect(A, C, 10);

    const maxFlow = try G.fordFulkerson(A, C);

    try std.testing.expectEqual(12, maxFlow);
}

fn dfsToRun() !Digraph {
    const alloc = std.testing.allocator;
    var G = try Digraph.init(alloc);

    const A = try G.addVertex("A");
    const B = try G.addVertex("B");
    const C = try G.addVertex("C");

    try G.connect(A, B, 12);
    try G.connect(B, C, 2);
    try G.connect(A, C, 10);

    const path = try G.dfsTo(A, C, alloc);
    try std.testing.expect(path != null);
    defer alloc.free(path.?);

    const lastVtx = try G.getVertexById(path.?[path.?.len - 1]);
    try std.testing.expectEqualStrings(
        "C",
        lastVtx.name,
    );

    return G;
}

test "dfsToCheckBuggyInputWorksNow" {
    var G = try dfsToRun();
    G.deinit();
}

test "dfsToAfterGraphUpdate" {
    var G = try dfsToRun();
    defer G.deinit();

    const A = VertexId{ .id = 0 };
    const B = VertexId{ .id = 1 };
    const C = VertexId{ .id = 2 };

    _ = try G.disconnect(B, C);

    try G.connect(C, B, 2);
    try G.connect(B, A, 2);
    try G.connect(A, B, 10);

    const reachable = try G.dfsTo(A, C, G.alloc);

    try std.testing.expect(reachable != null);

    G.alloc.free(reachable.?);
}
