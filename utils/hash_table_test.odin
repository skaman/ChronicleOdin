package utils

import "core:mem"
import "core:testing"

@test
test_hash_table :: proc(t: ^testing.T) {
    default_allocator := context.allocator
    tracking_allocator: mem.Tracking_Allocator
    mem.tracking_allocator_init(&tracking_allocator, default_allocator)
    context.allocator = mem.tracking_allocator(&tracking_allocator)

    Test :: struct {
        x: [dynamic]u64,
        y: u32
    }

    test_hash_proc :: proc(key: ^[dynamic]u64) -> u64 {
        h: u64 = 0
        for x in key {
            h += x
        }
        return h
    }

    test_eq_proc :: proc(a, b: ^[dynamic]u64) -> bool {
        if len(a) != len(b) {
            return false
        }
        for i in 0..<len(a) {
            if a[i] != b[i] {
                return false
            }
        }
        return true
    }

    hash_table: Hash_Table(^[dynamic]u64, ^Test)

    // Test initialization
    init_hash_table(&hash_table, test_hash_proc, test_eq_proc)
    testing.expectf(t, hash_table._hash_proc == test_hash_proc, "hash_proc failed: %p", hash_table._hash_proc)
    testing.expectf(t, hash_table._eq_proc == test_eq_proc, "eq_proc failed: %p", hash_table._eq_proc)
    testing.expectf(t, hash_table._data != nil, "data is nil: %p", hash_table._data)
    testing.expect(t, hash_table._capacity == HASH_TABLE_INITIAL_CAPACITY, "capacity is not HASH_TABLE_INITIAL_CAPACITY")
    testing.expect(t, hash_table._count == 0, "count is not 0")

    // Test add_to_hash_table with resize
    for i in 0..<HASH_TABLE_INITIAL_CAPACITY * 2 {
        test := new(Test)
        test.x = make([dynamic]u64, 3)
        test.x[0] = u64(i * i)
        test.x[1] = u64(4)
        test.x[2] = u64(i * i * i)
        test.y = u32(i)
        add_to_hash_table(&hash_table, &test.x, test)

        testing.expectf(t, hash_table._count == u32(i + 1), "count is not correct: %d", hash_table._count)
    }

    // Test get_from_hash_table
    for i in 0..<HASH_TABLE_INITIAL_CAPACITY * 2 {
        key := make([dynamic]u64, 3)
        defer delete(key)
        key[0] = u64(i * i)
        key[1] = u64(4)
        key[2] = u64(i * i * i)
        test := get_from_hash_table(&hash_table, &key)
        testing.expectf(t, test != nil, "get_from_hash_table failed: %p", test)
        testing.expectf(t, test.y == u32(i), "get_from_hash_table failed: %d", test.y)
    }

    // Test remove_from_hash_table
    for i in 0..<HASH_TABLE_INITIAL_CAPACITY * 2 {
        key := make([dynamic]u64, 3)
        defer delete(key)
        key[0] = u64(i * i)
        key[1] = u64(4)
        key[2] = u64(i * i * i)
        value := get_from_hash_table(&hash_table, &key)
        defer delete(value.x)
        defer free(value)
        remove_from_hash_table(&hash_table, &key)
        testing.expectf(t, hash_table._count == u32(HASH_TABLE_INITIAL_CAPACITY * 2 - i - 1), "count is not correct: %d", hash_table._count)
    }

    // Test get_from_hash_table for non-existent key
    {
        key := make([dynamic]u64, 3)
        defer delete(key)
        key[0] = u64(0)
        key[1] = u64(3)
        key[2] = u64(0)
        test := get_from_hash_table(&hash_table, &key)
        testing.expect(t, test == nil, "get_from_hash_table failed")
    }

    // Test destroy_hash_table
    destroy_hash_table(&hash_table)
    testing.expectf(t, hash_table._hash_proc == nil, "hash_proc is not nil: %p", hash_table._hash_proc)
    testing.expectf(t, hash_table._eq_proc == nil, "eq_proc is not nil: %p", hash_table._eq_proc)
    testing.expect(t, hash_table._data == nil, "data is not nil")
    testing.expect(t, hash_table._capacity == 0, "capacity is not 0")
    testing.expect(t, hash_table._count == 0, "count is not 0")

    // Test memory leaks
    have_memory_leak := false
    for _, value in tracking_allocator.allocation_map {
        testing.logf(t, "%v: Leaked %v bytes", value.location, value.size)
        have_memory_leak = true
    }
    testing.expect(t, !have_memory_leak, "Memory leak detected")
}