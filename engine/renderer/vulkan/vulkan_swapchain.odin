package renderer_vulkan

import "core:log"
import "core:math"

import vk "vendor:vulkan"

// Internal function to create a Vulkan swapchain.
//
// Parameters:
//   window_context: ^Vulkan_Window_Context - Pointer to the window context.
//   width: u32 - The width of the swapchain.
//   height: u32 - The height of the swapchain.
//   swapchain: ^Vulkan_Swapchain - Pointer to the swapchain to be created.
@(private="file")
vk_swapchain_create_internal :: proc(window_context: ^Vulkan_Window_Context,
                                     width: u32, height: u32, swapchain: ^Vulkan_Swapchain) {
    swapchain_extent := vk.Extent2D{
        width,
        height,
    }

    // Choose a swapchain format
    found := false
    for format in g_context.device.swapchain_support.surface_formats {
        // Preferred format
        if format.format == vk.Format.B8G8R8A8_UNORM &&
           format.colorSpace == vk.ColorSpaceKHR.SRGB_NONLINEAR {
            swapchain.image_format = format
            found = true
            break
        }
    }

    if !found {
        // Fallback to the first format
        swapchain.image_format = g_context.device.swapchain_support.surface_formats[0]
    }

    present_mode := vk.PresentModeKHR.FIFO
    for mode in g_context.device.swapchain_support.present_modes {
        if mode == vk.PresentModeKHR.MAILBOX {
            present_mode = mode
            break
        }
    }

    // Requery swapchain support
    if g_context.device.swapchain_support.capabilities.currentExtent.width != math.max(u32) {
        swapchain_extent = g_context.device.swapchain_support.capabilities.currentExtent
    }

    // Clamp to the value allowed by the GPU
    min := g_context.device.swapchain_support.capabilities.minImageExtent
    max := g_context.device.swapchain_support.capabilities.maxImageExtent
    swapchain_extent.width = math.clamp(swapchain_extent.width, min.width, max.width)
    swapchain_extent.height = math.clamp(swapchain_extent.height, min.height, max.height)

    image_count := g_context.device.swapchain_support.capabilities.minImageCount + 1
    if g_context.device.swapchain_support.capabilities.maxImageCount > 0 &&
       image_count > g_context.device.swapchain_support.capabilities.maxImageCount {
        image_count = g_context.device.swapchain_support.capabilities.maxImageCount
    }
    swapchain.max_frames_in_flight = u8(image_count - 1)

    // Swapchain craete info
    swapchain_create_info := vk.SwapchainCreateInfoKHR{
        sType = vk.StructureType.SWAPCHAIN_CREATE_INFO_KHR,
        pNext = nil,
        flags = {},
        surface = window_context.surface,
        minImageCount = image_count,
        imageFormat = swapchain.image_format.format,
        imageColorSpace = swapchain.image_format.colorSpace,
        imageExtent = swapchain_extent,
        imageArrayLayers = 1,
        imageUsage = {.COLOR_ATTACHMENT},
    }

    if g_context.device.graphics_queue_index != g_context.device.present_queue_index {
        queue_family_indices := [2]u32{g_context.device.graphics_queue_index,
                                       g_context.device.present_queue_index}
        swapchain_create_info.imageSharingMode = vk.SharingMode.CONCURRENT
        swapchain_create_info.queueFamilyIndexCount = 2
        swapchain_create_info.pQueueFamilyIndices = raw_data(&queue_family_indices)
    } else {
        swapchain_create_info.imageSharingMode = vk.SharingMode.EXCLUSIVE
        swapchain_create_info.queueFamilyIndexCount = 0
        swapchain_create_info.pQueueFamilyIndices = nil
    }

    swapchain_create_info.preTransform =
         g_context.device.swapchain_support.capabilities.currentTransform
    swapchain_create_info.compositeAlpha = {.OPAQUE}
    swapchain_create_info.presentMode = present_mode
    swapchain_create_info.clipped = true
    swapchain_create_info.oldSwapchain = vk.SwapchainKHR(0)

    result := vk.CreateSwapchainKHR(g_context.device.logical_device, &swapchain_create_info,
                                    g_context.allocator, &swapchain.handle)
    if result != vk.Result.SUCCESS {
        log.errorf("Failed to create swapchain: %v", result)
        return
    }

    // Start with a zero frame index
    window_context.current_frame = 0

    // Images
    swapchain_image_count := u32(0)
    result = vk.GetSwapchainImagesKHR(g_context.device.logical_device, swapchain.handle,
                                      &swapchain_image_count, nil)
    if result != vk.Result.SUCCESS {
        log.errorf("Failed to get swapchain image count: %v", result)
        return
    }
    swapchain.images = make([]vk.Image, swapchain_image_count)
    result = vk.GetSwapchainImagesKHR(g_context.device.logical_device, swapchain.handle,
                                      &swapchain_image_count, raw_data(swapchain.images))
    if result != vk.Result.SUCCESS {
        log.errorf("Failed to get swapchain images: %v", result)
        return
    }

    // Image views
    swapchain.image_views = make([]vk.ImageView, swapchain_image_count)
    for i in 0..<swapchain_image_count {
        image_view_create_info := vk.ImageViewCreateInfo{
            sType = vk.StructureType.IMAGE_VIEW_CREATE_INFO,
            pNext = nil,
            flags = {},
            image = swapchain.images[i],
            viewType = .D2,
            format = swapchain.image_format.format,
            subresourceRange = vk.ImageSubresourceRange{
                aspectMask = {.COLOR},
                baseMipLevel = 0,
                levelCount = 1,
                baseArrayLayer = 0,
                layerCount = 1,
            },
        }

        result = vk.CreateImageView(g_context.device.logical_device, &image_view_create_info,
                                    g_context.allocator, &swapchain.image_views[i])
        if result != vk.Result.SUCCESS {
            log.errorf("Failed to create image view: %v", result)
            return
        }
    }

    // Depth resources
    if !vk_device_detect_depth_format(&g_context.device) {
        g_context.device.depth_format = vk.Format.UNDEFINED
        log.error("Failed to find a suitable depth format")
        return
    }

    // Create depth image and its view
    vk_image_create(.D2, swapchain_extent.width, swapchain_extent.height,
                    g_context.device.depth_format, .OPTIMAL, {.DEPTH_STENCIL_ATTACHMENT},
                    {.DEVICE_LOCAL}, true, {.DEPTH}, &swapchain.depth_attachment)

    log.info("Swapchain created successfully")
}

