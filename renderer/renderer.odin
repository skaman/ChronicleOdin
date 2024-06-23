package renderer

import "vulkan"

Renderer_Backend_Type :: enum {
    Vulkan,
}

@(private="file")
Renderer_Backend :: struct {
    init: proc(app_name: string) -> b8,
    destroy: proc(),

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
            global_renderer_backend.resize = vulkan.resize
            global_renderer_backend.begin_frame = vulkan.begin_frame
            global_renderer_backend.end_frame = vulkan.end_frame
    }

    return global_renderer_backend.init(app_name)
}

destroy :: proc() {
    global_renderer_backend.destroy()
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