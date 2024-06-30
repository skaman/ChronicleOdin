package main

import "core:log"
import "core:mem"
import "core:thread"
import "core:math"
import "core:math/linalg"

import "engine/ecs"
import "engine/platform"
import "engine/renderer"
import rt "engine/renderer/types"

Window_State :: struct {
    x, y: i32,
    width, height: u32,
    window_id: platform.Window_Id,
    window_context_handle: rt.Window_Context_Handle,
    is_fullscreen: bool,
    is_destroyed: bool,
    is_created: bool,
}

worker :: proc(t: ^thread.Thread) {
    windows := make(map[platform.Window_Id]Window_State)
    defer delete(windows)

    for i in 0..<1 {
        x := i < 2 ? 100 : 900
        y := i % 2 == 0 ? 100 : 700
        window_id := platform.create_window({"Chronicle", i32(x), i32(y), 800, 600})
        windows[window_id] = {window_id = window_id}
    }


    for {
        for event in platform.poll() {
            switch _ in event {
                case platform.Window_Close_Requested_Event:
                    window_id := event.(platform.Window_Close_Requested_Event).window_id
                    platform.destroy_window(window_id)
                    
                    window := windows[window_id]
                    window.is_destroyed = true
                    windows[window_id] = window

                case platform.Window_Created_Event:
                    window_created_event := event.(platform.Window_Created_Event)
                    //log.infof("Window created: %v", window_created_event)
                    
                    window := windows[window_created_event.window_id]
                    window_context_handle, _ := renderer.init_window(window_created_event.instance,
                                                                     window_created_event.handle,
                                                                     window.width, window.height)
                    window.window_context_handle = window_context_handle
                    window.is_created = true
                    windows[window_created_event.window_id] = window

                case platform.Window_Destroyed_Event:
                    window_destroyed_event := event.(platform.Window_Destroyed_Event)
                    //log.infof("Window destroyed: %v", window_destroyed_event)
                    
                    window := windows[window_destroyed_event.window_id]
                    if window.window_context_handle != nil {
                        renderer.destroy_window(window.window_context_handle)
                    }
                    delete_key(&windows, window_destroyed_event.window_id)

                case platform.Window_Moved_Event:
                    window_move_event := event.(platform.Window_Moved_Event)
                    //log.infof("Window moved: %v", window_move_event)

                case platform.Window_Resized_Event:
                    window_resized_event := event.(platform.Window_Resized_Event)
                    //log.infof("Window resized: %v", window_resized_event)

                    window := windows[window_resized_event.window_id]
                    window.width = u32(window_resized_event.width)
                    window.height = u32(window_resized_event.height)
                    // TODO: we need to resize the renderer here?
                    if window.window_context_handle != nil {
                        renderer.resize_window(window.window_context_handle,
                                               u32(window_resized_event.width),
                                               u32(window_resized_event.height))
                    }
                    windows[window_resized_event.window_id] = window

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
                                window := windows[key_event.window_id]
                                window.is_fullscreen = !window.is_fullscreen
                                platform.set_window_fullscreen(key_event.window_id, window.is_fullscreen)
                                windows[key_event.window_id] = window
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
        for _, window in windows {
            if !window.is_destroyed {
                all_closed = false
                //break

                if window.is_created && window.window_context_handle != nil &&
                   renderer.begin_frame(window.window_context_handle, 0.0) {
                    projection := linalg.matrix4_perspective_f32(math.to_radians_f32(45.0), 800.0/600.0, 0.1, 1000.0)
                    view := linalg.matrix4_translate_f32(linalg.Vector3f32{0, 0, 30})
                    view = linalg.matrix4x4_inverse(view)
                    renderer.update_global_state(window.window_context_handle,
                                                 projection,
                                                 view,
                                                 linalg.Vector3f32(0),
                                                 linalg.Vector4f32(1),
                                                 0)

                    //model := linalg.matrix4_translate_f32(linalg.Vector3f32{0, 0, 0})
                    //rotation := linalg.matrix4_rotate_f32(math.to_radians_f32(0), linalg.Vector3f32{0, 1, 0})
                    @(static) angle := f32(0)
                    angle += 0.001
                    rotation := linalg.quaternion_angle_axis_f32(angle, linalg.Vector3f32{0, 0, -1})
                    model := linalg.matrix4_from_trs_f32(linalg.Vector3f32{0, 0, 0}, rotation, linalg.Vector3f32{1, 1, 1})
                    renderer.update_object(window.window_context_handle, model)

                    renderer.end_frame(window.window_context_handle, 0.0)
                }
            }
        }

        if all_closed {
            break
        }
        
        thread.yield()
    }

    for _, window in windows {
        if window.window_context_handle != nil {
            renderer.destroy_window(window.window_context_handle)
        }
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