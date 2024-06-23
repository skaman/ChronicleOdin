package renderer_vulkan

import "core:strings"
import "core:log"
import "base:runtime"

import vk "vendor:vulkan"

import "../../platform"

@private
Vulkan_Context :: struct {
    instance: vk.Instance,
    allocator: ^vk.AllocationCallbacks,
    debug_utils_messenger: vk.DebugUtilsMessengerEXT,
    debug_utils_context: runtime.Context,
}

@private
global_context : Vulkan_Context

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
        vk.StructureType.APPLICATION_INFO,          // sType
        nil,                                        // pNext
        strings.unsafe_string_to_cstring(app_name), // pApplicationName
        vk.MAKE_VERSION(1, 0, 0),                   // applicationVersion
        "Chronicle Engine",                         // pEngineName
        vk.MAKE_VERSION(1, 0, 0),                   // engineVersion
        vk.API_VERSION_1_2,                         // apiVersion
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

    create_info := vk.InstanceCreateInfo{
        vk.StructureType.INSTANCE_CREATE_INFO, // sType
        nil,                                   // pNext
        {},                                    // flags
        &app_info,                             // pApplicationInfo
        u32(len(validation_layers)),           // enabledLayerCount
        raw_data(validation_layers),           // ppEnabledLayerNames
        u32(len(required_extensions)),         // enabledExtensionCount
        raw_data(required_extensions),         // ppEnabledExtensionNames
    }

    result := vk.CreateInstance(&create_info, global_context.allocator, &global_context.instance)
    if result != vk.Result.SUCCESS {
        log.errorf("Failed to create Vulkan instance: %v", result)
        return false
    }

    vk.load_proc_addresses_instance(global_context.instance)

    log.debug("Vulkan instance created")

    when ODIN_DEBUG {
        global_context.debug_utils_context = context

        debug_utils_create_info := vk.DebugUtilsMessengerCreateInfoEXT{
            vk.StructureType.DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT, // sType
            nil,                                                    // pNext
            {},                                                     // flags
            {.ERROR | .WARNING | .INFO | .VERBOSE},                 // messageSeverity
            {.GENERAL | .PERFORMANCE | .VALIDATION},                // messageType
            vk_debug_utils_messenger_callback,                      // pfnUserCallback
            &global_context.debug_utils_context,                    // pUserData
        }

        global_context.debug_utils_messenger = vk.DebugUtilsMessengerEXT{}
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
    when ODIN_DEBUG {
        vk.DestroyDebugUtilsMessengerEXT(global_context.instance, global_context.debug_utils_messenger, global_context.allocator)
        log.debug("Vulkan debug utils messenger destroyed")
    }

    vk.DestroyInstance(global_context.instance, global_context.allocator)
    log.debug("Vulkan instance destroyed")
}

resize :: proc(width: i32, height: i32) {

}

begin_frame :: proc(delta_time: f32) -> b8 {
    return true
}

end_frame :: proc(delta_time: f32) -> b8 {
    return true
}