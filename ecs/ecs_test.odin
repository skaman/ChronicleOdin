package ecs

import "core:testing"
import "core:math/rand"
import "core:mem"

@test
test_query :: proc(t: ^testing.T) {
    init()

    Component_A :: struct {
        x: u32,
        y: u32
    }

    Component_B :: struct {
        x: f32,
        y: f32
    }

    entities := make([]Entity_Id, 100, context.temp_allocator)
    for i in 0..<100 {
        entities[i] = create_entity([]typeid{Component_A})
        componentA := Component_A{u32(i), u32(i)}
        set_component(entities[i], &componentA)
        if i % 2 == 0 {
            add_component(entities[i], Component_B)
            componentB := Component_B{f32(i), f32(i)}
            set_component(entities[i], &componentB)
        }
    }

    query_result := query([]typeid{Entity_Id, Component_A})
    count := 0
    found_entities := make(map[Entity_Id]bool, len(entities) * 2, context.temp_allocator)
    for query_next(&query_result) {
        entity := query_get_component(&query_result, Entity_Id)
        found_entities[entity^] = true

        componentA := query_get_component(&query_result, Component_A)
        testing.expect(t, componentA != nil, "Component A should not be nil")
        count += 1
    }
    testing.expect(t, count == 100, "Count should be 100")
    all_entities_found := true
    for entity in entities {
        _, ok := found_entities[entity]
        all_entities_found = all_entities_found && ok
    }
    testing.expect(t, all_entities_found, "All entities should be found")

    query_result = query([]typeid{Component_A, Component_B})
    count = 0
    for query_next(&query_result) {
        componentA := query_get_component(&query_result, Component_A)
        testing.expect(t, componentA != nil, "Component A should not be nil")
        componentB := query_get_component(&query_result, Component_B)
        testing.expect(t, componentB != nil, "Component B should not be nil")
        count += 1
    }

    testing.expect(t, count == 50, "Count should be 50")

    destroy()
}

@test
test_create_entity :: proc(t: ^testing.T) {
    init()

    entity := create_entity()
    exists := exists_entity(entity)
    testing.expect(t, exists, "Entity should exist")

    destroy()
}

@test
test_delete_entity :: proc(t: ^testing.T) {
    init()

    entity := create_entity()
    exists := exists_entity(entity)
    testing.expect(t, exists, "Entity should exist")

    delete_entity(entity)
    exists = exists_entity(entity)
    testing.expect(t, !exists, "Entity should not exist")

    destroy()
}

@test
test_delete_not_existing_entity :: proc(t: ^testing.T) {
    init()

    entity := Entity_Id(0xdeadbeef)
    delete_entity(entity)
    exists := exists_entity(entity)
    testing.expect(t, !exists, "Entity should not exist")

    destroy()
}

@test
test_add_component :: proc(t: ^testing.T) {
    init()

    entity := create_entity()
    add_component(entity, u32)
    has := has_component(entity, u32)
    testing.expect(t, has, "Entity should have component")

    destroy()
}

@test
test_set_component :: proc(t: ^testing.T) {
    init()

    Component_A :: struct {
        x: u32,
        y: u32
    }

    entity := create_entity()
    add_component(entity, Component_A)

    component1 := Component_A{42, 42}
    set_component(entity, &component1)
    has := has_component(entity, Component_A)
    testing.expect(t, has, "Entity should have component")

    component := get_component(entity, Component_A)
    testing.expect(t, component.x == 42, "Component x should be 42")
    testing.expect(t, component.y == 42, "Component y should be 42")

    component2 := Component_A{24, 24}
    set_component(entity, &component2)
    has = has_component(entity, Component_A)
    testing.expect(t, has, "Entity should have component")

    component = get_component(entity, Component_A)
    testing.expect(t, component.x == 24, "Component x should be 24")
    testing.expect(t, component.y == 24, "Component y should be 24")

    destroy()
}

@test
test_remove_component :: proc(t: ^testing.T) {
    init()

    entity := create_entity()
    add_component(entity, u32)
    has := has_component(entity, u32)
    testing.expect(t, has, "Entity should have component")

    remove_component(entity, u32)
    has = has_component(entity, u32)
    testing.expect(t, !has, "Entity should not have component")

    destroy()
}

@test
test_mixed_operations :: proc(t: ^testing.T) {
    // Context setup
    default_allocator := context.allocator
    tracking_allocator: mem.Tracking_Allocator
    mem.tracking_allocator_init(&tracking_allocator, default_allocator)
    context.allocator = mem.tracking_allocator(&tracking_allocator)

    init()

    Component_A :: struct {
        x: u32,
        y: u32
    }

    Component_B :: struct {
        x: f32,
        y: f32
    }

    // Create entities
    entities := make([]Entity_Id, 10000, context.temp_allocator)
    for i in 0..<10000 {
        entities[i] = create_entity()
    }

    rand.shuffle(entities[:])

    // Add or set components
    for entity in entities {
        if entity % 2 == 0 {
            add_component(entity, Component_A)
            add_component(entity, Component_B)

            componentB := Component_B{f32(entity), f32(2.45)}
            set_component(entity, &componentB)
        } else {
            add_component(entity, Component_A)
            add_component(entity, Component_B)

            componentA := Component_A{u32(entity), 2}
            set_component(entity, &componentA)
        }
    }
    
    rand.shuffle(entities[:])

    // Check components
    for entity in entities {
        if entity % 2 == 0 {
            component := get_component(entity, Component_A)
            testing.expect(t, component.x == 0, "Component x should be 0")
        } else {
            component := get_component(entity, Component_A)
            testing.expect(t, component.x == u32(entity), "Component x should be equal to entity")
        }
    }
    
    rand.shuffle(entities[:])

    // Delete some entities
    for i in 0..<len(entities) / 2 {
        delete_entity(entities[i])
    }
    entities = entities[len(entities) / 2:]
    
    rand.shuffle(entities[:])

    // Add other entities
    entities_tmp := make([]Entity_Id, 10000 + len(entities), context.temp_allocator)
    copy(entities_tmp[:len(entities)], entities[:])
    for i in 0..<10000 {
        entities_tmp[i + len(entities)] = create_entity([]typeid{typeid_of(Component_A)})
    }
    entities = entities_tmp
    
    rand.shuffle(entities[:])

    // Set components
    for entity in entities {
        add_component(entity, Component_A)
        componentA := Component_A{u32(entity) * 2, 2}
        set_component(entity, &componentA)
    }

    rand.shuffle(entities[:])

    // Check components
    for entity in entities {
        component := get_component(entity, Component_A)
        testing.expect(t, component.x == u32(entity) * 2, "Component x should be equal to entity * 2")
    }

    rand.shuffle(entities[:])

    // Delete all entities
    for entity in entities {
        delete_entity(entity)
    }

    destroy()

    free_all(context.temp_allocator)

    // Test memory leaks
    have_memory_leak := false
    for _, value in tracking_allocator.allocation_map {
        testing.logf(t, "%v: Leaked %v bytes", value.location, value.size)
        have_memory_leak = true
    }
    testing.expect(t, !have_memory_leak, "Memory leak detected") 
}