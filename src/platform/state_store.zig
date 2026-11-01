//! Host-owned Type-Hashed Key-Value Store (`useState` + scopes) and Reload-Boundary JSON Buffer.
//!
//! Safely crosses the `.dylib` C-ABI boundary without storing `.dylib` function pointers or
//! `.rodata` string slices in persistent host memory:
//!   1. **Host KV Store (`StateStore`)**: React Fast Refresh-style `useState(T, key, default)`
//!      with hierarchical `pushScope` / `popScope` ID stack. Validates compile-time type + field
//!      layout hashes on access; automatically frees and re-initializes only the modified key
//!      if `T`'s struct layout changes across a hot-reload.
//!   2. **Reload-Boundary Snapshot Buffer (`SnapshotBuffer`)**: Stores serialized JSON bytes in
//!      host-owned heap memory across `app_before_reload` -> `dlclose` -> `dlopen` -> `app_after_reload`,
//!      allowing structured global state to survive arbitrary field additions/removals.

const std = @import("std");

pub const StateEntry = struct {
    ptr: [*]u8,
    size: usize,
    alignment: u8,
    type_hash: u64,
};

/// Host-owned persistent Key-Value store for component-scoped `useState` hooks.
pub const StateStore = struct {
    allocator: std.mem.Allocator,
    map: std.AutoHashMapUnmanaged(u64, StateEntry) = .empty,
    scope_stack: [32]u64 = @splat(0),
    scope_len: usize = 0,

    pub fn init(allocator: std.mem.Allocator) StateStore {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *StateStore) void {
        var it = self.map.valueIterator();
        while (it.next()) |entry| {
            const slice = entry.ptr[0..entry.size];
            self.allocator.rawFree(slice, @enumFromInt(entry.alignment), @returnAddress());
        }
        self.map.deinit(self.allocator);
        self.scope_len = 0;
    }

    pub fn resetScopes(self: *StateStore) void {
        self.scope_len = 0;
    }

    pub fn currentScopeId(self: *const StateStore) u64 {
        return if (self.scope_len > 0) self.scope_stack[self.scope_len - 1] else 0;
    }

    pub fn pushScope(self: *StateStore, scope_name: []const u8) void {
        const parent = self.currentScopeId();
        const next_id = std.hash.Wyhash.hash(parent, scope_name);
        std.debug.assert(self.scope_len < self.scope_stack.len);
        self.scope_stack[self.scope_len] = next_id;
        self.scope_len += 1;
    }

    pub fn popScope(self: *StateStore) void {
        if (self.scope_len > 0) {
            self.scope_len -= 1;
        }
    }

    /// Looks up or allocates a state slot of `(size, alignment, type_hash)` under `(currentScopeId, key)`.
    /// Sets `initialized_out.* = true` if the existing slot matched `type_hash` and `size`,
    /// or `false` if a fresh allocation was created (or re-allocated after a type change).
    pub fn getOrAllocRaw(
        self: *StateStore,
        key: []const u8,
        size: usize,
        alignment_log2: u8,
        type_hash: u64,
        initialized_out: *bool,
    ) [*]u8 {
        const full_key = std.hash.Wyhash.hash(self.currentScopeId(), key);

        if (self.map.getPtr(full_key)) |entry| {
            if (entry.type_hash == type_hash and entry.size == size and entry.alignment == alignment_log2) {
                initialized_out.* = true;
                return entry.ptr;
            }
            // Type signature or size changed across hot-reload! Free old memory and re-allocate.
            const old_slice = entry.ptr[0..entry.size];
            self.allocator.rawFree(old_slice, @enumFromInt(entry.alignment), @returnAddress());
        }

        const raw_ptr = self.allocator.rawAlloc(size, @enumFromInt(alignment_log2), @returnAddress()) orelse
            @panic("OOM in StateStore.getOrAllocRaw");

        self.map.put(self.allocator, full_key, .{
            .ptr = raw_ptr,
            .size = size,
            .alignment = alignment_log2,
            .type_hash = type_hash,
        }) catch @panic("OOM in StateStore.map.put");

        initialized_out.* = false;
        return raw_ptr;
    }

    /// Removes a key from the current scope if present.
    pub fn remove(self: *StateStore, key: []const u8) bool {
        const full_key = std.hash.Wyhash.hash(self.currentScopeId(), key);
        if (self.map.fetchRemove(full_key)) |kv| {
            const slice = kv.value.ptr[0..kv.value.size];
            self.allocator.rawFree(slice, @enumFromInt(kv.value.alignment), @returnAddress());
            return true;
        }
        return false;
    }

    pub fn count(self: *const StateStore) usize {
        return self.map.count();
    }
};

/// Host-owned byte buffer for Reload-Boundary JSON Serialization (`onBeforeReload` / `onAfterReload`).
pub const SnapshotBuffer = struct {
    allocator: std.mem.Allocator,
    bytes: ?[]u8 = null,

    pub fn init(allocator: std.mem.Allocator) SnapshotBuffer {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *SnapshotBuffer) void {
        if (self.bytes) |b| {
            self.allocator.free(b);
            self.bytes = null;
        }
    }

    pub fn write(self: *SnapshotBuffer, data: []const u8) void {
        if (self.bytes) |old| {
            self.allocator.free(old);
            self.bytes = null;
        }
        if (data.len == 0) return;
        const copy = self.allocator.dupe(u8, data) catch return;
        self.bytes = copy;
    }

    pub fn slice(self: *const SnapshotBuffer) []const u8 {
        return self.bytes orelse &.{};
    }
};

