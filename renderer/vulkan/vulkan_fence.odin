package renderer_vulkan

import "core:log"

import vk "vendor:vulkan"

@private
vk_fence_create :: proc(create_signaled: b8, out_fence: ^Vulkan_Fence) {
    
    out_fence.is_signaled = create_signaled
    
    create_info := vk.FenceCreateInfo{
        sType = .FENCE_CREATE_INFO,
        flags = create_signaled ? {.SIGNALED} : {},
    }

    result := vk.CreateFence(global_context.device.logical_device,
                             &create_info,
                             global_context.allocator,
                             &out_fence.handle)
    if result != .SUCCESS {
        log.error("Failed to create fence")
        return
    }
}

@private
vk_fence_destroy :: proc(fence: ^Vulkan_Fence) {
    if fence.handle != 0 {
        vk.DestroyFence(global_context.device.logical_device,
                        fence.handle,
                        global_context.allocator)
        fence.handle = 0
    }

    fence.is_signaled = false
}

@private
vk_fence_wait :: proc(fence: ^Vulkan_Fence, timeout_ns: u64) -> b8 {
    if !fence.is_signaled {
        result := vk.WaitForFences(global_context.device.logical_device,
                                   1,
                                   &fence.handle,
                                   true,
                                   timeout_ns)
        #partial switch result {
        case .SUCCESS:
            fence.is_signaled = true
            return true
        case .TIMEOUT:
            log.warn("Fence wait timed out")
        case .ERROR_DEVICE_LOST:
            log.error("Device lost")
        case .ERROR_OUT_OF_HOST_MEMORY:
            log.error("Out of host memory")
        case .ERROR_OUT_OF_DEVICE_MEMORY:
            log.error("Out of device memory")
        case:
            log.error("Failed to wait for fence")
        }
    }
    else {
        // if the fence is already signaled, don't wait
        return true
    }

    return false
}

@private
vk_fence_reset :: proc(fence: ^Vulkan_Fence) {
    if fence.is_signaled {
        result := vk.ResetFences(global_context.device.logical_device,
            1,
            &fence.handle)
        if result != .SUCCESS {
            log.error("Failed to reset fence")
            return
        }

        fence.is_signaled = false
    }
}