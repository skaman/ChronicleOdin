package renderer_vulkan

import "core:log"
import "core:math"

import vk "vendor:vulkan"

// Struct to specify the requirements for selecting a Vulkan physical device.
@(private="file")
Vulkan_Physical_Device_Requirements :: struct {
    graphics: b8,                               // Indicates if a graphics queue is required
    present: b8,                                // Indicates if a present queue is required
    compute: b8,                                // Indicates if a compute queue is required
    transfer: b8,                               // Indicates if a transfer queue is required
    device_extensions_names: [dynamic]cstring,  // List of required device extension names
    sampler_anisotropy: b8,                     // Indicates if sampler anisotropy is required
    discrete_gpu: b8,                           // Indicates if a discrete GPU is preferred
}

// Struct to store the queue family indices of a Vulkan physical device.
@(private="file")
Vulkan_Physical_Device_Queue_Family_Info :: struct {
    graphics_family_index: u32,                 // Index of the graphics queue family
    present_family_index: u32,                  // Index of the present queue family
    compute_family_index: u32,                  // Index of the compute queue family
    transfer_family_index: u32,                 // Index of the transfer queue family
}

// Checks if a Vulkan physical device meets the specified requirements.
//
// Parameters:
//   physical_device: vk.PhysicalDevice - The physical device to check.
//   surface: vk.SurfaceKHR - The surface to check support for.
//   properties: ^vk.PhysicalDeviceProperties - Pointer to the device properties.
//   features: ^vk.PhysicalDeviceFeatures - Pointer to the device features.
//   requirements: ^Vulkan_Physical_Device_Requirements - Pointer to the device requirements.
//   out_queue_info: ^Vulkan_Physical_Device_Queue_Family_Info - Pointer to store the queue family indices.
//   out_swapchain_support: ^Vulkan_Swapchain_Support_Info - Pointer to store the swapchain support info.
//
// Returns:
//   b8 - True if the device meets the requirements, otherwise false.
@(private="file")
vk_physical_device_meets_requirements :: proc(physical_device: vk.PhysicalDevice,
                                              surface: vk.SurfaceKHR,
                                              properties: ^vk.PhysicalDeviceProperties,
                                              features: ^vk.PhysicalDeviceFeatures,
                                              requirements: ^Vulkan_Physical_Device_Requirements,
                                              out_queue_info: ^Vulkan_Physical_Device_Queue_Family_Info,
                                              out_swapchain_support: ^Vulkan_Swapchain_Support_Info) -> b8 {
    out_queue_info.graphics_family_index = math.max(u32)
    out_queue_info.present_family_index = math.max(u32)
    out_queue_info.compute_family_index = math.max(u32)
    out_queue_info.transfer_family_index = math.max(u32)

    // discrete gpu?
    if requirements.discrete_gpu && properties.deviceType != vk.PhysicalDeviceType.DISCRETE_GPU {
        log.info("Device is not a discrete GPU, and one is quired. Skipping.")
        return false
    }

    queue_family_count : u32
    vk.GetPhysicalDeviceQueueFamilyProperties(physical_device, &queue_family_count, nil)
    queue_families := make([]vk.QueueFamilyProperties, queue_family_count, context.temp_allocator)
    vk.GetPhysicalDeviceQueueFamilyProperties(physical_device, &queue_family_count, raw_data(queue_families))

    min_transfer_score := math.max(u8)
    for i in 0..<queue_family_count {
        queue_family := queue_families[i]
        current_transfer_score : u8 = 0

        // graphics queue?
        if vk.QueueFlag.GRAPHICS in queue_family.queueFlags {
            out_queue_info.graphics_family_index = i
            current_transfer_score += 1
        }

        // compute queue?
        if vk.QueueFlag.COMPUTE in queue_family.queueFlags {
            out_queue_info.compute_family_index = i
            current_transfer_score += 1
        }

        // transfer queue?
        if vk.QueueFlag.TRANSFER in queue_family.queueFlags {
            // take the index if it is the current lowest. This increases the
            // likelihood that is a dedicated transfer queue.
            if current_transfer_score <= min_transfer_score {
                min_transfer_score = current_transfer_score
                out_queue_info.transfer_family_index = i
            }
        }

        // present queue?
        present_support : b32
        result := vk.GetPhysicalDeviceSurfaceSupportKHR(physical_device, i, surface, &present_support)
        if result != vk.Result.SUCCESS {
            log.errorf("Failed to get surface support: %v", result)
            return false
        }
        if present_support {
            out_queue_info.present_family_index = i
        }
    }

    log.infof("%s (graphics=%v, presente=%v, compute=%v, transfer=%v)",
              properties.deviceName,
              out_queue_info.graphics_family_index != math.max(u32),
              out_queue_info.present_family_index != math.max(u32),
              out_queue_info.compute_family_index != math.max(u32),
              out_queue_info.transfer_family_index != math.max(u32))

    if (!requirements.graphics || (requirements.graphics && out_queue_info.graphics_family_index != math.max(u32))) &&
       (!requirements.present || (requirements.graphics && out_queue_info.present_family_index != math.max(u32))) &&
       (!requirements.compute || (requirements.graphics && out_queue_info.compute_family_index != math.max(u32))) &&
       (!requirements.transfer || (requirements.graphics && out_queue_info.transfer_family_index != math.max(u32))) {
        log.info("Device meets queue requirements")
        log.debugf("Graphics: %v", out_queue_info.graphics_family_index)
        log.debugf("Present: %v", out_queue_info.present_family_index)
        log.debugf("Compute: %v", out_queue_info.compute_family_index)
        log.debugf("Transfer: %v", out_queue_info.transfer_family_index)

        vk_query_swapchain_support(physical_device, surface, out_swapchain_support)

        if len(out_swapchain_support.surface_formats) < 1 || len(out_swapchain_support.present_modes) < 1 {
            log.info("Required swapchain support not present, skipping device.")
            delete(out_swapchain_support.present_modes)
            delete(out_swapchain_support.surface_formats)
            return false
        }

        // device extensions
        if len(requirements.device_extensions_names) > 0 {
            available_extensions_count : u32
            result := vk.EnumerateDeviceExtensionProperties(physical_device, nil, &available_extensions_count, nil)
            if result != vk.Result.SUCCESS {
                log.errorf("Failed to enumerate device extensions count: %v, skipping", result)
                delete(out_swapchain_support.present_modes)
                delete(out_swapchain_support.surface_formats)
                return false
            }
            available_extensions := make([]vk.ExtensionProperties, available_extensions_count, context.temp_allocator)
            result = vk.EnumerateDeviceExtensionProperties(physical_device, nil, &available_extensions_count, raw_data(available_extensions))
            if result != vk.Result.SUCCESS {
                log.errorf("Failed to enumerate device extensions: %v, skipping", result)
                delete(out_swapchain_support.present_modes)
                delete(out_swapchain_support.surface_formats)
                return false
            }

            for extension_name in requirements.device_extensions_names {
                found := false
                for extension in available_extensions {
                    available_extension_name := extension.extensionName
                    if extension_name == cstring(&available_extension_name[0]) {
                        found = true
                        break
                    }
                }

                if !found {
                    log.infof("Device does not support required extension: %v, skipping.", extension_name)
                    return false
                }
            }
        }

        // sampler anisotropy
        if requirements.sampler_anisotropy && !features.samplerAnisotropy {
            log.info("Device does not support sampler anisotropy, skipping.")
            delete(out_swapchain_support.present_modes)
            delete(out_swapchain_support.surface_formats)
            return false
        }

        return true
    }

    return false
}

