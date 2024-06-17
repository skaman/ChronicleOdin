package ecs

import "core:slice"

import "../utils"

// Type that represents an entity.
Entity_Id :: distinct u32

// Type that represents an archetype and index for an entity.
@private
Record :: struct {
    archetype: ^Archetype,
    index: u32
}

// Index of archetype and index for each entity.
@private
global_records: map[Entity_Id]Record

// Index of archetype for a given set of components. 
@(private="file")
global_archetypes: utils.Hash_Table([]typeid, ^Archetype)

// The global entity ID counter.
@(private="file")
global_entity_id_counter: u32 = 0

// The FNV-1a offset basis.
@(private="file")
FNV_OFFSET :: 14695981039346656037

// The FNV-1a prime value.
@(private="file")
FNV_PRIME :: 1099511628211

// Calculates the FNV-1a hash value for a given key.
//
// Parameters:
//   key: [dynamic]u64 - The key to calculate the hash for.
//
// Returns:
//   u64 - The calculated hash value.
@(private="file")
archetype_hash_proc :: proc(key: []typeid) -> u64 {
    h: u64 = FNV_OFFSET
    for x in key {
        h ~= transmute(u64)x
        h *= FNV_PRIME
    }
    return h
}

// Compares two instances of the Components type for equality.
//
// Parameters:
//   a: [dynamic]Component_Id - The first Components instance to compare.
//   b: [dynamic]Component_Id - The second Components instance to compare.
//
// Returns:
//   bool - True if the two Components instances are equal, false otherwise.
@(private="file")
archetype_eq_proc :: proc(a, b: []typeid) -> bool {
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

// Get an archetype for a given set of components or create a new one if it does not exist.
//
// Parameters:
//   components: []typeid - The components to get or create an archetype for.
//
// Returns:
//   ^Archetype - The archetype for the given components.
@(private="file")
get_or_create_archetype :: proc(components: []typeid) -> ^Archetype {
    archetype := utils.get_from_hash_table(&global_archetypes, components)
    if archetype == nil {
        archetype = new(Archetype)
        columns := make([]typeid, len(components))
        copy(columns[:], components[:])
        init_archetype(archetype, columns)
        utils.add_to_hash_table(&global_archetypes, columns, archetype)
    }
    return archetype
}

// Prepares a new set of components for a new archetype by adding the given components to the current ones.
//
// Parameters:
//   archetype: ^Archetype - The current archetype.
//   components: []typeid - The components to add to the current ones.
//
// Returns:
//   []typeid - The new set of components.
@(private="file")
prepare_add_components_to_archetype :: proc(archetype: ^Archetype, components: []typeid) -> []typeid {
    assert(archetype != nil, "Archetype must not be nil")
    assert(len(components) > 0, "Components must not be empty")

    current_components := archetype.columns
    merged_components := make([dynamic]typeid, len(components) + len(current_components), context.temp_allocator)
    copy(merged_components[:], components[:])

    offset := len(components)
    for i in 0..<len(current_components) {
        merged_components[i + offset] = current_components[i].component
    }

    slice.sort(transmute([]u64)merged_components[:])
    uniques := slice.unique(merged_components[:])

    shrink(&merged_components, len(uniques))
    return merged_components[:]
}

// Prepares a new set of components for a new archetype by removing the given components from the current ones.
//
// Parameters:
//   archetype: ^Archetype - The current archetype.
//   components: []typeid - The components to remove from the current ones.
//
// Returns:
//   []typeid - The new set of components.
@(private="file")
prepare_remove_components_from_archetype :: proc(archetype: ^Archetype, components: []typeid) -> []typeid {
    assert(archetype != nil, "Archetype must not be nil")
    assert(len(components) > 0, "Components must not be empty")

    current_components := archetype.columns
    merged_components := make([dynamic]typeid, len(current_components), context.temp_allocator)

    i := 0
    for component in current_components {
        if !slice.contains(components, component.component) {
            merged_components[i] = component.component
            i += 1
        }
    }

    shrink(&merged_components, i)
    return merged_components[:]
}

add_archetype_to_related :: proc(archetype: ^Archetype) {
    assert(archetype != nil, "Archetype must not be nil")

    it := utils.init_hash_table_iterator(&global_archetypes)
    for utils.next_hash_table_iterator(&it) {
        if (archetype == it.value) {
            continue
        }

        relation := check_if_archetype_satisfy_query(it.value, archetype.columns)
        switch relation {
            case Query_Relation.CHILD:
                add_related_archetype(archetype, it.value)
            case Query_Relation.PARENT:
                add_related_archetype(it.value, archetype)
            case Query_Relation.NONE:
        }
    }
}

remove_archetype_from_related :: proc(archetype: ^Archetype) {
    assert(archetype != nil, "Archetype must not be nil")

    it := utils.init_hash_table_iterator(&global_archetypes)
    for utils.next_hash_table_iterator(&it) {
        if (archetype == it.value) {
            continue
        }

        remove_related_archetype(it.value, archetype)
        remove_related_archetype(archetype, it.value)
    }
}

// Initializes the ECS module.
init :: proc() {
    global_records = make(map[Entity_Id]Record)
    utils.init_hash_table(&global_archetypes, archetype_hash_proc, archetype_eq_proc)
}

// Destroys the ECS module.
destroy :: proc() {
    it := utils.init_hash_table_iterator(&global_archetypes)
    for utils.next_hash_table_iterator(&it) {
        delete(it.key)
        destroy_archetype(it.value)
        free(it.value)
    }
    
    utils.destroy_hash_table(&global_archetypes)
    delete(global_records)
}

// Creates a new entity.
//
// Parameters:
//   components: []typeid - The components to create the entity with.
//
// Returns:
//   Entity_Id - The ID of the created entity.
create_entity :: proc(components: []typeid = nil) -> Entity_Id {
    all_components := make([]typeid, 1 + len(components), context.temp_allocator)
    all_components[0] = typeid_of(Entity_Id)
    if components != nil {
        copy(all_components[1:], components)
        slice.sort(transmute([]u64)all_components[:])
    }

    archetype := get_or_create_archetype(all_components)

    entity := Entity_Id(global_entity_id_counter)
    global_entity_id_counter += 1

    add_row_to_archetype(archetype, entity)

    return entity
}

// Deletes an entity.
//
// Parameters:
//   entity: Entity_Id - The entity to delete.
delete_entity :: proc(entity: Entity_Id) {
    record, ok := global_records[entity]
    if ok {
        remove_row_from_archetype(record.archetype, record.index)
        delete_key(&global_records, entity)
    }
}

// Checks if an entity exists.
//
// Parameters:
//   entity: Entity_Id - The entity to check.
//
// Returns:
//   bool - True if the entity exists, false otherwise.
exists_entity :: proc(entity: Entity_Id) -> bool {
    _, ok := global_records[entity]
    return ok
}

// Adds components to an entity.
//
// Parameters:
//   entity: Entity_Id - The entity to add components to.
//   components: []typeid - The components to add.
add_components :: proc(entity: Entity_Id, components: []typeid) {
    assert(len(components) > 0, "Components must not be empty")

    record, ok := global_records[entity]
    if ok {
        current_artetype := record.archetype
        current_index := record.index
        new_components := prepare_add_components_to_archetype(current_artetype, components)
        if len(new_components) == len(current_artetype.columns) {
            return
        }

        new_archetype := get_or_create_archetype(new_components)
        add_row_to_archetype(new_archetype, entity)
        new_index := global_records[entity].index
        for column in current_artetype.columns {
            if column.component == typeid_of(Entity_Id) {
                continue
            }
            ptr := get_ptr_from_archetype(current_artetype, current_index, column.component)
            set_ptr_in_archetype(new_archetype, new_index, column.component, ptr, column.element_size)
        }
        remove_row_from_archetype(current_artetype, record.index)
    }
}

// Adds a component to an entity.
//
// Parameters:
//   entity: Entity_Id - The entity to add the component to.
//   component: typeid - The type ID of the component to add.
add_component :: #force_inline proc(entity: Entity_Id, component: typeid) {
    add_components(entity, []typeid{component})
}

