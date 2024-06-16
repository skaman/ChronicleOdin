package main

import "core:log"
import "core:mem"

import "ecs"
import "utils"

Component_A :: struct {
    x: u32,
    y: u32
}

Component_B :: struct {
    x: f32,
    y: f32
}

Component_C :: struct {
    x: u64,
    y: u64
}

main :: proc() {
    default_allocator := context.allocator
    tracking_allocator: mem.Tracking_Allocator
    mem.tracking_allocator_init(&tracking_allocator, default_allocator)

	context.logger = log.create_console_logger()
    context.allocator = mem.tracking_allocator(&tracking_allocator)

    ecs.init()

	entity1 := ecs.create_entity()
	log.info("entity id:", entity1)

    entity2 := ecs.create_entity({typeid_of(Component_A), typeid_of(Component_B)})
    log.info("entity id:", entity2)

    entity3 := ecs.create_entity({typeid_of(Component_A), typeid_of(Component_B)})
    log.info("entity id:", entity3)

    log.info("entity1 exists:", ecs.exists_entity(entity1))
    log.info("entity2 exists:", ecs.exists_entity(entity2))
    log.info("entity3 exists:", ecs.exists_entity(entity3))

    ecs.add_components(entity1, {typeid_of(Component_C), typeid_of(Component_B)})
    ecs.add_components(entity2, {typeid_of(Component_B)})
    ecs.add_components(entity3, {typeid_of(Component_C)})

    ecs.delete_entity(entity2)

    log.info("entity1 exists:", ecs.exists_entity(entity1))
    log.info("entity2 exists:", ecs.exists_entity(entity2))
    log.info("entity3 exists:", ecs.exists_entity(entity3))

	ecs.destroy()

    free_all(context.temp_allocator)

    for _, value in tracking_allocator.allocation_map {
        log.errorf("%v: Leaked %v bytes", value.location, value.size)
    }
	log.info("END OF PROGRAM")
}