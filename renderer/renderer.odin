package renderer

import "vulkan"
import "../platform"

Window_Context_Id :: distinct u32

Renderer_Backend_Type :: enum {
    Vulkan,
}

@(private="file")
Renderer_Backend :: struct {
    init: proc(app_name: string) -> b8,
    destroy: proc(),

    init_window: proc(instance: platform.Instance, handle: platform.Handle,
                      width: u32, height: u32) -> (u32, b8),
    destroy_window: proc(window_context_id: u32),
    resize_window: proc(window_context_id: u32, width: u32, height: u32),

    resize: proc(width: i32, height: i32),
    begin_frame: proc(delta_time: f32) -> b8,
    end_frame: proc(delta_time: f32) -> b8,
}

@(private="file")
global_renderer_backend : Renderer_Backend

init :: proc(backend: Renderer_Backend_Type, app_name: string) -> b8 {
    switch backend {
        case .Vulkan:
            global_renderer_backend.init = vulkan.init
            global_renderer_backend.destroy = vulkan.destroy
            global_renderer_backend.init_window = vulkan.init_window
            global_renderer_backend.destroy_window = vulkan.destroy_window
            global_renderer_backend.resize_window = vulkan.resize_window
            global_renderer_backend.resize = vulkan.resize
            global_renderer_backend.begin_frame = vulkan.begin_frame
            global_renderer_backend.end_frame = vulkan.end_frame
    }

    return global_renderer_backend.init(app_name)
}

destroy :: proc() {
    global_renderer_backend.destroy()
}

init_window :: proc(instance: platform.Instance, handle: platform.Handle,
                    width: u32, height: u32) -> (Window_Context_Id, b8) {
    window_context_id, ok := global_renderer_backend.init_window(instance, handle, width, height)
    return Window_Context_Id(window_context_id), ok
}

destroy_window :: proc(window_context_id: Window_Context_Id) {
    global_renderer_backend.destroy_window(u32(window_context_id))
}

resize_window :: proc(window_context_id: Window_Context_Id, width: u32, height: u32) {
    global_renderer_backend.resize_window(u32(window_context_id), width, height)
}

resize :: proc(width: i32, height: i32) {
    global_renderer_backend.resize(width, height)
}

begin_frame :: proc(delta_time: f32) -> b8 {
    return global_renderer_backend.begin_frame(delta_time)
}

end_frame :: proc(delta_time: f32) -> b8 {
    return global_renderer_backend.end_frame(delta_time)
}