// Internal function to destroy a Vulkan swapchain.
//
// Parameters:
//   window_context: ^Vulkan_Window_Context - Pointer to the window context.
//   swapchain: ^Vulkan_Swapchain - Pointer to the swapchain to be destroyed.
@(private="file")
vk_swapchain_destroy_internal :: proc(window_context: ^Vulkan_Window_Context,
                                      swapchain: ^Vulkan_Swapchain) {
    vk.DeviceWaitIdle(g_context.device.logical_device)

    vk_image_destroy(&swapchain.depth_attachment)

    // Only destroys the image views, the images are destroyed with the swapchain
    for view in swapchain.image_views {
        vk.DestroyImageView(g_context.device.logical_device, view, g_context.allocator)
    }

    vk.DestroySwapchainKHR(g_context.device.logical_device, swapchain.handle,
                           g_context.allocator)

    delete(swapchain.images)
    delete(swapchain.image_views)
}

// Creates a Vulkan swapchain.
//
// Parameters:
//   window_context: ^Vulkan_Window_Context - Pointer to the window context.
//   width: u32 - The width of the swapchain.
//   height: u32 - The height of the swapchain.
//   out_swapchain: ^Vulkan_Swapchain - Pointer to the swapchain to be created.
@private
vk_swapchain_create :: proc(window_context: ^Vulkan_Window_Context, width: u32, height: u32,
                            out_swapchain: ^Vulkan_Swapchain) {
    vk_swapchain_create_internal(window_context, width, height, out_swapchain)
}

// Recreates a Vulkan swapchain.
//
// Parameters:
//   window_context: ^Vulkan_Window_Context - Pointer to the window context.
//   width: u32 - The width of the swapchain.
//   height: u32 - The height of the swapchain.
//   out_swapchain: ^Vulkan_Swapchain - Pointer to the swapchain to be recreated.
@private
vk_swapchain_recreate :: proc(window_context: ^Vulkan_Window_Context, width: u32, height: u32,
                              out_swapchain: ^Vulkan_Swapchain) {
    vk_swapchain_destroy_internal(window_context, out_swapchain)
    vk_swapchain_create_internal(window_context, width, height, out_swapchain)
}

