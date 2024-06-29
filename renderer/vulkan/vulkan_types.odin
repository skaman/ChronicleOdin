package renderer_vulkan

import "base:runtime"

import vk "vendor:vulkan"

import "../../platform"
import "../../mathx"

@private
Vulkan_Context :: struct {
    instance: vk.Instance,
    allocator: ^vk.AllocationCallbacks,
    debug_utils_messenger: vk.DebugUtilsMessengerEXT,
    debug_utils_context: runtime.Context,
    device: Vulkan_Device,

    find_memory_index: proc(type_filter: u32, property_flags: vk.MemoryPropertyFlags) -> u32,
}

@private
Vulkan_Device :: struct {
    physical_device: vk.PhysicalDevice,
    logical_device: vk.Device,
    swapchain_support: Vulkan_Swapchain_Support_Info,
    graphics_queue_index: u32,
    present_queue_index: u32,
    transfer_queue_index: u32,

    graphics_queue: vk.Queue,
    present_queue: vk.Queue,
    transfer_queue: vk.Queue,

    graphics_command_pool: vk.CommandPool,

    properties: vk.PhysicalDeviceProperties,
    features: vk.PhysicalDeviceFeatures,
    memory: vk.PhysicalDeviceMemoryProperties,

    depth_format: vk.Format,
}

@private
Vulkan_Image :: struct {
    handle: vk.Image,
    memory: vk.DeviceMemory,
    view: vk.ImageView,
    width: u32,
    height: u32,
}

@private
Vulkan_Render_Pass_State :: enum {
    Ready,
    Recording,
    In_Render_Pass,
    Recording_Ended,
    Submitted,
    Not_Allocated,
}

@private
Vulkan_Render_Pass :: struct {
    handle: vk.RenderPass,
    render_area: mathx.Vector4,
    clear_color: mathx.Vector4,

    depth: f32,
    stencil: u32,

    state: Vulkan_Render_Pass_State,
}

@private
Vulkan_Frame_Buffer :: struct {
    handle: vk.Framebuffer,
    attachments: []vk.ImageView,
    render_pass: ^Vulkan_Render_Pass,
}

@private
Vulkan_Swapchain :: struct {
    image_format: vk.SurfaceFormatKHR,
    max_frames_in_flight: u8,
    handle: vk.SwapchainKHR,
    images: []vk.Image,
    image_views: []vk.ImageView,

    depth_attachment: Vulkan_Image,

    // framebuffers used for on-screen rendering
    frame_buffers: []Vulkan_Frame_Buffer,
}

@private
Vulkan_Command_Buffer_State :: enum {
    Ready,
    Recording,
    In_Render_Pass,
    Recording_Ended,
    Submitted,
    Not_Allocated,
}

@private
Vulkan_Command_Buffer :: struct {
    handle: vk.CommandBuffer,

    state: Vulkan_Command_Buffer_State,
}

@private
Vulkan_Swapchain_Support_Info :: struct {
    capabilities: vk.SurfaceCapabilitiesKHR,
    surface_formats: []vk.SurfaceFormatKHR,
    present_modes: []vk.PresentModeKHR,
}

@private
Vulkan_Fence :: struct {
    handle: vk.Fence,
    is_signaled: b8,
}

@private
Vulkan_Window_Context :: struct {
    instance: platform.Instance,
    handle: platform.Handle,
    surface: vk.SurfaceKHR,

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

    swapchain: Vulkan_Swapchain,
    main_render_pass: Vulkan_Render_Pass,

    graphics_command_buffers: []Vulkan_Command_Buffer,
    image_available_semaphores: []vk.Semaphore,
    queue_complete_semaphores: []vk.Semaphore,

    in_flight_fences: []Vulkan_Fence,

    
    images_in_flight: []^Vulkan_Fence,      // Hold pointers to fences which exist and are owned
                                            // elsewhere

    image_index: u32,
    current_frame: u32,

    recreating_swapchain: b8,
}