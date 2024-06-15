package utils

import "core:mem"
import "core:math"
import "core:testing"
import "core:fmt"

FREE_LIST_INITIAL_CAPACITY :: 16

// Free_List is a type that represents a free list data structure.
Free_List :: struct($Type: typeid) {
    data: [dynamic]Type,  // The underlying data array.
    next_free_index: u32, // The index of the next free element in the data array.
    size: u32             // The number of elements in the data array.
}

// Initializes a Free_List instance with the specified capacity.
//
// Parameters:
//   fl: ^Free_List - A pointer to the Free_List instance to initialize.
//   capacity: u32 - The initial capacity of the Free_List data array.
//   allocator: mem.Allocator - The allocator to use for memory allocation.
init_free_list :: proc (fl: ^Free_List($Type), capacity: u32 = FREE_LIST_INITIAL_CAPACITY, allocator: mem.Allocator = context.allocator) {
    #assert(size_of(Type) >= size_of(u32), "Type size must be greater than u32 size")

    assert(fl != nil, "Free_List pointer is nil")
    assert(fl.data == nil, "Free_List data is not nil")
    assert(fl.next_free_index == 0, "Free_List next_free_index is not 0")
    assert(fl.size == 0, "Free_List size is not 0")

    assert(capacity > 0, "Capacity must be greater than 0")

    fl.data = make([dynamic]Type, 0, capacity, allocator)
    fl.next_free_index = math.max(u32)
    fl.size = 0
}

// Destroys a Free_List instance and frees the associated memory.
//
// Parameters:
//   fl: ^Free_List - A pointer to the Free_List instance to destroy.
destroy_free_list :: proc (fl: ^Free_List($Type)) {
    assert(fl != nil, "Free_List pointer is nil")
    assert(fl.data != nil, "Free_List data is nil")

    delete(fl.data)

    fl^ = {}
}

// Adds a value to the Free_List data array.
//
// Parameters:
//   fl: ^Free_List - A pointer to the Free_List instance.
//   value: Type - The value to add to the Free_List data array.
//
// Returns:
//   u32 - The index of the added value in the Free_List data array.
@require_results
add_to_free_list :: proc (fl: ^Free_List($Type), value: Type) -> u32 {
    assert(fl != nil, "Free_List pointer is nil")
    assert(fl.data != nil, "Free_List data is nil")

    index : u32
    if fl.next_free_index == math.max(u32) {
        index = u32(len(fl.data))
        append(&fl.data, value)
    }
    else {
        index = fl.next_free_index
        fl.next_free_index = (^u32)(&fl.data[index])^
        fl.data[index] = value
    }

    fl.size += 1

    return index
}

// Removes a value from the Free_List data array.
//
// Parameters:
//   fl: ^Free_List - A pointer to the Free_List instance.
//   index: u32 - The index of the value to remove from the Free_List data array.
remove_from_free_list :: proc (fl: ^Free_List($Type), index: u32) {
    assert(fl != nil, "Free_List pointer is nil")
    assert(fl.data != nil, "Free_List data is nil")

    assert(index < u32(len(fl.data)), "Index out of bounds")
    assert(index != math.max(u32), "Index is invalid")

    (^u32)(&fl.data[index])^ = fl.next_free_index
    fl.next_free_index = index

    fl.size -= 1
}

// Gets a value from the Free_List data array.
//
// Parameters:
//   fl: ^Free_List - A pointer to the Free_List instance.
//   index: u32 - The index of the value to get from the Free_List data array.
//
// Returns:
//   Type - The value at the specified index in the Free_List data array.
@require_results
get_from_free_list :: proc (fl: ^Free_List($Type), index: u32) -> Type {
    assert(fl != nil, "Free_List pointer is nil")
    assert(fl.data != nil, "Free_List data is nil")

    assert(index < u32(len(fl.data)), "Index out of bounds")
    assert(index != math.max(u32), "Index is invalid")

    return fl.data[index]
}

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