// Destroys a Vulkan swapchain.
//
// Parameters:
//   window_context: ^Vulkan_Window_Context - Pointer to the window context.
//   swapchain: ^Vulkan_Swapchain - Pointer to the swapchain to be destroyed.
@private
vk_swapchain_destroy :: proc(window_context: ^Vulkan_Window_Context,
                             swapchain: ^Vulkan_Swapchain) {
    vk_swapchain_destroy_internal(window_context, swapchain)
}

// Acquires the next image index from the swapchain.
//
// Parameters:
//   window_context: ^Vulkan_Window_Context - Pointer to the window context.
//   swapchain: ^Vulkan_Swapchain - Pointer to the swapchain.
//   timeout_ns: u64 - Timeout in nanoseconds.
//   image_available_semaphore: vk.Semaphore - Semaphore to signal when the image is available.
//   fence: vk.Fence - Fence to signal when the image is available.
//   out_image_index: ^u32 - Pointer to store the acquired image index.
//
// Returns:
//   b8 - True if the image index was successfully acquired, otherwise false.
@private
vk_swapchain_acquire_next_image_index :: proc(window_context: ^Vulkan_Window_Context, 
                                              swapchain: ^Vulkan_Swapchain,
                                              timeout_ns: u64,
                                              image_available_semaphore: vk.Semaphore,
                                              fence: vk.Fence,
                                              out_image_index: ^u32) -> b8 {
    result := vk.AcquireNextImageKHR(g_context.device.logical_device,
                                     swapchain.handle,
                                     timeout_ns,
                                     image_available_semaphore,
                                     fence,
                                     out_image_index)
    if result == vk.Result.ERROR_OUT_OF_DATE_KHR {
        // Trigger swapchain recreation, then boot out of the render loop
        vk_swapchain_recreate(window_context, window_context.frame_buffer_width,
                              window_context.frame_buffer_height, swapchain)
        return false
    } else if result != vk.Result.SUCCESS && result != vk.Result.SUBOPTIMAL_KHR {
        log.errorf("Failed to acquire next image index: %v", result)
        return false
    }

    return true
}

// Presents the current image to the swapchain.
//
// Parameters:
//   window_context: ^Vulkan_Window_Context - Pointer to the window context.
//   swapchain: ^Vulkan_Swapchain - Pointer to the swapchain.
//   graphics_queue: vk.Queue - The graphics queue.
//   present_queue: vk.Queue - The presentation queue.
//   render_complete_semaphore: vk.Semaphore - Semaphore to signal when rendering is complete.
//   present_image_index: u32 - The index of the image to present.
@private
vk_swapchain_present :: proc(window_context: ^Vulkan_Window_Context, 
                             swapchain: ^Vulkan_Swapchain,
                             graphics_queue: vk.Queue,
                             present_queue: vk.Queue,
                             render_complete_semaphore: vk.Semaphore,
                             present_image_index: u32) {
    wait_semaphores := [1]vk.Semaphore{render_complete_semaphore}
    image_indices := [1]u32{present_image_index}
    present_info := vk.PresentInfoKHR{
        sType = vk.StructureType.PRESENT_INFO_KHR,
        pNext = nil,
        waitSemaphoreCount = 1,
        pWaitSemaphores = raw_data(&wait_semaphores),
        swapchainCount = 1,
        pSwapchains = &swapchain.handle,
        pImageIndices = raw_data(&image_indices),
        pResults = nil,
    }

    result := vk.QueuePresentKHR(present_queue, &present_info)
    if result == vk.Result.ERROR_OUT_OF_DATE_KHR || result == vk.Result.SUBOPTIMAL_KHR {
        // Trigger swapchain recreation, then boot out of the render loop
        vk_swapchain_recreate(window_context, window_context.frame_buffer_width,
                              window_context.frame_buffer_height, swapchain)
    } else if result != vk.Result.SUCCESS {
        log.errorf("Failed to present image: %v", result)
    }

    // Increment (and loop) the index.
    window_context.current_frame = (window_context.current_frame + 1) %
                                    u32(swapchain.max_frames_in_flight)
}