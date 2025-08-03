const std = @import("std");

const Allocator = std.mem.Allocator;

pub fn RingBuffer(comptime T: type) type {
    return struct {
        const Self = @This();
        const Iterator = struct {
            target: *Self,

            direction: enum { forward, backward },
            index: usize,

            pub fn next(self: *Iterator) ?*T {
                if (self.index >= self.target.len()) return null;

                const real_index = if (self.direction == .forward) self.index else self.target.len() - 1 - self.index;
                if (self.target.get(real_index)) |item| {
                    self.index += 1;
                    return item;
                }

                return null;
            }
        };

        allocator: Allocator,

        buffer: []T = &[_]T{},

        head: usize = 0,
        tail: usize = 0,
        _len: usize = 0,

        /// Initialize a new buffer, no allocations are made until a `push*` method is called
        pub fn init(allocator: Allocator) Self {
            return .{ .allocator = allocator };
        }

        /// Initialize a new buffer that will be able to hold at least `num` items before allocating.
        pub fn initCapacity(allocator: Allocator, num: usize) !Self {
            var new = Self.init(allocator);
            try new.ensureTotalCapacityPrecise(num);
            return new;
        }

        /// Get the number of items that this buffer can hold before a reallocation is made.
        pub fn capacity(self: *const Self) usize {
            return self.buffer.len;
        }

        /// Get the numbers of items the buffer currently holds
        pub fn len(self: *const Self) usize {
            return self._len;
        }

        /// Reset without freeing memory
        pub fn clearRetainingCapacity(self: *Self) void {
            self._len = 0;
            self.head = 0;
            self.tail = 0;
        }

        /// Reset all internal fields and free the buffer.
        pub fn deinit(self: *Self) void {
            self.clearRetainingCapacity();

            if (self.capacity() > 0) {
                self.allocator.free(self.buffer);
                self.buffer.len = 0;
            }
        }

        /// Ensure the internal buffer can hold at least `needed` more elements, and reallocate if it can't.
        pub fn ensureUnusedCapacity(self: *Self, needed: usize) !void {
            return self.ensureTotalCapacity(self.capacity() + needed);
        }

        /// Grow the internal buffer to hold at least `target_capacity`
        pub fn ensureTotalCapacity(self: *Self, target_capacity: usize) !void {
            // Using the same algorithm for finding a better capacity as std.ArrayList (as of zig v0.9.0)
            if (target_capacity < self.capacity()) return;

            var better_capacity = self.capacity();
            while (true) {
                better_capacity += better_capacity / 2 + 8;
                if (better_capacity >= target_capacity) break;
            }

            return self.ensureTotalCapacityPrecise(better_capacity);
        }

        /// Grow the internal buffer to hold as close to `new_capacity` items as possible.
        /// It may hold more depending on the allocators realloc implementation
        pub fn ensureTotalCapacityPrecise(self: *Self, new_capacity: usize) !void {
            const old_capacity = self.capacity();
            if (old_capacity >= new_capacity) return;

            const new_buffer = try self.allocator.reallocAtLeast(self.buffer, new_capacity);
            self.buffer = new_buffer;

            // The buffer can be in three possible states
            // 1) The head is at the end of the buffer
            // 2) The head is closer to the start than the tail is to the end
            // 3) The tail is closer to the end than the head is to the start

            // Nothing needs to be done for case 1),
            // it means the buffer looks similar to a normal array
            if (self.tail < self.head) return;

            if (self.head < old_capacity - self.tail) { // case 2)
                // unwrap the head, moving after the tail
                if (self.head > 0)
                    std.mem.copy(T, self.buffer[old_capacity..], self.buffer[0..self.head]);

                self.head = old_capacity + self.head;
            } else if (self.head > old_capacity - self.tail) { // case 3)
                // shift the tail to the end of the array

                const new_tail = new_capacity - (old_capacity - self.tail);
                std.mem.copy(T, self.buffer[new_tail..], self.buffer[self.tail..old_capacity]);

                self.tail = new_tail;
            }
        }

        /// Add an item at the end of the buffer
        pub fn pushBack(self: *Self, item: T) !void {
            if (self.len() == self.capacity()) try self.ensureUnusedCapacity(1);

            self.buffer[self.head] = item;
            self.head = (self.head + 1) % self.capacity();
            self._len += 1;
        }

        /// Remove the last item in the buffer, or null if its empty
        pub fn popBack(self: *Self) ?T {
            if (self.len() == 0) return null;

            if (self.head == 0) self.head = self.capacity();
            self.head -= 1;
            self._len -= 1;

            return self.buffer[self.head];
        }

        /// Add an item at the start of the buffer
        pub fn pushFront(self: *Self, item: T) !void {
            if (self.len() == self.capacity()) try self.ensureUnusedCapacity(1);

            if (self.tail == 0) self.tail = self.capacity();
            self.tail -= 1;
            self._len += 1;

            self.buffer[self.tail] = item;
        }

        /// Remove the first item in the buffer, or null if its empty
        pub fn popFront(self: *Self) ?T {
            if (self.len() == 0) return null;

            const data = self.buffer[self.tail];

            self.tail = (self.tail + 1) % self.capacity();
            self._len -= 1;

            return data;
        }

        /// Get an item by index from the buffer
        pub fn get(self: *Self, i: usize) ?*T {
            if (i >= self.len()) return null;

            return &self.buffer[(self.tail + i) % self.capacity()];
        }

        /// Returns a new `Iterator` instance, for easy use with a while loop
        pub fn iter(self: *Self) Iterator {
            return .{
                .direction = .forward,

                .target = self,
                .index = 0,
            };
        }

        /// Same as `iter()` but iterates backwards from the end of a buffer
        pub fn iterReverse(self: *Self) Iterator {
            return .{
                .direction = .backward,

                .target = self,
                .index = 0,
            };
        }
    };
}
