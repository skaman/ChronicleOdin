package main

import "core:log"
import "core:mem"
import "core:thread"

import "ecs"
import "platform"


worker :: proc(t: ^thread.Thread) {
    window_ids := make(map[platform.Window_Id]bool)
    defer delete(window_ids)

    for i in 0..<4 {
        x := i < 2 ? 100 : 900
        y := i % 2 == 0 ? 100 : 700
        window_id := platform.create_window({"Chronicle", i32(x), i32(y), 800, 600, nil})
        window_ids[window_id] = true
    }

    for {
        for event in platform.poll() {
            switch _ in event {
                case platform.Window_Close_Requested:
                    window_id := event.(platform.Window_Close_Requested).window_id
                    platform.destroy_window(window_id)
                    window_ids[window_id] = false
                case platform.Window_Created:
                    log.info("Window created")
                case platform.Window_Destroyed:
                    log.info("Window destroyed")
            }
        }

        all_closed := true
        for _, value in window_ids {
            if value {
                all_closed = false
                break
            }
        }

        if all_closed {
            return
        }
        
        thread.yield()
    }
}

main :: proc() {
    default_allocator := context.allocator
    tracking_allocator: mem.Tracking_Allocator
    mem.tracking_allocator_init(&tracking_allocator, default_allocator)

	context.logger = log.create_console_logger()
    context.allocator = mem.tracking_allocator(&tracking_allocator)

    platform.init()
    ecs.init()

    platform.run(worker)

	ecs.destroy()
    platform.destroy()

    free_all(context.temp_allocator)

    for _, value in tracking_allocator.allocation_map {
        log.errorf("%v: Leaked %v bytes", value.location, value.size)
    }
	log.info("END OF PROGRAM")
}