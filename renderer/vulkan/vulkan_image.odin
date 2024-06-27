package renderer_vulkan

import "core:log"
import "core:math"

import vk "vendor:vulkan"

@private
vk_image_create :: proc(image_type: vk.ImageType, width: u32, height: u32, format: vk.Format,
                        tiling: vk.ImageTiling, usage: vk.ImageUsageFlags,
                        memory_flags: vk.MemoryPropertyFlags, create_view: b8,
                        view_aspect_flags: vk.ImageAspectFlags, out_image: ^Vulkan_Image) {
    // Copy params
    out_image.width = width
    out_image.height = height

    // Image create info
    create_info := vk.ImageCreateInfo{
        sType = vk.StructureType.IMAGE_CREATE_INFO,
        pNext = nil,
        flags = {},
        imageType = .D2,
        extent = vk.Extent3D{width, height, 1}, // TODO: support configurable depth
        mipLevels = 4,                          // TODO: Support mip mapping
        arrayLayers = 1,                        // TODO: Support number of layers in the image
        format = format,
        tiling = tiling,
        initialLayout = vk.ImageLayout.UNDEFINED,
        usage = usage,
        samples = {._1},                        // TODO: Configurable sample count
        sharingMode = vk.SharingMode.EXCLUSIVE, // TODO: Configurable sharing mode
        queueFamilyIndexCount = 0,
        pQueueFamilyIndices = nil,
    }

    result := vk.CreateImage(global_context.device.logical_device, &create_info,
                             global_context.allocator, &out_image.handle)
    if result != vk.Result.SUCCESS {
        log.errorf("Failed to create image: %v", result)
        return
    }

    // Query memory requirements
    memory_requirements := vk.MemoryRequirements{}
    vk.GetImageMemoryRequirements(global_context.device.logical_device, out_image.handle,
                                  &memory_requirements)

    memory_type := global_context.find_memory_index(memory_requirements.memoryTypeBits,
                                                    memory_flags)
    if memory_type == math.max(u32) {
        log.error("Failed to find suitable memory type")
        return
    }

    // Allocate memory
    allocate_info := vk.MemoryAllocateInfo{
        sType = vk.StructureType.MEMORY_ALLOCATE_INFO,
        pNext = nil,
        allocationSize = memory_requirements.size,
        memoryTypeIndex = memory_type,
    }
    result = vk.AllocateMemory(global_context.device.logical_device, &allocate_info,
                               global_context.allocator, &out_image.memory)
    if result != vk.Result.SUCCESS {
        log.errorf("Failed to allocate memory: %v", result)
        return
    }

    // Bind memory
    result = vk.BindImageMemory(global_context.device.logical_device, out_image.handle,
                                out_image.memory, 0)    // TODO: Configurable memory offset
    if result != vk.Result.SUCCESS {
        log.errorf("Failed to bind memory: %v", result)
        return
    }

    // Create view
    if create_view {
        vk_image_view_create(out_image, format, view_aspect_flags)
    }
}

@private
vk_image_view_create :: proc(image: ^Vulkan_Image, format: vk.Format,
                             aspect_flags: vk.ImageAspectFlags) {
    view_create_info := vk.ImageViewCreateInfo{
        sType = vk.StructureType.IMAGE_VIEW_CREATE_INFO,
        pNext = nil,
        flags = {},
        image = image.handle,
        viewType = .D2,                                 // TODO: Make configurable
        format = format,
        subresourceRange = vk.ImageSubresourceRange{
            aspectMask = aspect_flags,
            baseMipLevel = 0,                           // TODO: Make configurable
            levelCount = 1,                             // TODO: Make configurable
            baseArrayLayer = 0,                         // TODO: Make configurable
            layerCount = 1,                             // TODO: Make configurable
        },
    }

    result := vk.CreateImageView(global_context.device.logical_device, &view_create_info,
                                 global_context.allocator, &image.view)
    if result != vk.Result.SUCCESS {
        log.errorf("Failed to create image view: %v", result)
        return
    }
}

@private
vk_image_destroy :: proc(image: ^Vulkan_Image) {
    if image.view != 0 {
        vk.DestroyImageView(global_context.device.logical_device, image.view,
                            global_context.allocator)
        image.view = 0
    }
    if image.memory != 0 {
        vk.FreeMemory(global_context.device.logical_device, image.memory,
                      global_context.allocator)
        image.memory = 0
    }
    if image.handle != 0 {
        vk.DestroyImage(global_context.device.logical_device, image.handle,
                        global_context.allocator)
        image.handle = 0
    }
}