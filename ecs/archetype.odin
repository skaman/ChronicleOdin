package ecs

import "core:mem"
import "core:reflect"

@private
Archetype_Column :: struct {
    component: typeid,
    element_size: u32,
    data: rawptr
}

@private
Archetype :: struct {
    columns: []Archetype_Column,
    capacity: u32,
    count: u32,
    data: rawptr
}

@private
DEFAULT_ARCHETYPE_CAPACITY :: 64

@private
init_archetype :: proc(archetype: ^Archetype, columns: []typeid, capacity: u32 = DEFAULT_ARCHETYPE_CAPACITY) {
    assert(archetype != nil, "Archetype pointer is nil")
    assert(archetype.columns == nil, "Archetype columns are not nil")
    assert(archetype.capacity == 0, "Archetype capacity is not 0")
    assert(archetype.count == 0, "Archetype count is not 0")
    assert(archetype.data == nil, "Archetype data is not nil")

    assert(len(columns) > 0, "Archetype must have at least one column")
    assert(capacity > 0, "Archetype capacity must be greater than 0")

    archetype.columns = make([]Archetype_Column, len(columns))
    for i in 0..<len(columns) {
        info: ^reflect.Type_Info
        info = type_info_of(transmute(typeid)columns[i])
        archetype.columns[i] = Archetype_Column { columns[i], u32(info.size), nil }
    }

    resize_archetype(archetype, capacity)
}

@private
destroy_archetype :: proc(archetype: ^Archetype) {
    assert(archetype != nil, "Archetype pointer is nil")
    assert(archetype.columns != nil, "Archetype columns are nil")

    delete(archetype.columns)
    mem.free(archetype.data)

    archetype^ = {}
}

@(private="file")
resize_archetype :: proc(archetype: ^Archetype, new_capacity: u32) {
    assert(archetype != nil, "Archetype pointer is nil")
    assert(new_capacity >= archetype.count, "New capacity must be greater than or equal to the current count")

    row_size: u32 = 0
    for column in archetype.columns {
        assert(column.element_size > 0, "Column element size must be greater than 0")
        row_size += column.element_size
    }

    ptr, _ := mem.alloc(int(new_capacity * row_size))
    offset: uintptr = 0
    for &column in archetype.columns {
        column_ptr := rawptr(uintptr(ptr) + offset)

        if archetype.data != nil && archetype.count > 0 {
            mem.copy(column_ptr, column.data, int(column.element_size * archetype.count))
        }

        column.data = column_ptr
        offset += uintptr(column.element_size * new_capacity)
    }

    if archetype.data != nil {
        mem.free(archetype.data)
    }

    archetype.data = ptr
    archetype.capacity = new_capacity
}

@private
add_row_to_archetype :: proc(archetype: ^Archetype, entity: Entity_Id) {
    assert(archetype != nil, "Archetype pointer is nil")

    if (archetype.count == archetype.capacity) {
        resize_archetype(archetype, archetype.capacity * 2)
    }

    for column in archetype.columns {
        ptr := uintptr(column.data) + uintptr(column.element_size * archetype.count)
        if column.component == typeid_of(Entity_Id) {
            (^Entity_Id)(rawptr(ptr))^ = entity
        }
        else {
            mem.zero(rawptr(ptr), int(column.element_size))            
        }
    }

    global_records[entity] = { archetype, archetype.count }

    archetype.count += 1
}

@private
remove_row_from_archetype :: proc(archetype: ^Archetype, index: u32) {
    assert(archetype != nil, "Archetype pointer is nil")
    assert(index < archetype.count, "Index is out of bounds")

    for &column in archetype.columns {
        element_to_replace := uintptr(column.data) + uintptr(column.element_size * index)
        last_element := uintptr(column.data) + uintptr(column.element_size * (archetype.count - 1))
        mem.copy(rawptr(element_to_replace), rawptr(last_element), int(column.element_size))
    }

    entity := get_value_from_archetype(archetype, index, Entity_Id)

    if index < archetype.count - 1 {
        global_records[entity^] = { archetype, index }
    }

    archetype.count -= 1

    if (archetype.count == archetype.capacity / 4 &&
        archetype.capacity > DEFAULT_ARCHETYPE_CAPACITY * 2) {
        resize_archetype(archetype, archetype.capacity / 2)
    }
}

@private
get_ptr_from_archetype :: proc(archetype: ^Archetype, index: u32, component: typeid) -> rawptr {
    assert(archetype != nil, "Archetype pointer is nil")
    assert(index < archetype.count, "Index is out of bounds")

    for &column in archetype.columns {
        if column.component == component {
            return rawptr(uintptr(column.data) + uintptr(column.element_size * index))
        }
    }

    return nil
}

@private
get_value_from_archetype :: proc(archetype: ^Archetype, index: u32, $Type: typeid) -> ^Type {
    component := typeid_of(Type)
    ptr := get_ptr_from_archetype(archetype, index, component)
    return (^Type)(ptr)
}

@private
set_ptr_in_archetype :: proc(archetype: ^Archetype, index: u32, component: typeid, value: rawptr, size: u32) -> bool {
    ptr := get_ptr_from_archetype(archetype, index, component)
    if ptr == nil {
        return false
    }
    mem.copy(ptr, value, int(size))
    return true
}