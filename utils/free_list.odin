package utils

import "core:mem"
import "core:math"

FREE_LIST_INITIAL_CAPACITY :: 16

// Free_List is a type that represents a free list data structure.
Free_List :: struct($Type: typeid) {
    data: [dynamic]Type,        // The underlying data array.
    next_free_index: u32,       // The index of the next free element in the data array.
    size: u32                   // The number of elements in the data array.
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