// Selects a Vulkan physical device that meets the requirements.
//
// Parameters:
//   surface: vk.SurfaceKHR - The surface to check support for.
//
// Returns:
//   b8 - True if a suitable physical device was found, otherwise false.
@(private="file")
vk_select_physical_device :: proc(surface: vk.SurfaceKHR) -> b8 {
    physical_device_count : u32
    result := vk.EnumeratePhysicalDevices(global_context.instance, &physical_device_count, nil)
    if result != vk.Result.SUCCESS {
        log.errorf("Failed to enumerate physical devices: %v", result)
        return false
    }

    if physical_device_count == 0 {
        log.error("No physical devices found")
        return false
    }

    physical_devices := make([]vk.PhysicalDevice, physical_device_count, context.temp_allocator)
    result = vk.EnumeratePhysicalDevices(global_context.instance, &physical_device_count, raw_data(physical_devices))
    if result != vk.Result.SUCCESS {
        log.errorf("Failed to enumerate physical devices: %v", result)
        return false
    }

    for physical_device in physical_devices {
        properties : vk.PhysicalDeviceProperties
        vk.GetPhysicalDeviceProperties(physical_device, &properties)

        features : vk.PhysicalDeviceFeatures
        vk.GetPhysicalDeviceFeatures(physical_device, &features)

        memory : vk.PhysicalDeviceMemoryProperties
        vk.GetPhysicalDeviceMemoryProperties(physical_device, &memory)

        // TODO: These requirements should be configurable
        requirements := Vulkan_Physical_Device_Requirements{
            graphics = true,
            present = true,
            compute = true,
            transfer = true,
            device_extensions_names = make([dynamic]cstring, context.temp_allocator),
            sampler_anisotropy = true,
            discrete_gpu = false,
        }
        append(&requirements.device_extensions_names, vk.KHR_SWAPCHAIN_EXTENSION_NAME)

        queue_family_info : Vulkan_Physical_Device_Queue_Family_Info
        meet_requirements := vk_physical_device_meets_requirements(physical_device,
                                                                   surface,
                                                                   &properties,
                                                                   &features,
                                                                   &requirements,
                                                                   &queue_family_info,
                                                                   &global_context.device.swapchain_support)
        if meet_requirements {
            switch properties.deviceType {
                case .INTEGRATED_GPU:
                    log.info("Device type: Integrated GPU")
                case .DISCRETE_GPU:
                    log.info("Device type: Discrete GPU")
                case .VIRTUAL_GPU:
                    log.info("Device type: Virtual GPU")
                case .CPU:
                    log.info("Device type: CPU")
                case .OTHER:
                    log.info("Device type: Other")
            }

            log.infof("Device name: %s", properties.deviceName)
            log.infof("Device ID: %v", properties.deviceID)
            log.infof("Device API version: %v", properties.apiVersion)
            log.infof("Device driver version: %v", properties.driverVersion)
            log.infof("Device vendor ID: %v", properties.vendorID)

            for i in 0..<memory.memoryHeapCount {
                memory_size_gib := f32(memory.memoryHeaps[i].size) / 1024 / 1024 / 1024
                if vk.MemoryHeapFlag.DEVICE_LOCAL in memory.memoryHeaps[i].flags {
                    log.infof("Device local memory: %v GiB", memory_size_gib)
                }
                else {
                    log.infof("Host visible memory: %v GiB", memory_size_gib)
                }
            }

            global_context.device.physical_device = physical_device
            global_context.device.graphics_queue_index = queue_family_info.graphics_family_index
            global_context.device.present_queue_index = queue_family_info.present_family_index
            global_context.device.transfer_queue_index = queue_family_info.transfer_family_index
            // NOTE: set compute index here if needed
            //window_context.device.compute_queue_index = queue_family_info.compute_family_index

            global_context.device.properties = properties
            global_context.device.features = features
            global_context.device.memory = memory
            break
        }
    }

    // ensure a physical device was found
    if global_context.device.physical_device == nil {
        log.error("Failed to find a suitable physical device")
        return false
    }

    log.info("Selected physical device")
    
    return true
}

