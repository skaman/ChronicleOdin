package benchmark

import "../ecs"

TestComponent :: struct {
    x: u32,
    y: u32
}

test_create_1_entity :: proc() {
    run_benchmark(proc() {
        _ = ecs.create_entity()
    }, proc() {
        ecs.init()
    }, proc() {
        ecs.destroy()
    }, 1_000_000, "Create 1 entity")
}

test_create_100_entity :: proc() {
    run_benchmark(proc() {
        for i in 0..<100 {
            _ = ecs.create_entity()
        }
    }, proc() {
        ecs.init()
    }, proc() {
        ecs.destroy()
    }, 10_000, "Create 100 entity")
}

test_create_10000_entity :: proc() {
    run_benchmark(proc() {
        for i in 0..<10000 {
            _ = ecs.create_entity()
        }
    }, proc() {
        ecs.init()
    }, proc() {
        ecs.destroy()
    }, 100, "Create 10_000 entity")
}

test_add_1_component_entity : ecs.Entity_Id
test_add_1_component :: proc() {
    run_benchmark(proc() {
        ecs.add_component(test_add_1_component_entity, TestComponent)
    }, proc() {
        ecs.init()
        test_add_1_component_entity := ecs.create_entity()
    }, proc() {
        ecs.destroy()
    }, 1_000_000, "Add 1 component")
}

test_add_100_component_entity : [100]ecs.Entity_Id
test_add_100_component :: proc() {
    run_benchmark(proc() {
        for i in 0..<100 {
            ecs.add_component(test_add_100_component_entity[i], TestComponent)
        }
    }, proc() {
        ecs.init()
        for i in 0..<100 {
            test_add_100_component_entity[i] = ecs.create_entity()
        }
    }, proc() {
        ecs.destroy()
    }, 10_000, "Add 100 component")
}

test_add_10000_component_entity : [10000]ecs.Entity_Id
test_add_10000_component :: proc() {
    run_benchmark(proc() {
        for i in 0..<10000 {
            ecs.add_component(test_add_10000_component_entity[i], TestComponent)
        }
    }, proc() {
        ecs.init()
        for i in 0..<10000 {
            test_add_10000_component_entity[i] = ecs.create_entity()
        }
    }, proc() {
        ecs.destroy()
    }, 100, "Add 10_000 component")
}

test_set_1_component_entity : ecs.Entity_Id
test_set_1_component :: proc() {
    run_benchmark(proc() {
        cmp := TestComponent{1, 2}
        ecs.set_component(test_set_1_component_entity, &cmp)
    }, proc() {
        ecs.init()
        test_set_1_component_entity := ecs.create_entity()
        ecs.add_component(test_set_1_component_entity, TestComponent)
    }, proc() {
        ecs.destroy()
    }, 1_000_000, "Set 1 component")
}

test_set_100_component_entity : [100]ecs.Entity_Id
test_set_100_component :: proc() {
    run_benchmark(proc() {
        cmp := TestComponent{1, 2}
        for i in 0..<100 {
            ecs.set_component(test_set_100_component_entity[i], &cmp)
        }
    }, proc() {
        ecs.init()
        for i in 0..<100 {
            test_set_100_component_entity[i] = ecs.create_entity()
            ecs.add_component(test_set_100_component_entity[i], TestComponent)
        }
    }, proc() {
        ecs.destroy()
    }, 10_000, "Set 100 component")
}

test_set_10000_component_entity : [10000]ecs.Entity_Id
test_set_10000_component :: proc() {
    run_benchmark(proc() {
        cmp := TestComponent{1, 2}
        for i in 0..<10000 {
            ecs.set_component(test_set_10000_component_entity[i], &cmp)
        }
    }, proc() {
        ecs.init()
        for i in 0..<10000 {
            test_set_10000_component_entity[i] = ecs.create_entity()
            ecs.add_component(test_set_10000_component_entity[i], TestComponent)

        }
    }, proc() {
        ecs.destroy()
    }, 100, "Set 10_000 component")
}

test_query_1_component :: proc() {
    run_benchmark(proc() {
        query_result := ecs.query([]typeid{TestComponent})
        for ecs.query_next(&query_result) {
            _ = ecs.query_get_component(&query_result, TestComponent)
        }
    }, proc() {
        ecs.init()
        entity := ecs.create_entity()
        ecs.add_component(entity, TestComponent)
}, proc() {
        ecs.destroy()
    }, 100, "Query 1 component")
}

test_query_1000_component :: proc() {
    run_benchmark(proc() {
        query_result := ecs.query([]typeid{TestComponent})
        for ecs.query_next(&query_result) {
            _ = ecs.query_get_component(&query_result, TestComponent)
        }
    }, proc() {
        ecs.init()
        for i in 0..<1_000 {
            entity := ecs.create_entity()
            ecs.add_component(entity, TestComponent)
        }
    }, proc() {
        ecs.destroy()
    }, 100, "Query 1_000 component")
}

test_query_100000_component :: proc() {
    run_benchmark(proc() {
        query_result := ecs.query([]typeid{TestComponent})
        for ecs.query_next(&query_result) {
            _ = ecs.query_get_component(&query_result, TestComponent)
        }
    }, proc() {
        ecs.init()
        for i in 0..<100_000 {
            entity := ecs.create_entity()
            ecs.add_component(entity, TestComponent)
        }
    }, proc() {
        ecs.destroy()
    }, 100, "Query 100_000 component")
}