package renderer_vulkan

import "core:strings"
import "core:log"
import "base:runtime"

import vk "vendor:vulkan"

import "../../platform"
import "../../utils"

@private
Vulkan_Context :: struct {
    instance: vk.Instance,
    allocator: ^vk.AllocationCallbacks,
    debug_utils_messenger: vk.DebugUtilsMessengerEXT,
    debug_utils_context: runtime.Context,
    device: Vulkan_Device,
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

    properties: vk.PhysicalDeviceProperties,
    features: vk.PhysicalDeviceFeatures,
    memory: vk.PhysicalDeviceMemoryProperties,
}

@private
Vulkan_Swapchain_Support_Info :: struct {
    capabilities: vk.SurfaceCapabilitiesKHR,
    surface_formats: []vk.SurfaceFormatKHR,
    present_modes: []vk.PresentModeKHR,
}

Vulkan_Render_Window_Context :: struct {
    instance: platform.Instance,
    handle: platform.Handle,
    surface: vk.SurfaceKHR,
}

@private
global_context : Vulkan_Context

@(private="file")
global_window_contexts : utils.Free_List(Vulkan_Render_Window_Context)

@(private="file")
vk_debug_utils_messenger_callback :: proc "system" (messageSeverity: vk.DebugUtilsMessageSeverityFlagsEXT,
                                                    messageTypes: vk.DebugUtilsMessageTypeFlagsEXT,
                                                    pCallbackData: ^vk.DebugUtilsMessengerCallbackDataEXT,
                                                    pUserData: rawptr) -> b32 {
    context = (^runtime.Context)(pUserData)^
    if vk.DebugUtilsMessageSeverityFlagsEXT.ERROR in messageSeverity {
        log.errorf("Vulkan: %v", pCallbackData.pMessage)
    }
    else if vk.DebugUtilsMessageSeverityFlagsEXT.WARNING in messageSeverity {
        log.warnf("Vulkan: %v", pCallbackData.pMessage)
    }
    else if vk.DebugUtilsMessageSeverityFlagsEXT.INFO in messageSeverity {
        log.infof("Vulkan: %v", pCallbackData.pMessage)
    }
    else if vk.DebugUtilsMessageSeverityFlagsEXT.VERBOSE in messageSeverity {
        log.debugf("Vulkan: %v", pCallbackData.pMessage)
    }
    return false
}