// Creates a Vulkan device.
//
// Parameters:
//   surface: vk.SurfaceKHR - The surface to check support for.
//
// Returns:
//   b8 - True if the device was successfully created, otherwise false.
@private
vk_device_create :: proc(surface: vk.SurfaceKHR) -> b8 {
    if !vk_select_physical_device(surface) {
        log.error("Failed to select physical device")
        return false
    }

    log.info("Creating logical device...")
    present_shares_graphics_queue := global_context.device.graphics_queue_index == global_context.device.present_queue_index
    transfer_shares_graphics_queue := global_context.device.graphics_queue_index == global_context.device.transfer_queue_index
    index_count: u32 = 1
    if !present_shares_graphics_queue {
        index_count += 1
    }
    if !transfer_shares_graphics_queue {
        index_count += 1
    }
    indices := make([]u32, index_count, context.temp_allocator)
    index := 0
    indices[index] = global_context.device.graphics_queue_index
    index += 1
    if !present_shares_graphics_queue {
        indices[index] = global_context.device.present_queue_index
        index += 1
    }
    if !transfer_shares_graphics_queue {
        indices[index] = global_context.device.transfer_queue_index
        index += 1
    }

    queue_create_infos := make([]vk.DeviceQueueCreateInfo, index_count, context.temp_allocator)
    for i in 0..<index_count {
        queue_priority := f32(1.0)
        queue_create_infos[i] = vk.DeviceQueueCreateInfo{
            sType = vk.StructureType.DEVICE_QUEUE_CREATE_INFO,
            pNext = nil,
            flags = {},
            queueFamilyIndex = indices[i],
            queueCount = 1,
            // TODO: Enable this for a future enhancement
            //queueCount = indices[i] == global_context.device.graphics_queue_index ? 2 : 1,
            pQueuePriorities = &queue_priority,
        }
    }

    // Required device features
    // TODO: These should be configurable
    device_features := vk.PhysicalDeviceFeatures{
        samplerAnisotropy = true,
    }

    enabled_extensions_names :[1]cstring
    enabled_extensions_names[0] = vk.KHR_SWAPCHAIN_EXTENSION_NAME

    device_create_info := vk.DeviceCreateInfo{
        sType = vk.StructureType.DEVICE_CREATE_INFO,
        pNext = nil,
        flags = {},
        queueCreateInfoCount = index_count,
        pQueueCreateInfos = raw_data(queue_create_infos),
        enabledLayerCount = 0,      // deprecated
        ppEnabledLayerNames = nil,  // deprecated
        enabledExtensionCount = 1,
        ppEnabledExtensionNames = raw_data(&enabled_extensions_names),
        pEnabledFeatures = &device_features,
    }

    // create logical device
    result := vk.CreateDevice(global_context.device.physical_device,
                              &device_create_info,
                              global_context.allocator,
                              &global_context.device.logical_device)
    if result != vk.Result.SUCCESS {
        log.errorf("Failed to create logical device: %v", result)
        return false
    }

    log.info("Logical device created")

    // get queue handles
    vk.GetDeviceQueue(global_context.device.logical_device,
                      global_context.device.graphics_queue_index,
                      0,
                      &global_context.device.graphics_queue)

    vk.GetDeviceQueue(global_context.device.logical_device,
                      global_context.device.present_queue_index,
                      0,
                      &global_context.device.present_queue)

    vk.GetDeviceQueue(global_context.device.logical_device,
                      global_context.device.transfer_queue_index,
                      0,
                      &global_context.device.transfer_queue)

    log.info("Queue handles acquired")

    // Create command pool for graphics queue
    command_pool_create_info := vk.CommandPoolCreateInfo{
        sType = vk.StructureType.COMMAND_POOL_CREATE_INFO,
        pNext = nil,
        flags = {.RESET_COMMAND_BUFFER},
        queueFamilyIndex = global_context.device.graphics_queue_index,
    }
    result = vk.CreateCommandPool(global_context.device.logical_device,
                                  &command_pool_create_info,
                                  global_context.allocator,
                                  &global_context.device.graphics_command_pool)
    if result != vk.Result.SUCCESS {
        log.errorf("Failed to create command pool: %v", result)
        return false
    }

    log.info("Command pool created")

    return true
}

