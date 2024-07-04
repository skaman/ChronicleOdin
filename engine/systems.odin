package engine

import "core:log"

System_Stage :: enum {
    Pre_Update,
    Update,
    Post_Update,
}

System :: struct {
    init: proc(),
    destroy: proc(),
    update: proc(delta: f64),
}

@(private="file")
systems: [len(System_Stage)][dynamic]System

@private
init_systems :: proc() {
    for stage in System_Stage {
        systems[stage] = make([dynamic]System)
    }
}

@private
destroy_systems :: proc() {
    for stage in System_Stage {
        delete_dynamic_array(systems[stage])
    }
}

add_system :: proc(stage: System_Stage, system: System) {
    append(&systems[stage], system)
}