// Removes components from an entity.
//
// Parameters:
//   entity: Entity_Id - The entity to remove components from.
//   components: []typeid - The components to remove.
remove_component :: proc(entity: Entity_Id, component: typeid) {
    record, ok := global_records[entity]
    if ok {
        current_artetype := record.archetype
        current_index := record.index
        new_components := prepare_remove_components_from_archetype(current_artetype, []typeid{component})
        if len(new_components) == len(current_artetype.columns) {
            return
        }

        new_archetype := get_or_create_archetype(new_components)
        add_row_to_archetype(new_archetype, entity)
        new_index := global_records[entity].index
        for column in new_archetype.columns {
            if column.component == typeid_of(Entity_Id) {
                continue
            }
            ptr := get_ptr_from_archetype(current_artetype, current_index, column.component)
            set_ptr_in_archetype(new_archetype, new_index, column.component, ptr, column.element_size)
        }
        remove_row_from_archetype(current_artetype, record.index)
    }
}

// Checks if an entity has a component.
//
// Parameters:
//   entity: Entity_Id - The entity to check.
//   component: typeid - The type ID of the component to check.
//
// Returns:
//   bool - True if the entity has the component, false otherwise.
has_component :: #force_inline proc "contextless" (entity: Entity_Id, component: typeid) -> bool {
    record, ok := global_records[entity]
    if ok {
        return get_ptr_from_archetype(record.archetype, record.index, component) != nil
    }
    return false
}

// Sets a component by a raw pointer.
//
// Parameters:
//   entity: Entity_Id - The entity to set the component for.
//   component: typeid - The type ID of the component to set.
//   data: rawptr - The raw pointer to the component data.
//   size: u32 - The size of the component data.
set_component_by_ptr :: #force_inline proc "contextless" (entity: Entity_Id, component: typeid, data: rawptr, size: u32) {
    //assert(data != nil, "Data must not be nil")
    //assert(size > 0, "Size must be greater than 0")

    record, ok := global_records[entity]
    if ok {
        set_ptr_in_archetype(record.archetype, record.index, component, data, size)
    }
}