// Destroys the Vulkan device.
@private
vk_device_destroy :: proc() {
    global_context.device.graphics_queue = nil
    global_context.device.present_queue = nil
    global_context.device.transfer_queue = nil

    log.info("Destroying command pool...")
    if global_context.device.graphics_command_pool != 0 {
        vk.DestroyCommandPool(global_context.device.logical_device,
                              global_context.device.graphics_command_pool,
                              global_context.allocator)
        global_context.device.graphics_command_pool = 0
    }

    log.info("Destroying logical device...")
    if global_context.device.logical_device != nil {
        vk.DestroyDevice(global_context.device.logical_device, global_context.allocator)
        global_context.device.logical_device = nil
    }

    log.info("Releasing physical device resources...")
    global_context.device.physical_device = nil
    
    if global_context.device.swapchain_support.surface_formats != nil {
        delete(global_context.device.swapchain_support.surface_formats)
        global_context.device.swapchain_support.surface_formats = nil
    }
    
    if global_context.device.swapchain_support.present_modes != nil {
        delete(global_context.device.swapchain_support.present_modes)
        global_context.device.swapchain_support.present_modes = nil
    }

    global_context.device.swapchain_support = {}
    global_context.device.graphics_queue_index = math.max(u32)
    global_context.device.present_queue_index = math.max(u32)
    global_context.device.transfer_queue_index = math.max(u32)
}

