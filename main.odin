package main

import "core:log"
import "core:mem"
import "core:thread"

import "ecs"
import "platform"
import "renderer"


worker :: proc(t: ^thread.Thread) {
    window_ids := make(map[platform.Window_Id]bool)
    defer delete(window_ids)

    window_contexts := make(map[platform.Window_Id]renderer.Window_Context_Id)
    defer delete(window_contexts)

    window_fullscreen := make(map[platform.Window_Id]bool)
    defer delete(window_fullscreen)

    for i in 0..<4 {
        x := i < 2 ? 100 : 900
        y := i % 2 == 0 ? 100 : 700
        window_id := platform.create_window({"Chronicle", i32(x), i32(y), 800, 600})
        window_ids[window_id] = true
    }


    for {
        for event in platform.poll() {
            switch _ in event {
                case platform.Window_Close_Requested_Event:
                    window_id := event.(platform.Window_Close_Requested_Event).window_id
                    platform.destroy_window(window_id)
                    window_ids[window_id] = false
                case platform.Window_Created_Event:
                    window_created_event := event.(platform.Window_Created_Event)
                    log.infof("Window created: %v", window_created_event)
                    window_context_id, _ := renderer.init_window(window_created_event.instance, window_created_event.handle)
                    window_contexts[window_created_event.window_id] = window_context_id
                case platform.Window_Destroyed_Event:
                    window_destroyed_event := event.(platform.Window_Destroyed_Event)
                    log.infof("Window destroyed: %v", window_destroyed_event)
                    renderer.destroy_window(window_contexts[window_destroyed_event.window_id])
                    delete_key(&window_ids, window_destroyed_event.window_id)
                    delete_key(&window_contexts, window_destroyed_event.window_id)
                case platform.Window_Moved_Event:
                    window_move_event := event.(platform.Window_Moved_Event)
                    log.infof("Window moved: %v", window_move_event)
                case platform.Window_Resized_Event:
                    window_resized_event := event.(platform.Window_Resized_Event)
                    log.infof("Window resized: %v", window_resized_event)
                case platform.Key_Event:
                    key_event := event.(platform.Key_Event)
                    log.infof("Key event: %v", key_event)
                    #partial switch key_event.key {
                        case .Key_0:
                            platform.set_window_position(key_event.window_id, 0, 0)
                        case .Key_1:
                            platform.set_window_size(key_event.window_id, 1920, 1080)
                        case .Key_2:
                            platform.set_window_title(key_event.window_id, "New Title")
                        case .Key_F:
                            if key_event.pressed {
                                platform.set_window_fullscreen(key_event.window_id, !window_fullscreen[key_event.window_id])
                                window_fullscreen[key_event.window_id] = !window_fullscreen[key_event.window_id]
                            }
                        case:
                    }
                case platform.Char_Event:
                    char_event := event.(platform.Char_Event)
                    log.infof("Char event: %c", char_event.character)
                case platform.Mouse_Event:
                    mouse_event := event.(platform.Mouse_Event)
                    //log.infof("Mouse event: %v", mouse_event)
                case platform.Gamepad_Event:
                    gamepad_event := event.(platform.Gamepad_Event)
                    log.infof("Gamepad event: %v", gamepad_event)
                case platform.Gamepad_Button_Event:
                    gamepad_button_event := event.(platform.Gamepad_Button_Event)
                    log.infof("Gamepad button event: %v", gamepad_button_event)
                case platform.Gamepad_Axis_Event:
                    gamepad_axis_event := event.(platform.Gamepad_Axis_Event)
                    log.infof("Gamepad axis event: %v", gamepad_axis_event)
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
            break
        }
        
        thread.yield()
    }

    for window_id in window_ids {
        window_context_id := window_contexts[window_id]
        renderer.destroy_window(window_context_id)
    }
}

main :: proc() {
	context.logger = log.create_console_logger()

    tracking_allocator: mem.Tracking_Allocator
    when ODIN_DEBUG {
        default_allocator := context.allocator
        mem.tracking_allocator_init(&tracking_allocator, default_allocator)
    
        context.allocator = mem.tracking_allocator(&tracking_allocator)
    }

    if !platform.init() {
        log.error("Failed to initialize platform")
        return
    }

    ecs.init()
    if !renderer.init(.Vulkan, "Chronicle") {
        log.error("Failed to initialize renderer")
        return
    }

    platform.run(worker)

    renderer.destroy()
	ecs.destroy()
    platform.destroy()

    free_all(context.temp_allocator)

    when ODIN_DEBUG {
        for _, value in tracking_allocator.allocation_map {
            log.errorf("%v: Leaked %v bytes", value.location, value.size)
        }
    }
	log.info("END OF PROGRAM")
}