//! A collection of sorting algorithms with annotated time complexities etc.
//!
//! I don't like sorting algorithms because I always forget how to write them.

const std = @import("std");

/// Bubble sort. This has an upper bound time complexity of O(n^2).
pub fn bubbleSort(comptime T: type, list: []T, comparatorFn: fn (lhs: T, rhs: T) std.math.Order) void {
    for (0..list.len - 1) |_| {
        for (0..list.len - 1) |j| {
            const left = list[j];
            const right = list[j + 1];

            const order = comparatorFn(left, right);

            if (order.compare(.gt)) {
                // Swap.
                swapElems(T, list, j, j + 1);
            }
        }
    }
}

/// Insertion sorts a list, has an upper bound O(n^2) time complexity, although
/// this is good for small lists n < 12 or so.
pub fn insertionSort(comptime T: type, list: []T, comparatorFn: fn (lhs: T, rhs: T) std.math.Order) void {
    for (0..list.len - 1) |i| {
        var insertAt = i + 1;
        var needsSwap = false;

        for (i + 1..list.len) |j| {
            const left = list[i];
            const right = list[j];

            const order = comparatorFn(left, right);

            if (order.compare(.gt)) {
                insertAt = j;
                needsSwap = true;
                continue;
            }
        }

        if (needsSwap) swapElems(T, list, i, insertAt);
    }
}

/// Weird generic wrapper around Merge Sort since I didn't like having long
/// function prototypes for users.
///
/// ```zig
/// try mergeSort(u8, std.math.order).sort(alloc, list); // And boom, your list is sorted.
/// ```
///
/// # Computational Complexity
///
/// The `sort` function should run in O(nlogn) time. TODO: Prove this is true.
pub fn mergeSort(comptime T: type, comparatorFn: fn (lhs: T, rhs: T) std.math.Order) type {
    return struct {
        alloc: std.mem.Allocator,

        const Self = @This();

        /// Sorts `list` in place.
        pub fn sort(alloc: std.mem.Allocator, list: []T) !void {
            // No-op for small lists.
            if (list.len <= 1) {
                return;
            }

            var self = Self{ .alloc = alloc };

            // 1. Allocate a single temporary buffer for the entire operation.
            const temp = try alloc.alloc(T, list.len);
            defer alloc.free(temp);
            @memcpy(temp, list);

            // 2. Start the recursive sort.
            // The initial source is `list`, and the destination is `temp`.
            try self.mergeSortRecursive(temp, list, 0, list.len);
        }

        // Recursive helper that sorts from a source buffer into a destination buffer.
        fn mergeSortRecursive(self: *Self, source: []T, dest: []T, start: usize, end: usize) !void {
            const len = end - start;
            if (len <= 1) {
                return;
            }

            const mid = start + (len / 2);

            // Note the swap: recurse from `dest` back into `source`.
            try self.mergeSortRecursive(dest, source, start, mid);
            try self.mergeSortRecursive(dest, source, mid, end);

            // Now merge the sorted halves from `source` into `dest`.
            try self.merge(source, dest, start, mid, end);
        }

        /// Merges two sorted sub-ranges from a source slice into a destination slice.
        /// The sorted ranges are `source[start..mid]` and `source[mid..end]`.
        /// The result is written to `dest[start..end]`.
        fn merge(self: *Self, source: []T, dest: []T, start: usize, mid: usize, end: usize) !void {
            _ = self;

            var i = start; // Pointer for the left half
            var j = mid; // Pointer for the right half
            var k = start; // Pointer for the destination slice

            while (i < mid and j < end) {
                if (comparatorFn(source[i], source[j]) != .gt) {
                    dest[k] = source[i];
                    i += 1;
                } else {
                    dest[k] = source[j];
                    j += 1;
                }
                k += 1;
            }

            // Copy any remaining elements from the left half.
            while (i < mid) {
                dest[k] = source[i];
                i += 1;
                k += 1;
            }

            // Copy any remaining elements from the right half.
            while (j < end) {
                dest[k] = source[j];
                j += 1;
                k += 1;
            }
        }
    };
}

/// Just a wrapper for sorting lists of u8 in ascending order.
pub fn orderU8(lhs: u8, rhs: u8) std.math.Order {
    return std.math.order(lhs, rhs);
}

/// Swaps two elements in a list.
pub inline fn swapElems(comptime T: type, list: []T, firstIdx: usize, secondIdx: usize) void {
    const tmp = list[firstIdx];
    list[firstIdx] = list[secondIdx];
    list[secondIdx] = tmp;
}

test "bubbleSortReverseOrderedList" {
    const expected = [_]u8{ 1, 2, 3, 6, 9, 10, 21 };
    var toSort = [_]u8{ 21, 10, 9, 6, 3, 2, 1 };

    bubbleSort(u8, toSort[0..], orderU8);

    try std.testing.expectEqualSlices(u8, &expected, &toSort);
}

test "insertionSortReverseOrderedList" {
    const expected = [_]u8{ 1, 2, 3, 6, 9, 10, 21 };
    var toSort = [_]u8{ 21, 10, 9, 6, 3, 2, 1 };

    insertionSort(u8, toSort[0..], orderU8);

    try std.testing.expectEqualSlices(u8, &expected, &toSort);
}

test "insertionSortOneElement" {
    const expected = [_]u8{1};
    var toSort = [_]u8{1};

    insertionSort(u8, toSort[0..], orderU8);

    try std.testing.expectEqualSlices(u8, &expected, &toSort);
}

test "mergeSortReverseOrderedList" {
    const expected = [_]u8{ 1, 2, 3, 6, 9, 10, 21 };
    var toSort = [_]u8{ 21, 10, 9, 6, 3, 2, 1 };

    const alloc = std.testing.allocator;

    try mergeSort(u8, orderU8).sort(alloc, toSort[0..]);
    try std.testing.expectEqualSlices(u8, &expected, &toSort);
}

test "mergeSortOneElement" {
    const expected = [_]u8{1};
    var toSort = [_]u8{1};

    const alloc = std.testing.allocator;

    try mergeSort(u8, orderU8).sort(alloc, toSort[0..]);
    try std.testing.expectEqualSlices(u8, &expected, &toSort);
}
