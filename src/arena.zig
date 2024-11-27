const std = @import("std");

const EntryType = enum {
    empty,
    occupied,
};

const FreeSlot = struct {
    generation: u32,
    next: ?u32,
};

fn Entry(comptime T: type) type {
    return struct {
        generation: u32,
        value: T,
    };
}

// Helper type to get the handle for an arena.
pub fn Handle(comptime T: type) type {
    return Arena(T).Handle;
}

pub fn Arena(comptime T: type) type {
    const Slot = union(EntryType) { empty: FreeSlot, occupied: Entry(T) };

    return struct {
        pub const ValidItemsIterator = struct {
            arena: *Arena(T),
            index: u32 = 0,
            
            pub fn nextPtr(self: *ValidItemsIterator) ?*T {
                const index = self.index;
                if (index < 0 or index >= self.arena.len) return null;

                while (self.index < self.arena.len) {
                    var slot = self.arena.entries.items[self.index];
                    switch(slot) {
                        .occupied => |*val| {
                            self.index += 1;
                            return &val.value;
                        },
                        .empty => {
                            self.index += 1;
                        },
                    }
                }

                return null;
            }

            pub fn next(self: *ValidItemsIterator) ?T {
                const index = self.index;
                if (index < 0 or index >= self.arena.len) return null;

                while (self.index < self.arena.len) {
                    const slot = self.arena.entries.items[self.index];
                    switch(slot) {
                        .occupied => |val| {
                            self.index += 1;
                            return val.value;
                        },
                        .empty => {
                            self.index += 1;
                        },
                    }
                }

                return null;
            }
        };

        pub const Handle = struct {
            generation: u32 = 0,
            index: u32 = 0,

            pub const invalid = Arena(T).Handle { .generation = 0, .index = 0 };

            pub fn is_valid(self: Arena(T).Handle) bool { return self.generation != 0; }
        };

        len: u32,
        entries: std.ArrayList(Slot),
        free_list: ?u32,
        num_items: u32,

        pub fn create(allocator: std.mem.Allocator, size: u32) !Arena(T) {
            return Arena(T){
                .len = 0,
                .entries = try std.ArrayList(Slot).initCapacity(allocator, size),
                .free_list = null,
                .num_items = 0,
            };
        }

        pub fn deinit(self: *Arena(T)) void {
            self.entries.clearAndFree();
        }

        pub fn capacity(self: Arena(T)) u32 {
            return @intCast(self.entries.capacity);
        }

        pub fn get(self: Arena(T), handle: Arena(T).Handle) !T {
            const idx = handle.index;
            if (idx >= self.len) return error.OutOfRange;
            return switch (self.entries.items[idx]) {
                .empty => error.Invalidated,
                .occupied => |val| blk: {
                    if (val.generation > handle.generation) break :blk error.Invalidated;
                    break :blk val.value;
                },
            };
        }

        pub fn getPtr(self: Arena(T), handle: Arena(T).Handle) !*T {
            const idx = handle.index;
            if (idx >= self.len) return error.OutOfRange;
            return switch (self.entries.items[idx]) {
                .empty => error.Invalidated,
                .occupied => |*val| blk: {
                    if (val.generation > handle.generation) break :blk error.Invalidated;
                    break :blk &val.value;
                },
            };
            
        }

        pub fn at(self: Arena(T), idx: u32) !*T {
            if (idx >= self.len) return error.OutOfRange;
            return switch (self.entries.items[idx]) {
                .empty => error.Invalidated,
                .occupied => |val| val.value,
            };
        }

        pub fn handle_at(self: Arena(T), idx: u32) !Arena(T).Handle {
            return switch (self.entries.items[idx]) {
                .empty => error.Invalidated,
                .occupied => |val| .{ .index = idx, .generation = val.generation },
            };
        }

        pub fn iterator(self: *Arena(T)) ValidItemsIterator {
            return ValidItemsIterator {
                .arena = self,
                .index = 0,
            };
        }

        pub fn insert(self: *Arena(T), value: T) !Arena(T).Handle {
            if (self.free_list != null) {
                const idx = self.free_list.?;
                const slot = &self.entries.items[idx];
                const gen = slot.empty.generation;

                self.free_list = slot.empty.next;
                slot.* = .{ .occupied = .{ .generation = gen, .value = value } };
                self.num_items += 1;

                return .{ .index = idx, .generation = gen };
            } else {
                const index = self.len;
                if (index >= self.capacity()) {
                    const new_cap = @max(self.capacity() * 2, 1);
                    try self.resize(new_cap);
                    return self.insert(value);
                }


                try self.entries.insert(index, .{ .occupied = .{
                    .generation = 1,
                    .value = value,
                } });

                self.len += 1;
                self.num_items += 1;

                return .{
                    .index = index,
                    .generation = 1,
                };
            }
        }

        pub fn release(self: *Arena(T), handle: Arena(T).Handle) void {
            const idx = handle.index;
            if (idx >= self.len) return;
            const slot = &self.entries.items[idx];
            const val: ?T = switch (self.entries.items[idx]) {
                .empty => null,
                .occupied => |entry| blk: {
                    slot.* = .{ .empty = .{
                        .generation = entry.generation + 1,
                        .next = self.free_list,
                    } };
                    self.free_list = idx;
                    break :blk entry.value;
                },
            };
            if (val != null) {
                self.num_items -= 1;
                return;
            }
        }

        pub fn resize(self: *Arena(T), new_cap: u32) !void {
            if (new_cap > std.math.maxInt(u32)) return error.OutOfMemory;
            try self.entries.resize(new_cap);
        }
    };
}

test "hyarena-alloc-free" {
    var g = try Arena(u32).create(std.testing.allocator, 20);
    defer g.deinit();
    try std.testing.expect(g.entries.capacity == 20);
}

test "hyarena-insert" {
    var g = try Arena(u32).create(std.testing.allocator, 20);
    defer g.deinit();
    try std.testing.expectError(error.OutOfRange, g.get(.{ .index = 0, .generation = 0 }));
    const id = try g.insert(37);
    const id2 = try g.insert(42);
    try std.testing.expect(try g.get(id) == 37);
    try std.testing.expect(try g.get(id2) == 42);
}

test "hyarena-invalidate" {
    var g = try Arena(u32).create(std.testing.allocator, 20);
    defer g.deinit();
    const id = try g.insert(37);
    try std.testing.expect(try g.get(id) == 37);
    const val = g.release(id);
    try std.testing.expect(val == 37);
    try std.testing.expectError(error.Invalidated, g.get(id));

    const new_id = try g.insert(24);
    try std.testing.expect(try g.get(new_id) == 24);
    try std.testing.expectError(error.Invalidated, g.get(id));
    try std.testing.expect(id.index == new_id.index);
}
