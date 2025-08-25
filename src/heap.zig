//! This already exists in the standard library but I want to write one for
//! the practice.

const std = @import("std");
const Allocator = std.mem.Allocator;

const orderU8 = @import("sort.zig").orderU8;

test "heapIsValid" {
    const alloc = std.testing.allocator;

    const slice = try alloc.alloc(u8, 3);
    defer alloc.free(slice);

    slice[0] = 7;
    slice[1] = 2;
    slice[2] = 21;

    const expectedOrder = [_]u8{ 21, 2, 7 };

    const heap = PriorityQueue(u8, orderU8).fromOwnedSlice(alloc, slice);

    try std.testing.expectEqualSlices(u8, &expectedOrder, heap.items.items);
}

/// A minimum or maximum heap depending on the passed `orderFn`.
///
/// # Notes
///
/// This defaults to a Max Heap, so when comparing the first argument with the
/// second argument, we consider the first argument to be greater if the `Order`
/// is `.gt`.
pub fn PriorityQueue(comptime T: type, comptime orderFn: fn (T, T) std.math.Order) type {
    return struct {
        items: std.ArrayList(T),

        const Self = @This();

        pub fn init(alloc: Allocator) Self {
            return Self{ .items = std.ArrayList(T).init(alloc) };
        }

        pub fn fromOwnedSlice(alloc: Allocator, slice: []T) Self {
            _ = alloc;

            var self = Self{ .items = std.ArrayList(T).fromOwnedSlice(slice) };
            if (self.items.items.len == 0) return self;

            var i: isize = @as(isize, @intCast(self.items.items.len / 2)) - 1;
            while (i >= 0) : (i -= 1) {
                self.bubbleDown(@intCast(i));
            }
            return self;
        }

        pub fn deinit(self: *Self) void {
            self.items.deinit();
        }

        // Helper functions (parentIdx, leftIdx, rightIdx) are fine.
        inline fn parentIdx(idx: usize) usize {
            return (idx - 1) / 2;
        }
        inline fn leftIdx(idx: usize) usize {
            return (idx * 2) + 1;
        }
        inline fn rightIdx(idx: usize) usize {
            return (idx * 2) + 2;
        }

        fn swap(self: *Self, idx1: usize, idx2: usize) void {
            const tmp = self.items.items[idx1];
            self.items.items[idx1] = self.items.items[idx2];
            self.items.items[idx2] = tmp;
        }

        // Switched to an iterative bubbleDown for efficiency and to avoid stack limits.
        fn bubbleDown(self: *Self, start_idx: usize) void {
            var current = start_idx;
            const len = self.items.items.len;

            while (leftIdx(current) < len) {
                var best_child_idx = leftIdx(current);
                const right_child_idx = rightIdx(current);

                if (right_child_idx < len and orderFn(self.items.items[right_child_idx], self.items.items[best_child_idx]).compare(.gt)) {
                    best_child_idx = right_child_idx;
                }

                if (orderFn(self.items.items[current], self.items.items[best_child_idx]).compare(.gte)) {
                    // Parent is in the correct place, we are done.
                    return;
                }

                self.swap(current, best_child_idx);
                current = best_child_idx;
            }
        }

        fn bubbleUp(self: *Self, start_idx: usize) void {
            var current = start_idx;
            while (current > 0) {
                const pIdx = parentIdx(current);
                if (orderFn(self.items.items[pIdx], self.items.items[current]).compare(.gte)) {
                    // Child is in the correct place, we are done.
                    return;
                }
                self.swap(current, pIdx);
                current = pIdx;
            }
        }

        pub fn enqueue(self: *Self, key: T) !void {
            try self.items.append(key);
            self.bubbleUp(self.items.items.len - 1);
        }

        pub fn getTopOrNull(self: *const Self) ?T {
            if (self.items.items.len == 0) return null;
            return self.items.items[0];
        }

        pub fn dequeue(self: *Self) ?T {
            if (self.items.items.len == 0) return null;

            const top = self.items.swapRemove(0);

            if (self.items.items.len > 0) {
                self.bubbleDown(0);
            }

            return top;
        }
    };
}
