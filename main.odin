package main

import "core:log"
import "core:mem"
import "core:testing"

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

	//entity1 := ecs.create_entity()
	//log.info("entity id:", entity1)
//
    //entity2 := ecs.create_entity({typeid_of(Component_A), typeid_of(Component_B)})
    //log.info("entity id:", entity2)
//
    //entity3 := ecs.create_entity({typeid_of(Component_A), typeid_of(Component_B)})
    //log.info("entity id:", entity3)
//
    //log.info("entity1 exists:", ecs.exists_entity(entity1))
    //log.info("entity2 exists:", ecs.exists_entity(entity2))
    //log.info("entity3 exists:", ecs.exists_entity(entity3))
//
    //ecs.add_components(entity1, {typeid_of(Component_C), typeid_of(Component_B)})
    //ecs.add_components(entity2, {typeid_of(Component_B)})
    //ecs.add_components(entity3, {typeid_of(Component_C)})
//
    //ecs.delete_entity(entity2)
//
    //log.info("entity1 exists:", ecs.exists_entity(entity1))
    //log.info("entity2 exists:", ecs.exists_entity(entity2))
    //log.info("entity3 exists:", ecs.exists_entity(entity3))

	ecs.destroy()

    free_all(context.temp_allocator)

    for _, value in tracking_allocator.allocation_map {
        log.errorf("%v: Leaked %v bytes", value.location, value.size)
    }


    //Test :: struct {
    //    x: [dynamic]u64,
    //    y: u32
    //}
//
    //test_hash_proc :: proc(key: ^[dynamic]u64) -> u64 {
    //    h: u64 = 0
    //    for x in key {
    //        h += x
    //    }
    //    return h
    //}
//
    //test_eq_proc :: proc(a, b: ^[dynamic]u64) -> bool {
    //    if len(a) != len(b) {
    //        return false
    //    }
    //    for i in 0..<len(a) {
    //        if a[i] != b[i] {
    //            return false
    //        }
    //    }
    //    return true
    //}
//
    //hash_table: utils.Hash_Table(^[dynamic]u64, ^Test)
    //utils.init_hash_table(&hash_table, test_hash_proc, test_eq_proc, 4)
//
    //{
    //    key := make([dynamic]u64, 3)
    //    defer delete(key)
    //    key[0] = u64(0)
    //    key[1] = u64(3)
    //    key[2] = u64(0)
    //    test := utils.get_from_hash_table(&hash_table, &key)
    //}
//
	log.info("END OF PROGRAM")
}
@test
test_add_component :: proc(t: ^testing.T) {
    ecs.init()

    entity := ecs.create_entity()
    ecs.add_component(entity, typeid_of(u32))
    has := ecs.has_component(entity, typeid_of(u32))
    testing.expect(t, has, "Entity should have component")

    ecs.destroy()
}