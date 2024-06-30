package renderer

import rt "types"
import "vulkan"
import "../platform"

// Struct to define the renderer backend interface
@(private="file")
Renderer_Backend :: struct {
    init: proc(app_name: string) -> b8,             // Function to initialize the renderer backend
    destroy: proc(),                                // Function to destroy the renderer backend

    init_window: proc(instance: platform.Instance,  // Function to initialize a window
                      handle: platform.Handle,
                      width: u32, height: u32) -> (rt.Window_Context_Handle, b8),
    destroy_window: proc(window_context_handle: rt.Window_Context_Handle),   // Function to destroy a window
    resize_window: proc(window_context_handle: rt.Window_Context_Handle,     // Function to resize a window
                        width: u32, height: u32),

    begin_frame: proc(window_context_handle: rt.Window_Context_Handle,       // Function to begin rendering a frame
                      delta_time: f32) -> b8,
    end_frame: proc(window_context_handle: rt.Window_Context_Handle,         // Function to end rendering a frame
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
init :: proc(backend: rt.Renderer_Backend_Type, app_name: string) -> b8 {
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
                    width: u32, height: u32) -> (rt.Window_Context_Handle, b8) {
    return global_renderer_backend.init_window(instance, handle, width, height)
}

// Destroys the specified window.
//
// Parameters:
//   window_context_handle: rt.Window_Context_Handle - The ID of the window context to destroy.
destroy_window :: proc(window_context_handle: rt.Window_Context_Handle) {
    assert(window_context_handle != nil, "Invalid window context handle")

    global_renderer_backend.destroy_window(window_context_handle)
}

// Resizes the specified window.
//
// Parameters:
//   window_context_handle: rt.Window_Context_Handle - The ID of the window context to resize.
//   width: u32 - The new width of the window.
//   height: u32 - The new height of the window.
resize_window :: proc(window_context_handle: rt.Window_Context_Handle, width: u32, height: u32) {
    assert(window_context_handle != nil, "Invalid window context handle")
    
    global_renderer_backend.resize_window(window_context_handle, width, height)
}

// Begins rendering a frame for the specified window.
//
// Parameters:
//   window_context_handle: rt.Window_Context_Handle - The ID of the window context to begin
//                                                     rendering.
//   delta_time: f32 - The time since the last frame.
//
// Returns:
//   b8 - True if the frame was successfully begun, otherwise false.
begin_frame :: proc(window_context_handle: rt.Window_Context_Handle, delta_time: f32) -> b8 {
    assert(window_context_handle != nil, "Invalid window context handle")
    
    return global_renderer_backend.begin_frame(window_context_handle, delta_time)
}

// Ends rendering a frame for the specified window.
//
// Parameters:
//   window_context_handle: rt.Window_Context_Handle - The ID of the window context to end
//                                                     rendering.
//   delta_time: f32 - The time since the last frame.
//
// Returns:
//   b8 - True if the frame was successfully ended, otherwise false.
end_frame :: proc(window_context_handle: rt.Window_Context_Handle, delta_time: f32) -> b8 {
    assert(window_context_handle != nil, "Invalid window context handle")
    
    return global_renderer_backend.end_frame(window_context_handle, delta_time)
}