package ecs

import "core:mem"
import "core:reflect"

// Archetype_Column is a type that represents a column in an Archetype.
@private
Archetype_Column :: struct {
    component: typeid, // The type of the component.
    element_size: u32, // The size of the component element.
    data: rawptr       // The pointer to the column data portion.
}

// Archetype is a type that represents an archetype in the ECS.
@private
Archetype :: struct {
    columns: []Archetype_Column,           // The columns of the archetype.
    query_archetypes: [dynamic]^Archetype, // The related archetypes for queries.
    capacity: u32,                         // The capacity of the archetype.
    count: u32,                            // The number of entities in the archetype.
    data: rawptr                           // The data array for the entire archetype (all columns).
}

// Default capacity for an archetype.
@private
DEFAULT_ARCHETYPE_CAPACITY :: 64

// Default capacity for an archetype query.
@private
DEFAULT_ARCHETYPE_QUERY_CAPACITY :: 64

// Initializes an archetype with the specified columns and capacity.
//
// Parameters:
//   archetype: ^Archetype - A pointer to the Archetype instance to initialize.
//   columns: []typeid - The list of component types for the archetype.
//   capacity: u32 - The initial capacity of the archetype.
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

    archetype.query_archetypes = make([dynamic]^Archetype, 1, DEFAULT_ARCHETYPE_QUERY_CAPACITY)
    archetype.query_archetypes[0] = archetype

    resize_archetype(archetype, capacity)

    add_archetype_to_related(archetype)
}

// Destroys an archetype and frees the associated memory.
//
// Parameters:
//   archetype: ^Archetype - A pointer to the Archetype instance to destroy.
@private
destroy_archetype :: proc(archetype: ^Archetype) {
    assert(archetype != nil, "Archetype pointer is nil")
    assert(archetype.columns != nil, "Archetype columns are nil")

    remove_archetype_from_related(archetype)

    delete(archetype.columns)
    delete(archetype.query_archetypes)
    mem.free(archetype.data)

    archetype^ = {}
}

// Resizes an archetype to the specified new capacity.
//
// Parameters:
//   archetype: ^Archetype - A pointer to the Archetype instance to resize.
//   new_capacity: u32 - The new capacity of the archetype.
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

// Adds a row to the specified archetype with the specified entity.
//
// Parameters:
//   archetype: ^Archetype - A pointer to the Archetype instance.
//   entity: Entity_Id - The entity to add to the archetype.
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

    g_records[entity] = { archetype, archetype.count }

    archetype.count += 1
}

// Removes a row from the specified archetype at the specified index.
//
// Parameters:
//   archetype: ^Archetype - A pointer to the Archetype instance.
//   index: u32 - The index of the row to remove.
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
        g_records[entity^] = { archetype, index }
    }

    archetype.count -= 1

    if (archetype.count == archetype.capacity / 4 &&
        archetype.capacity > DEFAULT_ARCHETYPE_CAPACITY * 2) {
        resize_archetype(archetype, archetype.capacity / 2)
    }
}

// Adds an archetype to the related archetypes of the query archetypes.
//
// Parameters:
//   archetype: ^Archetype - A pointer to the Archetype instance.
//   index: u32 - The index of the row to remove.
//   component: typeid - The type of the component to add.
//
// Returns:
//   rawptr - A pointer to the added component.
@private
get_ptr_from_archetype :: #force_inline proc "contextless" (archetype: ^Archetype, index: u32, component: typeid) -> rawptr {
    //assert(archetype != nil, "Archetype pointer is nil")
    //assert(index < archetype.count, "Index is out of bounds")

    for &column in archetype.columns {
        if column.component == component {
            return rawptr(uintptr(column.data) + uintptr(column.element_size * index))
        }
    }

    return nil
}