/// Fixed-capacity UTF-8 string value safe to store inside `useState` or global state structs
/// without risking `.rodata` string literal segfaults when old `.dylib` images are `dlclose`d.
pub fn InlineString(comptime capacity: usize) type {
    return struct {
        const Self = @This();
        pub const Capacity = capacity;

        buf: [capacity]u8 = @splat(0),
        len: usize = 0,

        pub fn init(str: []const u8) Self {
            var s = Self{};
            s.set(str);
            return s;
        }

        pub fn set(self: *Self, str: []const u8) void {
            const n = @min(str.len, capacity);
            @memcpy(self.buf[0..n], str[0..n]);
            self.len = n;
        }

        pub fn appendSlice(self: *Self, str: []const u8) void {
            const cur = @min(self.len, capacity);
            const avail = capacity - cur;
            const n = @min(str.len, avail);
            if (n > 0) {
                @memcpy(self.buf[cur .. cur + n], str[0..n]);
                self.len = cur + n;
            }
        }

        pub fn clear(self: *Self) void {
            self.len = 0;
        }

        pub fn slice(self: *const Self) []const u8 {
            return self.buf[0..@min(self.len, capacity)];
        }

        pub fn trim(self: *const Self, chars: []const u8) []const u8 {
            return std.mem.trim(u8, self.slice(), chars);
        }

        pub fn isEmpty(self: *const Self) bool {
            return self.len == 0;
        }

        pub fn eql(self: *const Self, other: []const u8) bool {
            return std.mem.eql(u8, self.slice(), other);
        }
    };
}

/// Generates a compile-time hash of `T`'s type name, size, alignment, and struct/enum/union fields.
/// Recursive up to depth 4 so nested structs also invalidate cleanly when modified.
pub fn computeTypeHash(comptime T: type) u64 {
    return comptime blk: {
        @setEvalBranchQuota(50_000);
        break :blk computeTypeHashDepth(T, 0);
    };
}

fn computeTypeHashDepth(comptime T: type, comptime depth: usize) u64 {
    comptime {
        var hasher = std.hash.Wyhash.init(0);
        hasher.update(@typeName(T));
        const sz: usize = @sizeOf(T);
        const al: usize = @alignOf(T);
        hasher.update(std.mem.asBytes(&sz));
        hasher.update(std.mem.asBytes(&al));

        if (depth < 4) {
            switch (@typeInfo(T)) {
                .@"struct" => |info| {
                    for (info.field_names, info.field_types) |fname, FType| {
                        hasher.update(fname);
                        const field_hash = computeTypeHashDepth(FType, depth + 1);
                        hasher.update(std.mem.asBytes(&field_hash));
                    }
                },
                .@"enum" => |info| {
                    for (info.field_names, info.field_values) |fname, fval| {
                        hasher.update(fname);
                        const val: i128 = @intCast(fval);
                        hasher.update(std.mem.asBytes(&val));
                    }
                },
                .@"union" => |info| {
                    for (info.field_names, info.field_types) |fname, FType| {
                        hasher.update(fname);
                        const field_hash = computeTypeHashDepth(FType, depth + 1);
                        hasher.update(std.mem.asBytes(&field_hash));
                    }
                },
                else => {},
            }
        }
        const final = hasher.final();
        return if (final == 0) 1 else final;
    }
}

test "StateStore useState, scopes, and automatic type-evolution re-initialization" {
    var store = StateStore.init(std.testing.allocator);
    defer store.deinit();

    const Hooks = struct {
        fn useState(s: *StateStore, comptime T: type, key: []const u8, default: T) *T {
            var initialized = false;
            const raw = s.getOrAllocRaw(
                key,
                @sizeOf(T),
                @ctz(@as(usize, @alignOf(T))),
                comptime computeTypeHash(T),
                &initialized,
            );
            const typed: *T = @ptrCast(@alignCast(raw));
            if (!initialized) {
                typed.* = default;
            }
            return typed;
        }
    };

    // 1. Allocate state and mutate it
    const counter = Hooks.useState(&store, i32, "count", 10);
    try std.testing.expectEqual(@as(i32, 10), counter.*);
    counter.* = 42;

    // 2. Subsequent access with same key & type returns existing pointer and value
    const counter_again = Hooks.useState(&store, i32, "count", 10);
    try std.testing.expectEqual(@as(i32, 42), counter_again.*);

    // 3. Scoped state with identical key name does not collide with root scope
    store.pushScope("sidebar");
    const scoped_counter = Hooks.useState(&store, i32, "count", 99);
    try std.testing.expectEqual(@as(i32, 99), scoped_counter.*);
    scoped_counter.* = 100;
    store.popScope();

    try std.testing.expectEqual(@as(i32, 42), Hooks.useState(&store, i32, "count", 10).*);

    // 4. Simulate struct change across hot-reload on the same key ("panel_cfg"):
    const ConfigV1 = struct {
        speed: f32 = 1.0,
        rings: u32 = 4,
    };
    const ConfigV2 = struct {
        speed: f32 = 1.0,
        rings: u32 = 4,
        new_field: bool = true,
    };

    const cfg_v1 = Hooks.useState(&store, ConfigV1, "panel_cfg", .{ .speed = 2.5, .rings = 6 });
    try std.testing.expectEqual(@as(f32, 2.5), cfg_v1.speed);

    // Accessing "panel_cfg" with ConfigV2 detects the type hash mismatch, frees ConfigV1, and initializes ConfigV2
    const cfg_v2 = Hooks.useState(&store, ConfigV2, "panel_cfg", .{});
    try std.testing.expectEqual(@as(f32, 1.0), cfg_v2.speed);
    try std.testing.expect(cfg_v2.new_field);
}