// Sets a component by value.
//
// Parameters:
//   entity: Entity_Id - The entity to set the component for.
//   value: ^$Type - The value to set the component to.
set_component_by_value :: #force_inline proc "contextless" (entity: Entity_Id, value: ^$Type) {
    //assert(value != nil, "Value must not be nil")

    set_component_by_ptr(entity, typeid_of(Type), rawptr(value), size_of(Type))
}

// Sets a component by value or raw pointer.
set_component :: proc{set_component_by_value, set_component_by_ptr}

// Gets a component by type ID.
//
// Parameters:
//   entity: Entity_Id - The entity to get the component from.
//   component: typeid - The type ID of the component to get.
//
// Returns:
//   rawptr - The raw pointer to the component data.
get_component_by_typeid :: #force_inline proc "contextless" (entity: Entity_Id, component: typeid) -> rawptr {
    record, ok := global_records[entity]
    if ok {
        return get_ptr_from_archetype(record.archetype, record.index, component)
    }
    return nil
}

// Gets a component by type.
//
// Parameters:
//   entity: Entity_Id - The entity to get the component from.
//   $Type - The type of the component to get.
//
// Returns:
//   ^Type - The value of the component.
get_component_by_type :: #force_inline proc "contextless" (entity: Entity_Id, $Type: typeid) -> ^Type {
    record, ok := global_records[entity]
    if ok {
        return get_value_from_archetype(record.archetype, record.index, Type)
    }
    return nil
}

// Gets a component by type or type ID.
get_component :: proc{get_component_by_type, get_component_by_typeid}

// The result of a query.
Query_Result :: struct {
    _archetypes: []^Archetype, // The archetypes that match the query.
    _archetype: ^Archetype,    // The current archetype.
    _archetype_index: i32,     // The index of the current archetype.
    _row_index: u32            // The index of the current row in the current archetype.
}

// Queries for entities with the given components.
//
// Parameters:
//   components: []typeid - The components to query for.
//
// Returns:
//   Query_Result - The result of the query.
query :: proc(components: []typeid) -> Query_Result {
    assert(len(components) > 0, "Components must not be empty")

    archetype := get_or_create_archetype(components)
    return Query_Result{archetype.query_archetypes[:], nil, -1, 0}
}

// Advances to the next entity in the query result.
//
// Parameters:
//   result: ^Query_Result - The query result to advance.
//
// Returns:
//   bool - True if there is another entity in the query result, false otherwise.
query_next :: proc(result: ^Query_Result) -> bool {
    assert(result != nil, "Query result is nil")

    if result._archetype == nil || result._row_index >= result._archetype.count - 1 {
        result._archetype, result._archetype_index = query_next_archetype(result)
        result._row_index = 0
        return result._archetype != nil
    }

    result._row_index += 1

    return true
}

// Advances to the next archetype in the query result.
//
// Parameters:
//   result: ^Query_Result - The query result to advance.
//
// Returns:
//   ^Archetype - The next archetype in the query result.
//   i32 - The index of the next archetype in the query result.
@(private="file")
query_next_archetype :: proc(result: ^Query_Result) -> (^Archetype, i32) {
    assert(result != nil, "Query result is nil")

    start_index := int(result._archetype_index + 1)
    for i in start_index..<len(result._archetypes) {
        archetype := result._archetypes[i]
        if archetype.count > 0 {
            return archetype, i32(i)
        }
    }

    return nil, -1
}

// Gets a component by type ID from the current entity in the query result.
//
// Parameters:
//   result: ^Query_Result - The query result to get the component from.
//   component: typeid - The type ID of the component to get.
//
// Returns:
//   rawptr - The raw pointer to the component data.
query_get_component_by_typeid :: proc(result: ^Query_Result, component: typeid) -> rawptr {
    assert(result != nil, "Query result is nil")
    assert(result._archetype != nil, "Query result is invalid")
    assert(result._row_index < result._archetype.count, "Query result is invalid")

    return get_ptr_from_archetype(result._archetype, result._row_index, component)
}

// Gets a component by type from the current entity in the query result.
//
// Parameters:
//   result: ^Query_Result - The query result to get the component from.
//   $Type - The type of the component to get.
//
// Returns:
//   ^Type - The value of the component.
query_get_component_by_type :: proc(result: ^Query_Result, $Type: typeid) -> ^Type {
    assert(result != nil, "Query result is nil")
    assert(result._archetype != nil, "Query result is invalid")
    assert(result._row_index < result._archetype.count, "Query result is invalid")

    return get_value_from_archetype(result._archetype, result._row_index, Type)
}

// Gets a component by type or type ID from the current entity in the query result.
query_get_component :: proc{query_get_component_by_type, query_get_component_by_typeid}
