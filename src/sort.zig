//! A collection of sorting algorithms with annotated time complexities etc.
//!
//! I don't like sorting algorithms because I always forget how to write them.

const std = @import("std");

/// Simple sorting function: uses insertion sort for small lists, and merge sort
/// for lists of n > 15.
pub fn sort(comptime T: type, alloc: std.mem.Allocator, list: []T, comparatorFn: fn (lhs: T, rhs: T) std.math.Order) !void {
    if (list.len < 2) return;

    // If small, just insertion sort it.
    if (list.len <= 15) {
        insertionSort(T, list, comparatorFn);
        return;
    }

    try mergeSort(T, comparatorFn).sort(alloc, list);
}

/// Bubble sort. This has an upper bound time complexity of O(n^2).
pub fn bubbleSort(comptime T: type, list: []T, comparatorFn: fn (lhs: T, rhs: T) std.math.Order) void {
    if (list.len < 2) return;
    var swapped = false;

    for (0..list.len - 1) |i| {
        for (0..list.len - 1 - i) |j| {
            const left = list[j];
            const right = list[j + 1];

            const order = comparatorFn(left, right);

            if (order.compare(.gt)) {
                // Swap.
                swapElems(T, list, j, j + 1);
                swapped = true;
            } else {
                swapped = false;
            }
        }

        if (swapped == false) return;
    }
}

/// Insertion sorts a list, has an upper bound O(n^2) time complexity, although
/// this is good for small lists n < 12 or so. Best case is O(n) for a sorted list.
pub fn insertionSort(comptime T: type, list: []T, comparatorFn: fn (lhs: T, rhs: T) std.math.Order) void {
    if (list.len < 2) return;

    for (1..list.len) |i| {
        const key = list[i];

        // `j` will represent the insertion point. It starts at `i`.
        var j = i;

        // Loop while `j` is not at the start of the list to prevent underflow,
        // and the element to the left (`j - 1`) is greater than our key.
        while (j > 0 and comparatorFn(list[j - 1], key) == .gt) {
            // The element to the left is too big, so shift it into the empty slot `j`.
            list[j] = list[j - 1];
            // Move the empty slot one position to the left.
            j -= 1;
        }

        // The loop has finished, so `j` is now the correct insertion point for the key.
        list[j] = key;
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

pub fn quickSort(comptime T: type, comparatorFn: fn (lhs: T, rhs: T) std.math.Order) type {
    return struct {
        rand: std.Random.DefaultPrng,

        const Self = @This();

        pub fn init() !Self {
            const prng = std.Random.DefaultPrng.init(blk: {
                var seed: u64 = undefined;
                try std.posix.getrandom(std.mem.asBytes(&seed));
                break :blk seed;
            });

            return Self{
                .rand = prng,
            };
        }

        pub fn sort(self: *Self, slice: []T) void {
            if (slice.len <= 1) return;
            self.sortRecursive(slice, 0, slice.len - 1);
        }

        fn sortRecursive(self: *Self, slice: []T, left: usize, right: usize) void {
            if (left >= right) return;

            const pivotIdx = self.rand.random().intRangeAtMost(usize, left, right);

            // Partition the array and then call sort on either side.

            const newPivotIdx = self.partition(slice, pivotIdx, left, right);

            if (newPivotIdx > left) {
                self.sortRecursive(slice, left, newPivotIdx - 1);
            }

            self.sortRecursive(slice, newPivotIdx + 1, right);
        }

        /// Partitions the array around a pivot at `pivotIdx`. Entries less
        /// than pivot are placed leftwards, and greater than or equal are
        /// placed at pivotIdx + 1, ..., self.array.len - 1.
        ///
        /// `start`: Starting index for the partition operation.
        /// `end`: Ending index for the partition operation.
        ///
        /// `start` <= `pivotIdx` <= `end`.
        fn partition(self: *Self, slice: []T, pivotIdx: usize, start: usize, end: usize) usize {
            _ = self;

            // Get the pivot out of the way.
            swapElems(T, slice, pivotIdx, start);
            const pivot = slice[start];

            var i: usize = start + 1;
            var j: usize = end;

            while (true) {
                while (i <= end and comparatorFn(slice[i], pivot).compare(.lte)) {
                    i += 1;
                }

                while (j > start and comparatorFn(slice[j], pivot).compare(.gt)) {
                    j -= 1;
                }

                if (i >= j) break;

                swapElems(T, slice, i, j);
                i += 1;
                j -= 1;
            }

            swapElems(T, slice, start, j);

            return j;
        }
    };
}

/// Just a wrapper for sorting lists of u8 in ascending order.
pub fn orderU8(lhs: u8, rhs: u8) std.math.Order {
    return std.math.order(lhs, rhs);
}

pub fn reverseOrderU8(lhs: u8, rhs: u8) std.math.Order {
    return std.math.order(rhs, lhs);
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

test "quickSortOneElement" {
    const expected = [_]u8{1};
    var toSort = [_]u8{1};

    var sorter = try quickSort(u8, orderU8).init();

    sorter.sort(toSort[0..]);

    try std.testing.expectEqualSlices(u8, &expected, &toSort);
}

test "quickSortReverseOrderedList" {
    const expected = [_]u8{ 1, 2, 4, 7, 9, 10, 12 };
    var toSort = [_]u8{ 12, 10, 9, 7, 4, 2, 1 };

    var sorter = try quickSort(u8, orderU8).init();

    sorter.sort(toSort[0..]);

    try std.testing.expectEqualSlices(u8, &expected, &toSort);
}

test "sortReverseOrderedList" {
    const expected = [_]u8{ 1, 4, 5, 6, 7, 8, 9, 10, 14, 15, 19, 21, 102, 204, 205, 231 };
    var toSort = [_]u8{ 231, 205, 204, 102, 21, 19, 15, 14, 10, 9, 8, 7, 6, 5, 4, 1 };

    const alloc = std.testing.allocator;

    try sort(u8, alloc, toSort[0..], orderU8);
    try std.testing.expectEqualSlices(u8, &expected, &toSort);
}

test "reverseSort" {
    var toSort = [_]u8{ 1, 4, 5, 6, 7, 8, 9, 10, 14, 15, 19, 21, 102, 204, 205, 231 };
    const expected = [_]u8{ 231, 205, 204, 102, 21, 19, 15, 14, 10, 9, 8, 7, 6, 5, 4, 1 };

    const alloc = std.testing.allocator;

    try sort(u8, alloc, toSort[0..], reverseOrderU8);
    try std.testing.expectEqualSlices(u8, &expected, &toSort);
}
