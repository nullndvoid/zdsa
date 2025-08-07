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
