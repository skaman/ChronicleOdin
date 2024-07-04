package renderer_vulkan

import "core:strings"
import "core:log"
import "base:runtime"
import "core:math"
import "core:mem"
import "core:math/linalg"

import vk "vendor:vulkan"

import rt "../types"

import "../../platform"
import "../../utils"

// Contains the global context for Vulkan, including Vulkan instance and debug context.
@private
g_context : Vulkan_Context

// Callback function for Vulkan debug utils messenger.
//
// Parameters:
//   messageSeverity: vk.DebugUtilsMessageSeverityFlagsEXT - Severity of the debug message.
//   messageTypes: vk.DebugUtilsMessageTypeFlagsEXT - Type of the debug message.
//   pCallbackData: ^vk.DebugUtilsMessengerCallbackDataEXT - Pointer to callback data containing message information.
//   pUserData: rawptr - Pointer to user data passed to the callback.
//
// Returns:
//   b32 - False to indicate that the callback did not handle the message.
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

// Finds a suitable memory type based on type filter and property flags.
//
// Parameters:
//   type_filter: u32 - The filter specifying acceptable memory types.
//   property_flags: vk.MemoryPropertyFlags - The desired properties of the memory.
//
// Returns:
//   u32 - The index of the suitable memory type, or the maximum u32 value if not found.
@(private="file")
vk_find_memory_index :: proc(type_filter: u32, property_flags: vk.MemoryPropertyFlags) -> u32 {
    memory_properties: vk.PhysicalDeviceMemoryProperties
    vk.GetPhysicalDeviceMemoryProperties(g_context.device.physical_device, &memory_properties)

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
vk_upload_data_range :: proc(pool: vk.CommandPool, fence: vk.Fence, queue: vk.Queue,
                             buffer: ^Vulkan_Buffer, offset: u64, size: u64, data: rawptr) {
    // Create a host-visible staging buffer to upload to. Mark it as the source of the transfer.
    flags: vk.MemoryPropertyFlags = {.HOST_VISIBLE, .HOST_COHERENT}
    staging: Vulkan_Buffer
    vk_buffer_create(size, {.TRANSFER_SRC}, flags, true, &staging)

    // Load the data into the staging buffer
    vk_buffer_load_data(&staging, 0, size, {}, data)

    // Perform the copy from staging to the device local buffer
    vk_buffer_copy_to(pool, fence, queue, staging.handle, 0, buffer.handle, offset, size)

    // Cleanup the staging buffer
    vk_buffer_destroy(&staging)
}

// Creates Vulkan command buffers for a given window context.
//
// Parameters:
//   window_context: ^Vulkan_Window_Context - Pointer to the window context.
@(private="file")
vk_create_command_buffers :: proc(window_context: ^Vulkan_Window_Context) {
    if window_context.graphics_command_buffers == nil {
        window_context.graphics_command_buffers = make([]Vulkan_Command_Buffer,
                                                        len(window_context.swapchain.images))
    }

    for i in 0..<len(window_context.swapchain.images) {
        if window_context.graphics_command_buffers[i].handle != nil {
            vk_command_buffer_free(g_context.device.graphics_command_pool,
                                   &window_context.graphics_command_buffers[i])
        }
        window_context.graphics_command_buffers[i] = {}
        vk_command_buffer_allocate(g_context.device.graphics_command_pool,
                                   true,
                                   &window_context.graphics_command_buffers[i])
    }

    log.debug("Vulkan command buffers created")
}

// Destroys Vulkan command buffers for a given window context.
//
// Parameters:
//   window_context: ^Vulkan_Window_Context - Pointer to the window context.
@(private="file")
vk_destroy_command_buffers :: proc(window_context: ^Vulkan_Window_Context) {
    for i in 0..<len(window_context.swapchain.images) {
        if window_context.graphics_command_buffers[i].handle != nil {
            vk_command_buffer_free(g_context.device.graphics_command_pool,
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

// Regenerates Vulkan frame buffers for a given window context, swapchain, and render pass.
//
// Parameters:
//   window_context: ^Vulkan_Window_Context - Pointer to the window context.
//   swapchain: ^Vulkan_Swapchain - Pointer to the swapchain.
//   render_pass: ^Vulkan_Render_Pass - Pointer to the render pass.
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

// Recreates the Vulkan swapchain for a given window context.
//
// Parameters:
//   window_context: ^Vulkan_Window_Context - Pointer to the window context.
//
// Returns:
//   b8 - True if the swapchain was successfully recreated, otherwise false.
@(private="file")
vk_recreate_swapchain :: proc(window_context: ^Vulkan_Window_Context) -> b8 {
    // If already being recreated, do no try again.
    if window_context.recreating_swapchain {
        log.debug("Already recreating swapchain. Booting.")
        return false
    }

    // Detect if the window is too small to be drawn to
    if window_context.frame_buffer_width == 0 || window_context.frame_buffer_height == 0 {
        log.debug("Window size is < 1 in a dimension. Booting.")
        return false
    }

    // Mark as recreating if the dimensions are valid
    window_context.recreating_swapchain = true

    // Wait for any operations to complete.
    vk.DeviceWaitIdle(g_context.device.logical_device)

    // Clear these out just in case.
    for i in 0..<len(window_context.images_in_flight) {
        window_context.images_in_flight[i] = nil
    }

    // Requery support.
    vk_query_swapchain_support(g_context.device.physical_device,
                               window_context.surface,
                               &g_context.device.swapchain_support)
    vk_device_detect_depth_format(&g_context.device)

    // Recreate the swapchain.
    vk_swapchain_recreate(window_context,
                          window_context.frame_buffer_new_width,
                          window_context.frame_buffer_new_height,
                          &window_context.swapchain)

    // Sync the frame buffer sizes with the new sizes.
    window_context.frame_buffer_width = window_context.frame_buffer_new_width
    window_context.frame_buffer_height = window_context.frame_buffer_new_height
    window_context.main_render_pass.render_area.z = f32(window_context.frame_buffer_width)
    window_context.main_render_pass.render_area.w = f32(window_context.frame_buffer_height)
    window_context.frame_buffer_new_width = 0
    window_context.frame_buffer_new_height = 0

    // Update frame buffer size generation.
    window_context.frame_buffer_size_last_generation = window_context.frame_buffer_size_generation

    // Cleanup swapchain
    for i in 0..<len(window_context.swapchain.images) {
        vk_command_buffer_free(g_context.device.graphics_command_pool,
                               &window_context.graphics_command_buffers[i])
    }

    // Frame buffers
    for i in 0..<len(window_context.swapchain.images) {
        vk_frame_buffer_destroy(&window_context.swapchain.frame_buffers[i])
    }

    window_context.main_render_pass.render_area = {
        0, 0, f32(window_context.frame_buffer_width), f32(window_context.frame_buffer_height),
    }

    vk_regenerate_frame_buffers(window_context, &window_context.swapchain,
                                &window_context.main_render_pass)

    vk_create_command_buffers(window_context)

    // Clear the recreating flag.
    window_context.recreating_swapchain = false

    return true
}

// Creates default Vulkan buffers.
//
// Parameters:
//   window_context: ^Vulkan_Window_Context - Pointer to the window context.
//
// Returns:
//   b8 - True if the buffers were successfully created, otherwise false.
@(private="file")
vk_create_buffers :: proc(window_context: ^Vulkan_Window_Context) -> b8 {
    memory_property_flags: vk.MemoryPropertyFlags = {.DEVICE_LOCAL}

    VERTEX_BUFFER_SIZE :: size_of(linalg.Vector3f32) * 1024 * 1024;
    if !vk_buffer_create(VERTEX_BUFFER_SIZE,
                         {.VERTEX_BUFFER, .TRANSFER_DST, .TRANSFER_SRC},
                         memory_property_flags,
                         true,
                         &window_context.object_vertex_buffer) {
        log.error("Failed to create vertex buffer")
        return false
    }
    window_context.geometry_vertex_offset = 0

    INDEX_BUFFER_SIZE :: size_of(u32) * 1024 * 1024;
    if !vk_buffer_create(INDEX_BUFFER_SIZE,
                         {.INDEX_BUFFER, .TRANSFER_DST, .TRANSFER_SRC},
                         memory_property_flags,
                         true,
                         &window_context.object_index_buffer) {
        log.error("Failed to create index buffer")
        return false
    }
    window_context.geometry_index_offset = 0

    return true
}

// Initializes the Vulkan context and creates the Vulkan instance.
//
// Parameters:
//   app_name: string - The name of the application.
//
// Returns:
//   b8 - True if initialization was successful, otherwise false.
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

    // Function pointers
    g_context.find_memory_index = vk_find_memory_index

    // TODO: Add a custom allocator
    g_context.allocator = nil

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

    result := vk.CreateInstance(&create_info, g_context.allocator, &g_context.instance)
    if result != vk.Result.SUCCESS {
        log.errorf("Failed to create Vulkan instance: %v", result)
        return false
    }
    vk.load_proc_addresses_instance(g_context.instance)

    log.debug("Vulkan instance created")

    // Debug utils messenger
    when ODIN_DEBUG {
        g_context.debug_utils_context = context

        debug_utils_create_info := vk.DebugUtilsMessengerCreateInfoEXT{
            sType = vk.StructureType.DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
            pNext = nil,
            flags = {},
            messageSeverity = {.VERBOSE, .INFO, .WARNING, .ERROR},
            messageType = {.GENERAL, .PERFORMANCE, .VALIDATION},
            pfnUserCallback = vk_debug_utils_messenger_callback,
            pUserData = &g_context.debug_utils_context,
        }

        result = vk.CreateDebugUtilsMessengerEXT(g_context.instance,
                                                 &debug_utils_create_info,
                                                 g_context.allocator,
                                                 &g_context.debug_utils_messenger)
        if result != vk.Result.SUCCESS {
            log.errorf("Failed to create Vulkan debug utils messenger: %v", result)
            return false
        }
        log.debug("Vulkan debug utils messenger created")
    }

    log.info("Vulkan renderer initialized successfully")

    return true
}

// Destroys the Vulkan context and cleans up resources.
destroy :: proc() {
    vk_device_destroy()

    when ODIN_DEBUG {
        vk.DestroyDebugUtilsMessengerEXT(g_context.instance,
                                         g_context.debug_utils_messenger,
                                         g_context.allocator)
        log.debug("Vulkan debug utils messenger destroyed")
    }

    vk.DestroyInstance(g_context.instance, g_context.allocator)
    log.debug("Vulkan instance destroyed")
}

// Initializes a Vulkan window context.
//
// Parameters:
//   instance: platform.Instance - The platform instance for the window.
//   handle: platform.Handle - The handle for the window.
//   width: u32 - The initial width of the window.
//   height: u32 - The initial height of the window.
//
// Returns:
//   (rt.Window_Context_Handle, b8) - The window context ID and a boolean indicating success or failure.
init_window :: proc(instance: platform.Instance, handle: platform.Handle,
                    width: u32, height: u32) -> (rt.Window_Context_Handle, b8) {
    window_context, _ := mem.new(Vulkan_Window_Context)
    
    window_context^ = {
        instance = instance,
        handle = handle,
        frame_buffer_width = width,
        frame_buffer_height = height,
    }

    if !vk_platform_create_vulkan_surface(window_context) {
        log.error("Failed to create Vulkan surface")
        return {}, false
    }

    // Device creation
    if g_context.device.physical_device == nil {
        if !vk_device_create(window_context.surface) {
            log.error("Failed to create Vulkan device")
            return {}, false
        }
    }

    // Swapchain creation
    vk_swapchain_create(window_context, window_context.frame_buffer_width,
                        window_context.frame_buffer_height, &window_context.swapchain)

    // Render pass creation
    vk_render_pass_create(window_context, &window_context.main_render_pass,
                          linalg.Vector4f32{0, 0, f32(window_context.frame_buffer_width),
                                                  f32(window_context.frame_buffer_height)},
                          linalg.Vector4f32{0, 0, 0.2, 1},
                          1.0, 0)

    // Swapachain framebuffers
    window_context.swapchain.frame_buffers = make([]Vulkan_Frame_Buffer,
                                                  len(window_context.swapchain.images))
    vk_regenerate_frame_buffers(window_context,
                                &window_context.swapchain,
                                &window_context.main_render_pass)

    // Create command buffers
    vk_create_command_buffers(window_context)

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
        result := vk.CreateSemaphore(g_context.device.logical_device,
                                     &semaphore_create_info,
                                     g_context.allocator,
                                     &window_context.image_available_semaphores[i])
        if result != vk.Result.SUCCESS {
            log.error("Failed to create image available semaphore")
            return {}, false
        }

        result = vk.CreateSemaphore(g_context.device.logical_device,
                                    &semaphore_create_info,
                                    g_context.allocator,
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

    // Create builtin shaders
    if !vk_object_shader_create(window_context, &window_context.object_shader) {
        log.error("Failed to create object shader")
        return {}, false
    }

    if !vk_create_buffers(window_context) {
        log.error("Failed to create buffers")
        return {}, false
    }

    // TODO: temporary test code
    FACTOR :: 10
    VERT_COUNT :: u32(4)
    verts: [VERT_COUNT]linalg.Vector3f32
    verts[0] = linalg.Vector3f32{-0.5, -0.5, 0} * FACTOR
    verts[1] = linalg.Vector3f32{0.5, 0.5, 0} * FACTOR
    verts[2] = linalg.Vector3f32{-0.5, 0.5, 0} * FACTOR
    verts[3] = linalg.Vector3f32{0.5, -0.5, 0} * FACTOR

    INDEX_COUNT :: u32(6)
    indices: [INDEX_COUNT]u32
    indices[0] = 0
    indices[1] = 1
    indices[2] = 2
    indices[3] = 0
    indices[4] = 3
    indices[5] = 1

    vk_upload_data_range(g_context.device.graphics_command_pool,
                         0,
                         g_context.device.graphics_queue,
                         &window_context.object_vertex_buffer,
                         0,
                         size_of(verts),
                         raw_data(&verts))

    vk_upload_data_range(g_context.device.graphics_command_pool,
                         0,
                         g_context.device.graphics_queue,
                         &window_context.object_index_buffer,
                         0,
                         size_of(indices),
                         raw_data(&indices))
    // TODO: end temporary test code

    log.info("Vulkan window initialized successfully")

    return rt.Window_Context_Handle(window_context), true
}

// Destroys a Vulkan window context.
//
// Parameters:
//   window_context_handle: rt.Window_Context_Handle - The ID of the window context to destroy.
destroy_window :: proc(window_context_handle: rt.Window_Context_Handle) {
    window_context := (^Vulkan_Window_Context)(window_context_handle)

    vk.DeviceWaitIdle(g_context.device.logical_device)

    // Destroy buffers
    vk_buffer_destroy(&window_context.object_vertex_buffer)
    vk_buffer_destroy(&window_context.object_index_buffer)

    vk_object_shader_destroy(&window_context.object_shader)
    
    // Destroy sync objects
    if window_context.images_in_flight != nil {
        delete(window_context.images_in_flight)
        window_context.images_in_flight = nil
    }

    for i in 0..<window_context.swapchain.max_frames_in_flight {
        vk.DestroySemaphore(g_context.device.logical_device,
                            window_context.image_available_semaphores[i],
                            g_context.allocator)
        vk.DestroySemaphore(g_context.device.logical_device,
                            window_context.queue_complete_semaphores[i],
                            g_context.allocator)
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
    vk.DestroySurfaceKHR(g_context.instance, window_context.surface, g_context.allocator)

    mem.free(window_context)
    log.debug("Vulkan surface destroyed")
}

// Resizes a Vulkan window context.
//
// Parameters:
//   window_context_handle: rt.Window_Context_Handle - The ID of the window context to resize.
//   width: u32 - The new width of the window.
//   height: u32 - The new height of the window.
resize_window :: proc(window_context_handle: rt.Window_Context_Handle, width: u32, height: u32) {
    window_context := (^Vulkan_Window_Context)(window_context_handle)

    // Update the "frame buffer size generation", a counter which indicates when the
    // frame buffer size has changed. This is used to determine when to regenerate the frame
    // buffers.
    window_context.frame_buffer_new_width = width
    window_context.frame_buffer_new_height = height
    window_context.frame_buffer_size_generation += 1

    log.infof("Vulkan window resized to %vx%v (%v)", width, height,
                                                     window_context.frame_buffer_size_generation)
}

// Begins a new frame for the given window context.
//
// Parameters:
//   window_context_handle: rt.Window_Context_Handle - The ID of the window context.
//   delta_time: f32 - The time elapsed since the last frame.
//
// Returns:
//   b8 - True if the frame was successfully begun, otherwise false.
begin_frame :: proc(window_context_handle: rt.Window_Context_Handle, delta_time: f32) -> b8 {
    window_context := (^Vulkan_Window_Context)(window_context_handle)
    device := &g_context.device

    // Check if recreating swap chain and boot out.
    if window_context.recreating_swapchain {
        result := vk.DeviceWaitIdle(device.logical_device)
        if !vk_result_is_success(result) {
            error, error_message := vk_result_to_string(result)
            log.errorf("Failed to wait for device idle: %v (%v)", error_message, error)
            return false
        }
        log.info("Recreating swapchain, booting.")
        return false
    }

    // Check if the frame buffer has been resized. If so, a new swapchain must be created.
    if window_context.frame_buffer_size_generation !=
       window_context.frame_buffer_size_last_generation {
        result := vk.DeviceWaitIdle(device.logical_device)
        if !vk_result_is_success(result) {
            error, error_message := vk_result_to_string(result)
            log.errorf("Failed to wait for device idle: %v (%v)", error_message, error)
            return false
        }

        // If the swapchain recreation failed (because, for example, the window was minimized),
        // boot out before unsetting the flag.
        if !vk_recreate_swapchain(window_context) {
            return false
        }

        log.info("Resized, booting.")
        return false
    }

    // Wait for the execution of the current frame to complete. The fence being free will allow this
    // one to move on.
    if !vk_fence_wait(&window_context.in_flight_fences[window_context.current_frame],
                      math.max(u64)) {
        log.warn("Failed to wait for in flight fence")
        return false
    }

    // Acquire the next image from the swap chain. Pass along the semaphore that should signaled
    // when this completes. This same semaphore will later be waited on by the queue submission to
    // ensure this image is available.
    if !vk_swapchain_acquire_next_image_index(window_context,
                            &window_context.swapchain,
                            math.max(u64),
                            window_context.image_available_semaphores[window_context.current_frame],
                            0,
                            &window_context.image_index) {
        return false;
    }

    // Begin recording commands.
    command_buffer := &window_context.graphics_command_buffers[window_context.image_index]
    vk_command_buffer_reset(command_buffer)
    vk_command_buffer_begin(command_buffer, false, false, false)

    // Dynamic state
    viewport := vk.Viewport{
        x = 0,
        y = f32(window_context.frame_buffer_height),
        width = f32(window_context.frame_buffer_width),
        height = -f32(window_context.frame_buffer_height),
        minDepth = 0,
        maxDepth = 1,
    }

    // Scissor
    scissor := vk.Rect2D{
        offset = vk.Offset2D{0, 0},
        extent = vk.Extent2D{window_context.frame_buffer_width, window_context.frame_buffer_height},
    }

    vk.CmdSetViewport(command_buffer.handle, 0, 1, &viewport)
    vk.CmdSetScissor(command_buffer.handle, 0, 1, &scissor)

    window_context.main_render_pass.render_area.z = f32(window_context.frame_buffer_width)
    window_context.main_render_pass.render_area.w = f32(window_context.frame_buffer_height)

    // Begin render pass
    vk_render_pass_begin(command_buffer, &window_context.main_render_pass,
                         window_context.swapchain.frame_buffers[window_context.image_index].handle)

    return true
}

// Ends the current frame for the given window context.
//
// Parameters:
//   window_context_handle: rt.Window_Context_Handle - The ID of the window context.
//   delta_time: f32 - The time elapsed since the last frame.
//
// Returns:
//   b8 - True if the frame was successfully ended, otherwise false.
end_frame :: proc(window_context_handle: rt.Window_Context_Handle, delta_time: f32) -> b8 {
    window_context := (^Vulkan_Window_Context)(window_context_handle)
    command_buffer := &window_context.graphics_command_buffers[window_context.image_index]

    // End render pass
    vk_render_pass_end(command_buffer, &window_context.main_render_pass)

    // End recording commands
    vk_command_buffer_end(command_buffer)

    // Make sure the previous frame is not using this image (i.e. its fence is being waited on)
    if window_context.images_in_flight[window_context.image_index] != nil {
        vk_fence_wait(window_context.images_in_flight[window_context.image_index], math.max(u64))
    }

    // Mark the image fence as in-use by this frame
    window_context.images_in_flight[window_context.image_index] =
        &window_context.in_flight_fences[window_context.current_frame]

    // Reset the fence for use on the next frame
    vk_fence_reset(&window_context.in_flight_fences[window_context.current_frame])

    // Submit the queue and wait for the operation to complete.
    // Begin queue submission
    submit_info := vk.SubmitInfo{
        sType = vk.StructureType.SUBMIT_INFO,
        pNext = nil,
        waitSemaphoreCount = 1,
        pWaitSemaphores = &window_context.image_available_semaphores[window_context.current_frame],
        commandBufferCount = 1,
        pCommandBuffers = &command_buffer.handle,
        signalSemaphoreCount = 1,
        pSignalSemaphores = &window_context.queue_complete_semaphores[window_context.current_frame],
    }

    // Each semaphore waits on the correspoing pipeline stage to complete. 1:1 ratio.
    // .COLOR_ATTACHMENT_OUTPUT prevent subsequent color atacchment writes from executing until
    // the semaphore signals (i.e. one frame is presented at a time)
    flags := [1]vk.PipelineStageFlags{{.COLOR_ATTACHMENT_OUTPUT}}
    submit_info.pWaitDstStageMask = raw_data(&flags)

    result := vk.QueueSubmit(g_context.device.graphics_queue, 1, &submit_info,
                             window_context.in_flight_fences[window_context.current_frame].handle)
    if result != vk.Result.SUCCESS {
        error, error_message := vk_result_to_string(result)
        log.errorf("Failed to submit queue: %v (%v)", error_message, error)
        return false
    }

    vk_command_buffer_update_submitted(command_buffer)

    // Give the image back to the swap chain for presentation
    vk_swapchain_present(window_context,
                         &window_context.swapchain,
                         g_context.device.graphics_queue,
                         g_context.device.present_queue,
                         window_context.queue_complete_semaphores[window_context.current_frame],
                         window_context.image_index)

    return true
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
    window_context := (^Vulkan_Window_Context)(window_context_handle)
    command_buffer := &window_context.graphics_command_buffers[window_context.image_index]
    
    vk_object_shader_use(window_context, &window_context.object_shader)
    window_context.object_shader.global_ubo.projection = projection
    window_context.object_shader.global_ubo.view = view

    // TODO: other ubo properties

    vk_object_shader_update_global_state(window_context, &window_context.object_shader)
}

update_object :: proc(window_context_handle: rt.Window_Context_Handle, model: linalg.Matrix4f32) {
    window_context := (^Vulkan_Window_Context)(window_context_handle)
    command_buffer := &window_context.graphics_command_buffers[window_context.image_index]

    vk_object_shader_update_object(window_context, &window_context.object_shader, model)

    // TODO: temporary test code
    vk_object_shader_use(window_context, &window_context.object_shader)
    vk_pipeline_bind(command_buffer, .GRAPHICS, &window_context.object_shader.pipeline)

    offsets: [1]vk.DeviceSize
    vk.CmdBindVertexBuffers(command_buffer.handle, 0, 1, &window_context.object_vertex_buffer.handle, &offsets[0])
    vk.CmdBindIndexBuffer(command_buffer.handle, window_context.object_index_buffer.handle, 0, .UINT32)
    vk.CmdDrawIndexed(command_buffer.handle, 6, 1, 0, 0, 0)
    // TODO: end temporary test code
}