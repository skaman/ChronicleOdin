package utils

import "core:mem"
import "core:testing"

// Hash_Table_Iterator is a type that represents an iterator for a hash table.
Hash_Table_Iterator :: struct($Key, $Value: typeid) {
    key: Key,                               // The key of the current entry.
    value: Value,                           // The value of the current entry.
    _hash_table: ^Hash_Table(Key, Value),   // The hash table being iterated.
    _index: u32                             // The current index of the iterator.
}

// Hash_Table_Entry is a type that represents an entry in a hash table.
@(private="file")
Hash_Table_Entry :: struct($Key, $Value: typeid) {
    is_used: bool,                          // Indicates whether the entry is used.
    key: Key,                               // The key of the entry.
    value: Value                            // The value of the entry.
}

// Hash_Table is a type that represents a hash table data structure.
Hash_Table :: struct($Key, $Value: typeid) {
    _hash_proc: proc(key: Key) -> u64,      // The hash function for the keys.
    _eq_proc: proc(a, b: Key) -> bool,      // The equality function for the keys.
    _data: rawptr,                          // The underlying data array.
    _capacity: u32,                         // The capacity of the data array.
    _count: u32                             // The number of elements in the data array.
}

HASH_TABLE_INITIAL_CAPACITY :: 64

// Initializes a Hash_Table instance with the specified hash and equality functions.
//
// Parameters:
//   t: ^Hash_Table - A pointer to the Hash_Table instance to initialize.
//   hash_proc: proc - The hash function for the keys.
//   eq_proc: proc - The equality function for the keys.
//   capacity: u32 - The initial capacity of the Hash_Table data array.
init_hash_table :: proc(t: ^Hash_Table($Key, $Value), hash_proc: proc(key: Key) -> u64,
                        eq_proc: proc(a, b: Key) -> bool, capacity: u32 = HASH_TABLE_INITIAL_CAPACITY) {
    assert(t != nil, "Hash_Table pointer is nil")
    assert(t._data == nil, "Hash_Table data is not nil")
    assert(t._capacity == 0, "Hash_Table capacity is not 0")
    assert(t._count == 0, "Hash_Table count is not 0")

    assert(capacity > 0, "Capacity must be greater than 0")
    assert(hash_proc != nil, "Hash proc is nil")
    assert(eq_proc != nil, "Eq proc is nil")

    ptr, _ := mem.alloc(int(size_of(Hash_Table_Entry(Key, Value)) * capacity))

    t._hash_proc = hash_proc
    t._eq_proc = eq_proc
    t._data = ptr
    t._capacity = capacity
    t._count = 0
}

// Destroys a Hash_Table instance and frees the associated memory.
//
// Parameters:
//   t: ^Hash_Table - A pointer to the Hash_Table instance to destroy.
destroy_hash_table :: proc(t: ^Hash_Table($Key, $Value)) {
    assert(t != nil, "Hash_Table pointer is nil")
    assert(t._data != nil, "Hash_Table data is nil")

    mem.free(t._data)

    t^ = {}
}

// Resizes the underlying data array of a Hash_Table instance.
//
// Parameters:
//   t: ^Hash_Table - A pointer to the Hash_Table instance to resize.
//   new_capacity: u32 - The new capacity of the data array.
@(private="file")
resize_hash_table :: proc(t: ^Hash_Table($Key, $Value), new_capacity: u32) {
    assert(t != nil, "Hash_Table pointer is nil")
    assert(t._data != nil, "Hash_Table data is nil")
    assert(new_capacity > 0, "New capacity must be greater than 0")
    assert(new_capacity >= t._count, "New capacity must be greater than or equal to the current count")

    ptr, _ := mem.alloc(int(size_of(Hash_Table_Entry(Key, Value)) * new_capacity))

    for i in 0..<int(t._capacity) {
        current_ptr := uintptr(t._data) + uintptr(i * size_of(Hash_Table_Entry(Key, Value)))
        entry := (^Hash_Table_Entry(Key, Value))(current_ptr)

        if entry.is_used {
            add_to_hash_table_entries(rawptr(ptr), new_capacity, t._hash_proc, entry.key, entry.value)
        }
    }

    mem.free(t._data)

    t._data = ptr
    t._capacity = new_capacity
}

// Adds an entry to the underlying data array of a Hash_Table instance.
//
// Parameters:
//   ptr: rawptr - A pointer to the start of the data array.
//   capacity: u32 - The capacity of the data array.
//   hash_proc: proc - The hash function for the keys.
//   key: Key - The key of the entry.
//   value: Value - The value of the entry.
@(private="file")
add_to_hash_table_entries :: proc(ptr: rawptr, capacity: u32, hash_proc: proc(key: $Key) -> u64,
                                  key: Key, value: $Value) {
    index := hash_proc(key) % u64(capacity)
    ptr := uintptr(ptr) + uintptr(index * size_of(Hash_Table_Entry(Key, Value)))
    entry := (^Hash_Table_Entry(Key, Value))(ptr)

    for {
        if !entry.is_used {
            entry.is_used = true
            entry.key = key
            entry.value = value
            break
        }

        index = (index + 1) % u64(capacity)
        ptr += size_of(Hash_Table_Entry(Key, Value))
        entry = (^Hash_Table_Entry(Key, Value))(ptr)
    }
}