// Queries swapchain support details for a physical device.
//
// Parameters:
//   physical_device: vk.PhysicalDevice - The physical device to query.
//   surface: vk.SurfaceKHR - The surface to query support for.
//   out_support: ^Vulkan_Swapchain_Support_Info - Pointer to store the swapchain support info.
@private
vk_query_swapchain_support :: proc(physical_device: vk.PhysicalDevice,
                                   surface: vk.SurfaceKHR,
                                   out_support: ^Vulkan_Swapchain_Support_Info) {
    result := vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(physical_device, surface, &out_support.capabilities)
    if result != vk.Result.SUCCESS {
        log.errorf("Failed to get surface capabilities: %v", result)
        return
    }

    format_count : u32
    result = vk.GetPhysicalDeviceSurfaceFormatsKHR(physical_device, surface, &format_count, nil)
    if result != vk.Result.SUCCESS {
        log.errorf("Failed to get surface formats count: %v", result)
        return
    }
    
    if out_support.surface_formats != nil {
        delete(out_support.surface_formats)
    }
    out_support.surface_formats = make([]vk.SurfaceFormatKHR, format_count)
    result = vk.GetPhysicalDeviceSurfaceFormatsKHR(physical_device, surface, &format_count, raw_data(out_support.surface_formats))
    if result != vk.Result.SUCCESS {
        log.errorf("Failed to get surface formats: %v", result)
        return
    }

    present_mode_count : u32
    result = vk.GetPhysicalDeviceSurfacePresentModesKHR(physical_device, surface, &present_mode_count, nil)
    if result != vk.Result.SUCCESS {
        log.errorf("Failed to get present modes count: %v", result)
        return
    }
    
    if out_support.present_modes != nil {
        delete(out_support.present_modes)
    }
    out_support.present_modes = make([]vk.PresentModeKHR, present_mode_count)
    result = vk.GetPhysicalDeviceSurfacePresentModesKHR(physical_device, surface, &present_mode_count, raw_data(out_support.present_modes))
    if result != vk.Result.SUCCESS {
        log.errorf("Failed to get present modes: %v", result)
        return
    }
}

// Detects the depth format supported by a Vulkan device.
//
// Parameters:
//   device: ^Vulkan_Device - Pointer to the Vulkan device.
//
// Returns:
//   b8 - True if a suitable depth format was found, otherwise false.
@private
vk_device_detect_depth_format :: proc(device: ^Vulkan_Device) -> b8 {
    CANDIDATE_COUNT :: 3
    candidates := [CANDIDATE_COUNT]vk.Format{
        vk.Format.D32_SFLOAT,
        vk.Format.D32_SFLOAT_S8_UINT,
        vk.Format.D24_UNORM_S8_UINT,
    }

    //flags: vk.FormatFeatureFlags = {.DEPTH_STENCIL_ATTACHMENT}
    for i in 0..<CANDIDATE_COUNT {
        format := candidates[i]
        properties : vk.FormatProperties
        vk.GetPhysicalDeviceFormatProperties(device.physical_device, format, &properties)
        
        if vk.FormatFeatureFlag.DEPTH_STENCIL_ATTACHMENT in properties.linearTilingFeatures {
            device.depth_format = format
            return true
        }
        else if vk.FormatFeatureFlag.DEPTH_STENCIL_ATTACHMENT in properties.optimalTilingFeatures {
            device.depth_format = format
            return true
        }
    }

    return false
}