// Gets a value from the specified archetype at the specified index.
//
// Parameters:
//   archetype: ^Archetype - A pointer to the Archetype instance.
//   index: u32 - The index of the value to get.
//   Type: typeid - The type of the value to get.
//
// Returns:
//   Type - The value at the specified index in the archetype.
@private
get_value_from_archetype :: #force_inline proc "contextless" (archetype: ^Archetype, index: u32, $Type: typeid) -> ^Type {
    component := typeid_of(Type)
    ptr := get_ptr_from_archetype(archetype, index, component)
    return (^Type)(ptr)
}

// Sets a value in the specified archetype at the specified index.
//
// Parameters:
//   archetype: ^Archetype - A pointer to the Archetype instance.
//   index: u32 - The index of the value to set.
//   component: typeid - The type of the component to set.
//   value: rawptr - The pointer to the value to set.
//   size: u32 - The size of the value to set.
//
// Returns:
//   bool - True if the value was set successfully, false otherwise.
@private
set_ptr_in_archetype :: #force_inline proc "contextless" (archetype: ^Archetype, index: u32, component: typeid, value: rawptr, size: u32) -> bool {
    //assert(archetype != nil, "Archetype pointer is nil")
    //assert(index < archetype.count, "Index is out of bounds")
    //assert(value != nil, "Value pointer is nil")
    //assert(size > 0, "Size must be greater than 0")

    ptr := get_ptr_from_archetype(archetype, index, component)
    if ptr == nil {
        return false
    }
    mem.copy(ptr, value, int(size))
    return true
}

// Query_Relation is an enum that represents the relation between archetypes in a query.
Query_Relation :: enum {
    NONE,    // No relation between the archetypes.
	CHILD,   // The archetype is a child.
    PARENT,  // The archetype is a parent.
}

// Checks if an archetype satisfies the specified query.
//
// Parameters:
//   archetype: ^Archetype - A pointer to the Archetype instance to check.
//   columns: []Archetype_Column - The columns of the query.
//
// Returns:
//   Query_Relation - The relation between the archetype and the query.
@private
check_if_archetype_satisfy_query :: proc(archetype: ^Archetype, columns: []Archetype_Column) -> Query_Relation {
    assert(archetype != nil, "Archetype pointer is nil")
    assert(len(columns) > 0, "Query must have at least one column")

    if (len(columns) > len(archetype.columns)) {
        for &archetype_column in archetype.columns {
            found := false
            for &column in columns {
                if archetype_column.component == column.component {
                    found = true
                    break
                }
            }
            if !found {
                return Query_Relation.NONE
            }
        }
        return Query_Relation.PARENT
    }

    for &column in columns {
        found := false
        for &archetype_column in archetype.columns {
            if archetype_column.component == column.component {
                found = true
                break
            }
        }
        if !found {
            return Query_Relation.NONE
        }
    }
    return Query_Relation.CHILD
}

// Adds an archetype to the related archetypes of the query archetypes.
//
// Parameters:
//   archetype: ^Archetype - A pointer to the Archetype instance.
//   related: ^Archetype - A pointer to the related Archetype instance.
@private
add_related_archetype :: proc (archetype: ^Archetype, related: ^Archetype) {
    assert(archetype != nil, "Archetype pointer is nil")
    assert(related != nil, "Related Archetype pointer is nil")

    for a in archetype.query_archetypes {
        if a == related {
            return
        }
    }

    append(&archetype.query_archetypes, related)
}

// Removes an archetype from the related archetypes of the query archetypes.
//
// Parameters:
//   archetype: ^Archetype - A pointer to the Archetype instance.
//   related: ^Archetype - A pointer to the related Archetype instance.
@private
remove_related_archetype :: proc(archetype: ^Archetype, related: ^Archetype) {
    assert(archetype != nil, "Archetype pointer is nil")
    assert(related != nil, "Related Archetype pointer is nil")

    for a, i in archetype.query_archetypes {
        if a == related {
            unordered_remove(&archetype.query_archetypes, i)
            return
        }
    }
}