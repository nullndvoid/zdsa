const std = @import("std");

// Global just to count up as we append nodes. Nodes store their own IDs for internal usage.
var id: usize = 0;

const DirectedGraph = struct {
    alloc: std.mem.Allocator,
    vertices: std.AutoHashMap(usize, Vertex),

    const Vertex = struct {
        out: std.ArrayList(usize),
        len: Length,
        id: usize,
        name: []const u8,

        const Length = union(enum) {
            Infinite,
            Finite: usize,
        };

        pub fn init(alloc: std.mem.Allocator, name: []const u8) Vertex {
            const self = Vertex{
                .out = std.ArrayList(usize).init(alloc),
                .id = id,
                .name = name,
                .len = Length.Infinite,
            };

            id += 1;
            return self;
        }
    };

    /// Creates a new DirectedGraph.
    pub fn init(alloc: std.mem.Allocator) DirectedGraph {
        return DirectedGraph{
            .vertices = std.AutoHashMap(usize, Vertex).init(alloc),
            .alloc = alloc,
        };
    }

    /// Connect two existing vertices. TODO: Return an error type.
    pub fn connect(self: *DirectedGraph, src: *Vertex, dst: *Vertex) !void {
        var srcPtr = try self.vertices.getOrPut(src.id);
        if (!srcPtr.found_existing) {
            return; // TODO: Return an error type!
        }

        // Check for the presence of the destination vertex.
        const dstPtr = self.vertices.get(dst.id);
        if (dstPtr == null) {
            return;
        }

        // Add the new out pointer to the hashmap entry. 'id' equals the key in vertices.
        try srcPtr.value_ptr.out.append(dst.id);
    }

    /// Makes a new vertex and returns a pointer.
    pub fn makeVertex(self: *DirectedGraph, name: []const u8) !*Vertex {
        const idCopy = id;

        _ = try self.vertices.put(id, Vertex.init(self.alloc, name));

        return self.vertices.getPtr(idCopy).?;
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();
    var graph = DirectedGraph.init(alloc);

    const A = try graph.makeVertex("A");
    const B = try graph.makeVertex("B");

    try graph.connect(A, B);

    std.debug.print("{any}\n", .{A});
    std.debug.print("{any}\n", .{B});
}
