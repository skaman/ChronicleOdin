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
Vulkan_Swapchain :: struct {
    image_format: vk.SurfaceFormatKHR,
    max_frames_in_flight: u8,
    handle: vk.SwapchainKHR,
    images: []vk.Image,
    image_views: []vk.ImageView,

    depth_attachment: Vulkan_Image,
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
Vulkan_Window_Context :: struct {
    instance: platform.Instance,
    handle: platform.Handle,
    surface: vk.SurfaceKHR,

    framebuffer_width: u32,
    framebuffer_height: u32,

    swapchain: Vulkan_Swapchain,
    main_renderpass: Vulkan_Render_Pass,

    graphics_command_buffers: []Vulkan_Command_Buffer,

    image_index: u32,
    current_frame: u32,

    recreate_swapchain: b8,
}