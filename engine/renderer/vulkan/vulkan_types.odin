package renderer_vulkan

import "base:runtime"

import vk "vendor:vulkan"

import "../../platform"
import "../../mathx"

// Struct to hold the global Vulkan context.
@private
Vulkan_Context :: struct {
    instance: vk.Instance,                              // Vulkan instance.
    allocator: ^vk.AllocationCallbacks,                 // Pointer to Vulkan allocation callbacks.
    debug_utils_messenger: vk.DebugUtilsMessengerEXT,   // Vulkan debug utils messenger.
    debug_utils_context: runtime.Context,               // Context for Vulkan debug utils.
    device: Vulkan_Device,                              // Vulkan device information.

    find_memory_index: proc(type_filter: u32,           // Function to find memory index.
                            property_flags: vk.MemoryPropertyFlags) -> u32,
}

// Struct to hold Vulkan device information.
@private
Vulkan_Device :: struct {
    physical_device: vk.PhysicalDevice,                 // Physical Vulkan device.
    logical_device: vk.Device,                          // Logical Vulkan device.
    swapchain_support: Vulkan_Swapchain_Support_Info,   // Swapchain support information.
    graphics_queue_index: u32,                          // Index of the graphics queue.
    present_queue_index: u32,                           // Index of the present queue.
    transfer_queue_index: u32,                          // Index of the transfer queue.

    graphics_queue: vk.Queue,                           // Graphics queue.
    present_queue: vk.Queue,                            // Present queue.
    transfer_queue: vk.Queue,                           // Transfer queue.

    graphics_command_pool: vk.CommandPool,              // Command pool for graphics commands.

    properties: vk.PhysicalDeviceProperties,            // Physical device properties.
    features: vk.PhysicalDeviceFeatures,                // Physical device features.
    memory: vk.PhysicalDeviceMemoryProperties,          // Physical device memory properties.

    depth_format: vk.Format,                            // Depth format.
}

// Struct to hold Vulkan image information.
@private
Vulkan_Image :: struct {
    handle: vk.Image,           // Vulkan image handle.
    memory: vk.DeviceMemory,    // Vulkan device memory.
    view: vk.ImageView,         // Vulkan image view.
    width: u32,                 // Image width.
    height: u32,                // Image height.
}

// Enum to represent the state of a Vulkan render pass.
@private
Vulkan_Render_Pass_State :: enum {
    Ready,
    Recording,
    In_Render_Pass,
    Recording_Ended,
    Submitted,
    Not_Allocated,
}

// Struct to hold Vulkan render pass information.
@private
Vulkan_Render_Pass :: struct {
    handle: vk.RenderPass,              // Vulkan render pass handle.
    render_area: mathx.Vector4,         // Render area.
    clear_color: mathx.Vector4,         // Clear color.

    depth: f32,                         // Depth value.
    stencil: u32,                       // Stencil value.

    state: Vulkan_Render_Pass_State,    // State of the render pass.
}

// Struct to hold Vulkan frame buffer information.
@private
Vulkan_Frame_Buffer :: struct {
    handle: vk.Framebuffer,             // Vulkan framebuffer handle.
    attachments: []vk.ImageView,        // Attachments for the framebuffer.
    render_pass: ^Vulkan_Render_Pass,   // Pointer to the associated render pass.
}

// Struct to hold Vulkan swapchain information.
@private
Vulkan_Swapchain :: struct {
    image_format: vk.SurfaceFormatKHR,      // Format of the swapchain images.
    max_frames_in_flight: u8,               // Maximum number of frames in flight.
    handle: vk.SwapchainKHR,                // Vulkan swapchain handle.
    images: []vk.Image,                     // Swapchain images.
    image_views: []vk.ImageView,            // Image views for the swapchain images.

    depth_attachment: Vulkan_Image,         // Depth attachment image.

    frame_buffers: []Vulkan_Frame_Buffer,   // Framebuffers used for on-screen rendering.
}

// Enum to represent the state of a Vulkan command buffer.
@private
Vulkan_Command_Buffer_State :: enum {
    Ready,
    Recording,
    In_Render_Pass,
    Recording_Ended,
    Submitted,
    Not_Allocated,
}

// Struct to hold Vulkan command buffer information.
@private
Vulkan_Command_Buffer :: struct {
    handle: vk.CommandBuffer,               // Vulkan command buffer handle.
    state: Vulkan_Command_Buffer_State,     // State of the command buffer.
}

// Struct to hold Vulkan swapchain support information.
@private
Vulkan_Swapchain_Support_Info :: struct {
    capabilities: vk.SurfaceCapabilitiesKHR,    // Surface capabilities.
    surface_formats: []vk.SurfaceFormatKHR,     // Supported surface formats.
    present_modes: []vk.PresentModeKHR,         // Supported present modes.
}

// Struct to hold Vulkan fence information.
@private
Vulkan_Fence :: struct {
    handle: vk.Fence,   // Vulkan fence handle.
    is_signaled: b8,    // Indicates if the fence is signaled.
}

// Struct to hold Vulkan window context information.
@private
Vulkan_Window_Context :: struct {
    instance: platform.Instance,            // Platform instance for the window.
    handle: platform.Handle,                // Handle for the window.
    surface: vk.SurfaceKHR,                 // Vulkan surface for the window.

    frame_buffer_width: u32,                // The frame buffer current width
    frame_buffer_height: u32,               // The frame buffer current height
    frame_buffer_size_generation: u32,      // Current generation of the frame buffer size. If it
                                            // doesn't match frame_buffer_size_last_generation, a
                                            // new  one should be generated
    frame_buffer_new_width: u32,            // The new width of the frame buffer (for regeneration)
    frame_buffer_new_height: u32,           // The new height of the frame buffer (for regeneration)
    frame_buffer_size_last_generation: u32, // The gemeration of the frame buffer when it wast last
                                            // created. Set to frame_buffer_size_generation when
                                            // updated.

    swapchain: Vulkan_Swapchain,            // Vulkan swapchain information.
    main_render_pass: Vulkan_Render_Pass,   // Main render pass for the window.

    graphics_command_buffers: []Vulkan_Command_Buffer,  // Command buffers for graphics commands.
    image_available_semaphores: []vk.Semaphore,         // Semaphores for image availability.
    queue_complete_semaphores: []vk.Semaphore,          // Semaphores for queue completion.

    in_flight_fences: []Vulkan_Fence,       // Fences for in-flight frames.

    
    images_in_flight: []^Vulkan_Fence,      // Hold pointers to fences which exist and are owned
                                            // elsewhere

    image_index: u32,                       // Index of the current image in the swapchain.
    current_frame: u32,                     // Index of the current frame.

    recreating_swapchain: b8,               // Flag indicating if the swapchain is being recreated.
}