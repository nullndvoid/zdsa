const std = @import("std");
const RingBuffer = @import("RingBuffer.zig").RingBuffer;

const Vertex = struct {
    name: []const u8,
    out: std.AutoArrayHashMap(usize),
    weights: ?std.ArrayList(u32),
    /// The number in which the vertex appears in the list of all vertices.
    idx: u32,
    /// Whether or not the vertex has been removed from the graph.
    dead: bool,
};

const Digraph = struct {
    const Holes = std.PriorityQueue(usize, void, lessThan);

    /// A list of all vertices in G = (V, E). The set of all edges is encapsulated
    /// within the `out` fields of each vertex `v` in V.
    vertices: std.ArrayList(Vertex),
    currentIdx: usize,
    holes: Holes,
    /// A copy of the allocator passed in.
    alloc: std.mem.Allocator,

    fn lessThan(context: void, a: usize, b: usize) std.math.Order {
        _ = context;

        return std.math.order(a, b);
    }

    /// Returns a new directed graph.
    pub fn init(alloc: std.mem.Allocator) !Digraph {
        return Digraph{
            .vertices = std.ArrayList(Vertex).init(alloc),
            .currentIdx = 0,
            .alloc = alloc,
            .holes = null,
        };
    }

    /// Adds a new `Vertex` to the graph, returning a copy to the caller.
    pub fn addVertex(self: *Digraph, name: []const u8) !Vertex {
        var v: Vertex = undefined;

        if (self.holes.removeOrNull()) |hole| {
            v = Vertex.init(name, hole);
            self.vertices.items[hole] = v;
        } else {
            v = Vertex.init(name, self.currentIdx);
            self.currentIdx += 1;
            try self.vertices.append(v);
        }

        return v;
    }

    pub fn removeVertex(self: *Digraph, vertex: *Vertex) void {
        for (self.vertices.items) |*v| {
            v.out.swapRemove(vertex.idx);
        }

        // Now store the index on a queue of holes to be clobbered.
        self.holes.add(vertex.idx);

        // Mark the vertex as dead. If we wanted a count of vertices, we can exclude
        // dead ones or whatever.
        self.vertices.items[vertex.idx].dead = true;
        vertex.dead = true;
    }

    pub fn bfs(self: *Digraph, startVertex: *Vertex) !void {
        // The vertex is probably from another, larger graph.
        if (self.vertices.items.len - 1 <= startVertex.idx or startVertex.dead) {
            return .InvalidVertex;
        }

        // We keep a queue of vertices to check.
        const queue = try RingBuffer(Vertex).initCapacity(
            self.alloc,
            self.vertices.items.len - self.holes.items.len,
        );
        queue.enqueue(startVertex);

        var visited = try std.DynamicBitSet.initEmpty(
            self.alloc,
            self.vertices.items.len - self.holes.items.len,
        );

        while (queue.dequeue()) |v| {
            // Mark as visited and queue the out connections.
            visited.set(v.idx);
            while (v.out.iterator().next()) |w| {
                const vtx = self.vertices.items[w.value_ptr.*];
                if (!visited.isSet(vtx.idx))
                    queue.enqueue(vtx);
            }
        }
    }
};

pub fn main() !void {
    std.debug.print("Hello, world!\n", .{});
}
