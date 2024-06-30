package renderer

import "core:math/linalg"

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

    // Function to destroy a window
    destroy_window: proc(window_context_handle: rt.Window_Context_Handle),

    // Function to resize a window
    resize_window: proc(window_context_handle: rt.Window_Context_Handle,
                        width: u32, height: u32),

    // Function to begin rendering a frame
    begin_frame: proc(window_context_handle: rt.Window_Context_Handle,
                      delta_time: f32) -> b8,

    // Function to end rendering a frame
    end_frame: proc(window_context_handle: rt.Window_Context_Handle,
                    delta_time: f32) -> b8,

    // Function to update the global state
    update_global_state: proc(window_context_handle: rt.Window_Context_Handle,
                              projection: linalg.Matrix4f32, view: linalg.Matrix4f32,
                              view_position: linalg.Vector3f32,
                              ambient_color: linalg.Vector4f32, mode: i32),
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
            global_renderer_backend.update_global_state = vulkan.update_global_state
    }

    return global_renderer_backend.init(app_name)
}

// Destroys the renderer backend.
destroy :: proc() {
    global_renderer_backend.destroy()
    global_renderer_backend = {}
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

// Updates the global state of the ubo
//
// Parameters:
//   window_context_handle: rt.Window_Context_Handle - The ID of the window context.
//   projection: linalg.Matrix4f32 - The projection matrix.
//   view: linalg.Matrix4f32 - The view matrix.
//   view_position: linalg.Vector3f32 - The view position.
//   ambient_color: linalg.Vector4f32 - The ambient color.
//   mode: i32 - ????.
update_global_state :: proc(window_context_handle: rt.Window_Context_Handle,
                            projection: linalg.Matrix4f32, view: linalg.Matrix4f32,
                            view_position: linalg.Vector3f32,
                            ambient_color: linalg.Vector4f32, mode: i32) {
    assert(window_context_handle != nil, "Invalid window context handle")

    global_renderer_backend.update_global_state(window_context_handle, projection, view,
                                                view_position, ambient_color, mode)
}