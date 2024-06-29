package renderer_vulkan

import "core:strings"
import "core:log"
import "base:runtime"
import "core:math"

import vk "vendor:vulkan"

import "../../platform"
import "../../utils"
import "../../mathx"

@private
global_context : Vulkan_Context

@(private="file")
global_window_contexts : utils.Free_List(Vulkan_Window_Context)

@(private="file")
vk_debug_utils_messenger_callback :: proc "system" (
                                            messageSeverity: vk.DebugUtilsMessageSeverityFlagsEXT,
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

@(private="file")
vk_find_memory_index :: proc(type_filter: u32, property_flags: vk.MemoryPropertyFlags) -> u32 {
    memory_properties: vk.PhysicalDeviceMemoryProperties
    vk.GetPhysicalDeviceMemoryProperties(global_context.device.physical_device, &memory_properties)

    for i in 0..<memory_properties.memoryTypeCount {
        // Check each memory type to see if its bit is set to 1
        if type_filter & (1 << i) != 0 &&
           memory_properties.memoryTypes[i].propertyFlags & property_flags == property_flags {
            return i
        }
    }

    log.warn("Failed to find suitable memory type")
    return math.max(u32)
}

@(private="file")
vk_create_command_buffers :: proc(window_context: ^Vulkan_Window_Context) {
    if window_context.graphics_command_buffers == nil {
        window_context.graphics_command_buffers = make([]Vulkan_Command_Buffer,
                                                        len(window_context.swapchain.images))
    }

    for i in 0..<len(window_context.swapchain.images) {
        if window_context.graphics_command_buffers[i].handle != nil {
            vk_command_buffer_free(global_context.device.graphics_command_pool,
                                   &window_context.graphics_command_buffers[i])
        }
        window_context.graphics_command_buffers[i] = {}
        vk_command_buffer_allocate(global_context.device.graphics_command_pool,
                                   true,
                                   &window_context.graphics_command_buffers[i])
    }

    log.debug("Vulkan command buffers created")
}

@(private="file")
vk_destroy_command_buffers :: proc(window_context: ^Vulkan_Window_Context) {
    for i in 0..<len(window_context.swapchain.images) {
        if window_context.graphics_command_buffers[i].handle != nil {
            vk_command_buffer_free(global_context.device.graphics_command_pool,
                                    &window_context.graphics_command_buffers[i])
            window_context.graphics_command_buffers[i].handle = nil
        }
    }
    
    if window_context.graphics_command_buffers != nil {
        delete(window_context.graphics_command_buffers)
        window_context.graphics_command_buffers = nil
    }

    log.debug("Vulkan command buffers destroyed")
}

@(private="file")
vk_regenerate_frame_buffers :: proc(window_context: ^Vulkan_Window_Context,
                                    swapchain: ^Vulkan_Swapchain,
                                    render_pass: ^Vulkan_Render_Pass) {
    for i in 0..<len(swapchain.images) {
        attachment_count := u32(2)
        attachments := make([]vk.ImageView, attachment_count, context.temp_allocator)
        attachments[0] = swapchain.image_views[i]
        attachments[1] = swapchain.depth_attachment.view

        vk_frame_buffer_create(render_pass,
                               window_context.frame_buffer_width,
                               window_context.frame_buffer_height,
                               attachments,
                               &swapchain.frame_buffers[i])
    }

    log.debug("Vulkan frame buffers regenerated")
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

    // Function pointers
    global_context.find_memory_index = vk_find_memory_index

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
        available_layers := make([]vk.LayerProperties,
                                 available_layers_count,
                                 context.temp_allocator)
        if vk.EnumerateInstanceLayerProperties(&available_layers_count,
                                               raw_data(available_layers)) != vk.Result.SUCCESS {
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

        result = vk.CreateDebugUtilsMessengerEXT(global_context.instance,
                                                 &debug_utils_create_info,
                                                 global_context.allocator,
                                                 &global_context.debug_utils_messenger)
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
        vk.DestroyDebugUtilsMessengerEXT(global_context.instance,
                                         global_context.debug_utils_messenger,
                                         global_context.allocator)
        log.debug("Vulkan debug utils messenger destroyed")
    }

    vk.DestroyInstance(global_context.instance, global_context.allocator)
    log.debug("Vulkan instance destroyed")

    utils.destroy_free_list(&global_window_contexts)
}

init_window :: proc(instance: platform.Instance, handle: platform.Handle,
                    width: u32, height: u32) -> (u32, b8) {
    window_context := Vulkan_Window_Context{
        instance = instance,
        handle = handle,
        frame_buffer_width = width,
        frame_buffer_height = height,
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

    // Swapchain creation
    vk_swapchain_create(&window_context, window_context.frame_buffer_width,
                        window_context.frame_buffer_height, &window_context.swapchain)

    // Render pass creation
    vk_render_pass_create(&window_context, &window_context.main_render_pass,
                          mathx.Vector4{0, 0, f32(window_context.frame_buffer_width),
                                              f32(window_context.frame_buffer_height)},
                          mathx.Vector4{0, 0, 0.2, 1},
                          1.0, 0)

    // Swapachain framebuffers
    window_context.swapchain.frame_buffers = make([]Vulkan_Frame_Buffer,
                                                  len(window_context.swapchain.images))
    vk_regenerate_frame_buffers(&window_context,
                                &window_context.swapchain,
                                &window_context.main_render_pass)

    // Create command buffers
    vk_create_command_buffers(&window_context)

    // Create sync objects
    window_context.image_available_semaphores = make([]vk.Semaphore,
                                                     window_context.swapchain.max_frames_in_flight)
    window_context.queue_complete_semaphores = make([]vk.Semaphore,
                                                    window_context.swapchain.max_frames_in_flight)
    window_context.in_flight_fences = make([]Vulkan_Fence,
                                           window_context.swapchain.max_frames_in_flight)

    for i in 0..<window_context.swapchain.max_frames_in_flight {
        semaphore_create_info := vk.SemaphoreCreateInfo{
            sType = vk.StructureType.SEMAPHORE_CREATE_INFO,
            pNext = nil,
            flags = {},
        }
        result := vk.CreateSemaphore(global_context.device.logical_device,
                                     &semaphore_create_info,
                                     global_context.allocator,
                                     &window_context.image_available_semaphores[i])
        if result != vk.Result.SUCCESS {
            log.error("Failed to create image available semaphore")
            return {}, false
        }

        result = vk.CreateSemaphore(global_context.device.logical_device,
                                    &semaphore_create_info,
                                    global_context.allocator,
                                    &window_context.queue_complete_semaphores[i])
        if result != vk.Result.SUCCESS {
            log.error("Failed to create queue complete semaphore")
            return {}, false
        }

        // Create the fence in a signaled state, indicating that the first frame has already been
        // "rendered".
        // This will prevent the application from waiting indefinitely for the first frame to render
        // since it cannot be rendered until a frame is "rendered" before it.
        vk_fence_create(true, &window_context.in_flight_fences[i])
    }

    // In flight fences should not yet exist at this point, so clear the list. There are stored in
    // pointers because the initial state should be 0, and will be 0 when not in use. Actual fences
    // are not owned by this list.
    window_context.images_in_flight = make([]^Vulkan_Fence, len(window_context.swapchain.images))

    log.info("Vulkan window initialized successfully")

    return utils.add_to_free_list(&global_window_contexts, window_context), true
}

destroy_window :: proc(window_context_id: u32) {
    window_context := utils.get_from_free_list(&global_window_contexts, window_context_id)

    vk.DeviceWaitIdle(global_context.device.logical_device)

    // Destroy sync objects
    if window_context.images_in_flight != nil {
        delete(window_context.images_in_flight)
        window_context.images_in_flight = nil
    }

    for i in 0..<window_context.swapchain.max_frames_in_flight {
        vk.DestroySemaphore(global_context.device.logical_device,
                            window_context.image_available_semaphores[i],
                            global_context.allocator)
        vk.DestroySemaphore(global_context.device.logical_device,
                            window_context.queue_complete_semaphores[i],
                            global_context.allocator)
        vk_fence_destroy(&window_context.in_flight_fences[i])
    }
    if window_context.image_available_semaphores != nil {
        delete(window_context.image_available_semaphores)
        window_context.image_available_semaphores = nil
    }

    if window_context.queue_complete_semaphores != nil {
        delete(window_context.queue_complete_semaphores)
        window_context.queue_complete_semaphores = nil
    }

    if window_context.in_flight_fences != nil {
        delete(window_context.in_flight_fences)
        window_context.in_flight_fences = nil
    }
    
    // Destroy command buffers
    vk_destroy_command_buffers(window_context)

    // Destroy swapchain framebuffers
    for i in 0..<len(window_context.swapchain.frame_buffers) {
        vk_frame_buffer_destroy(&window_context.swapchain.frame_buffers[i])
    }
    delete(window_context.swapchain.frame_buffers)
    window_context.swapchain.frame_buffers = nil

    // Destroy render pass
    vk_render_pass_destroy(&window_context.main_render_pass)

    // Destroy swapchain
    vk_swapchain_destroy(window_context, &window_context.swapchain)

    // Destroy Vulkan surface
    vk.DestroySurfaceKHR(global_context.instance, window_context.surface, global_context.allocator)

    utils.remove_from_free_list(&global_window_contexts, window_context_id)
    log.debug("Vulkan surface destroyed")
}

resize_window :: proc(window_context_id: u32, width: u32, height: u32) {
    window_context := utils.get_from_free_list(&global_window_contexts, window_context_id)

    window_context.frame_buffer_width = width
    window_context.frame_buffer_height = height

    //vk_swapchain_recreate(&window_context, window_context.frame_buffer_width,
    //                      window_context.frame_buffer_height, &window_context.swapchain)
    //
    //vk_regenerate_frame_buffers(&window_context,
    //                            &window_context.swapchain,
    //                            &window_context.main_render_pass)
    //
    //vk_destroy_command_buffers(window_context)
    //vk_create_command_buffers(window_context)

    //log.debug("Vulkan window resized")
}

resize :: proc(width: i32, height: i32) {

}

begin_frame :: proc(delta_time: f32) -> b8 {
    return true
}

end_frame :: proc(delta_time: f32) -> b8 {
    return true
}