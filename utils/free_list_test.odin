package utils

import "core:testing"
import "core:mem"
import "core:math"

@test
test_free_list :: proc(t: ^testing.T) {
    default_allocator := context.allocator
    tracking_allocator: mem.Tracking_Allocator
    mem.tracking_allocator_init(&tracking_allocator, default_allocator)
    context.allocator = mem.tracking_allocator(&tracking_allocator)

    fl := Free_List(u64){}

    // Test initialization
    init_free_list(&fl, 10)

    testing.expectf(t, fl.size == 0, "size is not correct: %d", fl.size)
    testing.expectf(t, fl.next_free_index == math.max(u32), "next_free_index is not correct: %d", fl.next_free_index)
    testing.expectf(t, len(fl.data) == 0, "data length is not correct: %d", len(fl.data))

    // Test a bunch of add_to_free_list calls
    for i in 0..<10 {
        index := add_to_free_list(&fl, u64(i))
        testing.expectf(t, index == u32(i), "index is not correct: %d", index)
        testing.expectf(t, fl.size == u32(i + 1), "size is not correct: %d", fl.size)
    }

    // Test a bunch of remove_from_free_list calls
    indexes_to_remove := [3]u32{5, 3, 7}
    expected_sizes := [3]u32{9, 8, 7}
    for i in 0..<3 {
        remove_from_free_list(&fl, indexes_to_remove[i])
        testing.expectf(t, fl.size == expected_sizes[i], "size is not correct: %d", fl.size)
    }

    // Test add_to_free_list after remove_from_free_list
    values_to_add := [4]u64{10, 11, 12, 13}
    expected_indexes := [4]u32{7, 3, 5, 10}
    for i in 0..<4 {
        index := add_to_free_list(&fl, values_to_add[i])
        testing.expectf(t, index == expected_indexes[i], "index is not correct: %d", index)
    }

    // Test get_from_free_list
    expected := [11]u64{0, 1, 2, 11, 4, 12, 6, 10, 8, 9, 13}
    for i in 0..<11 {
        value := get_from_free_list(&fl, u32(i))
        testing.expectf(t, value == expected[i], "value is not correct: %d", value)
    }

    // Test destroy_free_list
    destroy_free_list(&fl)

    testing.expectf(t, fl.size == 0, "size is not correct: %d", fl.size)
    testing.expectf(t, fl.next_free_index == 0, "next_free_index is not correct: %d", fl.next_free_index)
    testing.expectf(t, fl.data == nil, "data length is not correct: %d", len(fl.data))

    // Test memory leaks
    have_memory_leak := false
    for _, value in tracking_allocator.allocation_map {
        testing.logf(t, "%v: Leaked %v bytes", value.location, value.size)
        have_memory_leak = true
    }
    testing.expect(t, !have_memory_leak, "Memory leak detected")    
}