// Adds an entry to a Hash_Table instance.
//
// Parameters:
//   t: ^Hash_Table - A pointer to the Hash_Table instance.
//   key: Key - The key of the entry.
//   value: Value - The value of the entry.
add_to_hash_table :: proc(t: ^Hash_Table($Key, $Value), key: Key, value: Value) {
    assert(t != nil, "Hash_Table pointer is nil")
    assert(t._data != nil, "Hash_Table data is nil")

    if t._count >= t._capacity / 2 {
        resize_hash_table(t, t._capacity * 2)
    }

    add_to_hash_table_entries(t._data, t._capacity, t._hash_proc, key, value)

    t._count += 1
}

// Removes an entry from a Hash_Table instance.
//
// Parameters:
//   t: ^Hash_Table - A pointer to the Hash_Table instance.
//   key: Key - The key of the entry to remove.
remove_from_hash_table :: proc(t: ^Hash_Table($Key, $Value), key: Key) {
    assert(t != nil, "Hash_Table pointer is nil")
    assert(t._data != nil, "Hash_Table data is nil")

    index := t._hash_proc(key) % u64(t._capacity)
    ptr := uintptr(t._data) + uintptr(index * size_of(Hash_Table_Entry(Key, Value)))
    start_ptr := ptr
    entry := (^Hash_Table_Entry(Key, Value))(ptr)

    for {
        if entry.is_used && t._eq_proc(entry.key, key) {
            entry^ = {}
            t._count -= 1
            break
        }

        index = (index + 1) % u64(t._capacity)
        ptr = uintptr(t._data) + uintptr(index * size_of(Hash_Table_Entry(Key, Value)))
        if ptr == start_ptr {
            break
        }
        entry = (^Hash_Table_Entry(Key, Value))(ptr)
    }
}

// Gets a value from a Hash_Table instance.
//
// Parameters:
//   t: ^Hash_Table - A pointer to the Hash_Table instance.
//   key: Key - The key of the entry to get.
//
// Returns:
//   Value - The value of the entry with the specified key.
@require_results
get_from_hash_table :: proc(t: ^Hash_Table($Key, $Value), key: Key) -> Value {
    assert(t != nil, "Hash_Table pointer is nil")
    assert(t._data != nil, "Hash_Table data is nil")

    index := t._hash_proc(key) % u64(t._capacity)
    ptr := uintptr(t._data) + uintptr(index * size_of(Hash_Table_Entry(Key, Value)))
    start_ptr := ptr
    entry := (^Hash_Table_Entry(Key, Value))(ptr)

    for {
        if entry.is_used && t._eq_proc(entry.key, key) {
            return entry.value
        }

        index = (index + 1) % u64(t._capacity)
        ptr = uintptr(t._data) + uintptr(index * size_of(Hash_Table_Entry(Key, Value)))
        if ptr == start_ptr {
            break
        }
        entry = (^Hash_Table_Entry(Key, Value))(ptr)
    }

    return {}
}

// Initializes a Hash_Table_Iterator instance for a Hash_Table.
//
// Parameters:
//   t: ^Hash_Table - A pointer to the Hash_Table instance.
//
// Returns:
//   Hash_Table_Iterator - The initialized Hash_Table_Iterator instance.
init_hash_table_iterator :: proc(t: ^Hash_Table($Key, $Value)) -> Hash_Table_Iterator(Key, Value) {
    assert(t != nil, "Hash_Table pointer is nil")
    assert(t._data != nil, "Hash_Table data is nil")

    return Hash_Table_Iterator(Key, Value){{},{},t, 0}
}

// Advances a Hash_Table_Iterator instance to the next entry in the Hash_Table.
//
// Parameters:
//   it: ^Hash_Table_Iterator - A pointer to the Hash_Table_Iterator instance.
//
// Returns:
//   bool - True if the iterator was advanced, false if the end of the Hash_Table was reached.
next_hash_table_iterator :: proc(it: ^Hash_Table_Iterator($Key, $Value)) -> bool {
    assert(it != nil, "Hash_Table_Iterator pointer is nil")
    assert(it._hash_table != nil, "Hash_Table_Iterator hash_table is nil")

    for {
        if it._index >= it._hash_table._capacity {
            return false
        }

        ptr := uintptr(it._hash_table._data) + uintptr(it._index * size_of(Hash_Table_Entry(Key, Value)))
        entry := (^Hash_Table_Entry(Key, Value))(ptr)

        it._index += 1

        if entry.is_used {
            it.key = entry.key
            it.value = entry.value
            return true
        }
    }
}