init :: proc(app_name: string) -> b8 {
    utils.init_free_list(&global_window_contexts)

    vulkan_handle := platform.load_module(VULKAN_LIBRARY_NAME)
    if vulkan_handle == nil {
        log.error("Failed to load Vulkan library")
        return false
    }

    proc_address := platform.get_module_symbol(vulkan_handle, "vkGetInstanceProcAddr")
    if proc_address == nil {
        log.error("Failed to get Vulkan instance proc address")
        return false
    }

    
    vk.load_proc_addresses(proc_address)

    // TODO: Add a custom allocator
    global_context.allocator = nil

    app_info := vk.ApplicationInfo{
        sType = vk.StructureType.APPLICATION_INFO,
        pNext = nil,
        pApplicationName = strings.unsafe_string_to_cstring(app_name),
        applicationVersion = vk.MAKE_VERSION(1, 0, 0),
        pEngineName = "Chronicle Engine",
        engineVersion = vk.MAKE_VERSION(1, 0, 0),
        apiVersion = vk.API_VERSION_1_2,
    }

    // Required extensions
    required_extensions := make([dynamic]cstring, context.temp_allocator)
    append(&required_extensions, vk.KHR_SURFACE_EXTENSION_NAME)
    for platform_extension in VULKAN_PLATFORM_EXTENSIONS {
        append(&required_extensions, platform_extension)
    }
    when ODIN_DEBUG {
        append(&required_extensions, vk.EXT_DEBUG_UTILS_EXTENSION_NAME)
    }

    log.debugf("Required extensions: %v", required_extensions)

    // Validation layers
    validation_layers := make([dynamic]cstring, context.temp_allocator)
    when ODIN_DEBUG {
        append(&validation_layers, "VK_LAYER_KHRONOS_validation")

        available_layers_count : u32
        if vk.EnumerateInstanceLayerProperties(&available_layers_count, nil) != vk.Result.SUCCESS {
            log.error("Failed to enumerate Vulkan instance layers count")
            return false
        }
        available_layers := make([]vk.LayerProperties, available_layers_count, context.temp_allocator)
        if vk.EnumerateInstanceLayerProperties(&available_layers_count, raw_data(available_layers)) != vk.Result.SUCCESS {
            log.error("Failed to enumerate Vulkan instance layers")
            return false
        }

        for layer in validation_layers {
            found := false
            for available_layer in available_layers {
                layer_name := available_layer.layerName
                if layer == cstring(&layer_name[0]) {
                    found = true
                    break
                }
            }
            if found {
                log.debugf("Validation layer %v found", layer)
            }
            else {
                log.errorf("Validation layer %v not found", layer)
                return false
            }
        }
    }

    // Instance creation
    create_info := vk.InstanceCreateInfo{
        sType = vk.StructureType.INSTANCE_CREATE_INFO,
        pNext = nil,
        flags = {},
        pApplicationInfo = &app_info,
        enabledLayerCount =  u32(len(validation_layers)),
        ppEnabledLayerNames = raw_data(validation_layers),
        enabledExtensionCount = u32(len(required_extensions)),
        ppEnabledExtensionNames = raw_data(required_extensions),
    }

    result := vk.CreateInstance(&create_info, global_context.allocator, &global_context.instance)
    if result != vk.Result.SUCCESS {
        log.errorf("Failed to create Vulkan instance: %v", result)
        return false
    }
    vk.load_proc_addresses_instance(global_context.instance)

    log.debug("Vulkan instance created")

    // Debug utils messenger
    when ODIN_DEBUG {
        global_context.debug_utils_context = context

        debug_utils_create_info := vk.DebugUtilsMessengerCreateInfoEXT{
            sType = vk.StructureType.DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
            pNext = nil,
            flags = {},
            messageSeverity = {.VERBOSE, .INFO, .WARNING, .ERROR},
            messageType = {.GENERAL, .PERFORMANCE, .VALIDATION},
            pfnUserCallback = vk_debug_utils_messenger_callback,
            pUserData = &global_context.debug_utils_context,
        }

        result = vk.CreateDebugUtilsMessengerEXT(global_context.instance, &debug_utils_create_info, global_context.allocator, &global_context.debug_utils_messenger)
        if result != vk.Result.SUCCESS {
            log.errorf("Failed to create Vulkan debug utils messenger: %v", result)
            return false
        }
        log.debug("Vulkan debug utils messenger created")
    }

    log.info("Vulkan renderer initialized successfully")

    return true
}

destroy :: proc() {
    vk_device_destroy()

    when ODIN_DEBUG {
        vk.DestroyDebugUtilsMessengerEXT(global_context.instance, global_context.debug_utils_messenger, global_context.allocator)
        log.debug("Vulkan debug utils messenger destroyed")
    }

    vk.DestroyInstance(global_context.instance, global_context.allocator)
    log.debug("Vulkan instance destroyed")

    utils.destroy_free_list(&global_window_contexts)
}

init_window :: proc(instance: platform.Instance, handle: platform.Handle) -> (u32, b8) {
    window_context := Vulkan_Render_Window_Context{
        instance,
        handle,
        {},
    }

    if !vk_platform_create_vulkan_surface(&window_context) {
        log.error("Failed to create Vulkan surface")
        return {}, false
    }

    // Device creation
    if global_context.device.physical_device == nil {
        if !vk_device_create(window_context.surface) {
            log.error("Failed to create Vulkan device")
            return {}, false
        }
    }

    log.info("Vulkan window initialized successfully")

    return utils.add_to_free_list(&global_window_contexts, window_context), true
}

destroy_window :: proc(window_context_id: u32) {
    window_context := utils.get_from_free_list(&global_window_contexts, window_context_id)
    vk.DestroySurfaceKHR(global_context.instance, window_context.surface, global_context.allocator)
    utils.remove_from_free_list(&global_window_contexts, window_context_id)
    log.debug("Vulkan surface destroyed")
}

resize :: proc(width: i32, height: i32) {

}

begin_frame :: proc(delta_time: f32) -> b8 {
    return true
}

end_frame :: proc(delta_time: f32) -> b8 {
    return true
}