package engine

import "core:log"
import "core:mem"
import "core:thread"
import "core:time"

import "ecs"
import "platform"
import "renderer"

import rt "renderer/types"

App_Info :: struct {
    name: string,
    version: string,
}

@(private="file")
worker :: proc(t: ^thread.Thread) {
    // TODO: place the window in the center of the screen and use default user size
    window_id := platform.create_window({"Chronicle", 100, 100, 800, 600})
    window_handle: rt.Window_Context_Handle
    window_closed := false
    window_created := false

    for !window_closed {
        for event in platform.poll_window(window_id) {
            #partial switch _ in event {
                case platform.Window_Created_Event:
                    window_created = true
                    event := event.(platform.Window_Created_Event)
                    window_handle, _ = renderer.init_window(event.instance,
                                                            event.handle,
                                                            800, 600) // TODO: Use default user size
                case platform.Window_Close_Requested_Event:
                    window_closed = true
                    platform.destroy_window(window_id)

                //case platform.Window_Resized_Event:
                //    event := event.(platform.Window_Resized_Event)
                //    renderer.resize_window(window_handle, u32(event.width), u32(event.height))
            }
        }

        // TODO: remove this when the renderer is ready
        time.sleep(time.Millisecond*8)

        thread.yield()

        free_all(context.temp_allocator)
    }

    if window_created {
        renderer.destroy_window(window_handle)
    }
}

run :: proc(app_info: App_Info) {
	context.logger = log.create_console_logger()

    log.infof("Starting %v %v", app_info.name, app_info.version)

    // Memory allocators
    tracking_allocator: mem.Tracking_Allocator
    when ODIN_DEBUG {
        default_allocator := context.allocator
        mem.tracking_allocator_init(&tracking_allocator, default_allocator)
    
        context.allocator = mem.tracking_allocator(&tracking_allocator)
    }

    // Platform
    if !platform.init() {
        log.error("Failed to initialize platform")
        return
    }

    // ECS
    ecs.init()
    if !renderer.init(.Vulkan, "Chronicle") {
        log.error("Failed to initialize renderer")
        return
    }

    // Run the platform main loop
    platform.run(worker)

    // Clean up
    renderer.destroy()
	ecs.destroy()
    platform.destroy()
    free_all(context.temp_allocator)

    // Check for memory leaks
    when ODIN_DEBUG {
        for _, value in tracking_allocator.allocation_map {
            log.errorf("%v: Leaked %v bytes", value.location, value.size)
        }
    }

    log.info("Exit")
}