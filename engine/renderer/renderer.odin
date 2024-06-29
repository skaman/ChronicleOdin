package renderer

import "vulkan"
import "../platform"

// Distinct type for window context identifier
Window_Context_Id :: distinct u32

// Enumeration for different renderer backend types
Renderer_Backend_Type :: enum {
    Vulkan,
}

// Struct to define the renderer backend interface
@(private="file")
Renderer_Backend :: struct {
    init: proc(app_name: string) -> b8,             // Function to initialize the renderer backend
    destroy: proc(),                                // Function to destroy the renderer backend

    init_window: proc(instance: platform.Instance,  // Function to initialize a window
                      handle: platform.Handle,
                      width: u32, height: u32) -> (u32, b8),
    destroy_window: proc(window_context_id: u32),   // Function to destroy a window
    resize_window: proc(window_context_id: u32,     // Function to resize a window
                        width: u32, height: u32),

    begin_frame: proc(window_context_id: u32,       // Function to begin rendering a frame
                      delta_time: f32) -> b8,
    end_frame: proc(window_context_id: u32,         // Function to end rendering a frame
                    delta_time: f32) -> b8,
}

// Global variable to store the current renderer backend
@(private="file")
global_renderer_backend : Renderer_Backend

// Initializes the renderer with the specified backend.
//
// Parameters:
//   backend: Renderer_Backend_Type - The type of the renderer backend to use.
//   app_name: string - The name of the application.
//
// Returns:
//   b8 - True if initialization was successful, otherwise false.
init :: proc(backend: Renderer_Backend_Type, app_name: string) -> b8 {
    switch backend {
        case .Vulkan:
            global_renderer_backend.init = vulkan.init
            global_renderer_backend.destroy = vulkan.destroy
            global_renderer_backend.init_window = vulkan.init_window
            global_renderer_backend.destroy_window = vulkan.destroy_window
            global_renderer_backend.resize_window = vulkan.resize_window
            global_renderer_backend.begin_frame = vulkan.begin_frame
            global_renderer_backend.end_frame = vulkan.end_frame
    }

    return global_renderer_backend.init(app_name)
}

// Destroys the renderer backend.
destroy :: proc() {
    global_renderer_backend.destroy()
}

// Initializes a window with the specified parameters.
//
// Parameters:
//   instance: platform.Instance - The platform instance.
//   handle: platform.Handle - The handle to the window.
//   width: u32 - The width of the window.
//   height: u32 - The height of the window.
//
// Returns:
//   (Window_Context_Id, b8) - The window context ID and a boolean indicating success.
init_window :: proc(instance: platform.Instance, handle: platform.Handle,
                    width: u32, height: u32) -> (Window_Context_Id, b8) {
    window_context_id, ok := global_renderer_backend.init_window(instance, handle, width, height)
    return Window_Context_Id(window_context_id), ok
}

// Destroys the specified window.
//
// Parameters:
//   window_context_id: Window_Context_Id - The ID of the window context to destroy.
destroy_window :: proc(window_context_id: Window_Context_Id) {
    global_renderer_backend.destroy_window(u32(window_context_id))
}

// Resizes the specified window.
//
// Parameters:
//   window_context_id: Window_Context_Id - The ID of the window context to resize.
//   width: u32 - The new width of the window.
//   height: u32 - The new height of the window.
resize_window :: proc(window_context_id: Window_Context_Id, width: u32, height: u32) {
    global_renderer_backend.resize_window(u32(window_context_id), width, height)
}

// Begins rendering a frame for the specified window.
//
// Parameters:
//   window_context_id: Window_Context_Id - The ID of the window context to begin rendering.
//   delta_time: f32 - The time since the last frame.
//
// Returns:
//   b8 - True if the frame was successfully begun, otherwise false.
begin_frame :: proc(window_context_id: Window_Context_Id, delta_time: f32) -> b8 {
    return global_renderer_backend.begin_frame(u32(window_context_id), delta_time)
}

// Ends rendering a frame for the specified window.
//
// Parameters:
//   window_context_id: Window_Context_Id - The ID of the window context to end rendering.
//   delta_time: f32 - The time since the last frame.
//
// Returns:
//   b8 - True if the frame was successfully ended, otherwise false.
end_frame :: proc(window_context_id: Window_Context_Id, delta_time: f32) -> b8 {
    return global_renderer_backend.end_frame(u32(window_context_id), delta_time)
}