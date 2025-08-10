const std = @import("std");

pub const CollisionRecovery = enum { direct_chaining, linear_probing, double_hashing };

pub const HashMapConfig = struct {
    /// What method should be used to recover from hash collisions.
    collision_recovery: CollisionRecovery = .direct_chaining,
};

pub fn HashMap(comptime T: type, config: HashMapConfig) type {

    // We need a wrapper for items of type T.
    const ItemLinkedListWrapper = struct {
        /// Used for returning the correct values when a lookup returns a linked list.
        keyString: []const u8,
        self: T,
        _next: ?std.SinglyLinkedList.Node,

        const Self = @This();

        pub fn init(keyString: []const u8, val: T) Self {
            return Self{
                .keyString = keyString,
                .self = val,
                ._next = null,
            };
        }

        pub fn next(self: Self) ?*Self {
            if (self._next == null) return null;
            const maybeNode = self._next.next;
            if (maybeNode == null) return null;
            const nextNode = maybeNode.?;
            const nextT: *T = @fieldParentPtr("_next", nextNode);

            return nextT;
        }
    };

    // Tagged enum for reading entries when using direct chaining for collision recovery.
    const ItemOrLinkedList = union(enum) { item: T, linkedList: std.SinglyLinkedList };

    return struct {
        items: std.ArrayList(ItemOrLinkedList),
        alloc: std.mem.Allocator,
        config: HashMapConfig,

        const Self = @This();

        /// Returns a `HashMap`.
        pub fn init(alloc: std.mem.Allocator) Self {
            return Self{
                .config = config,
                .alloc = alloc,
                .items = std.ArrayList(ItemOrLinkedList).init(alloc),
            };
        }

        /// Inserts the offending (k, v) into a Linked List at the given index.
        fn directChainingCollisionHandler(self: *Self, key: []const u8, val: T) !void {
            const idx = hash()
        }
    };
}
:
