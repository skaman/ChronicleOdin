package renderer_vulkan

import "core:log"

import vk "vendor:vulkan"

// Creates a Vulkan fence.
//
// Parameters:
//   create_signaled: b8 - Flag indicating whether the fence should be created in a signaled state.
//   out_fence: ^Vulkan_Fence - Pointer to the Vulkan fence to be created.
@private
vk_fence_create :: proc(create_signaled: b8, out_fence: ^Vulkan_Fence) {
    
    out_fence.is_signaled = create_signaled
    
    create_info := vk.FenceCreateInfo{
        sType = .FENCE_CREATE_INFO,
        flags = create_signaled ? {.SIGNALED} : {},
    }

    result := vk.CreateFence(g_context.device.logical_device,
                             &create_info,
                             g_context.allocator,
                             &out_fence.handle)
    if result != .SUCCESS {
        log.error("Failed to create fence")
        return
    }
}

// Destroys a Vulkan fence.
//
// Parameters:
//   fence: ^Vulkan_Fence - Pointer to the Vulkan fence to be destroyed.
@private
vk_fence_destroy :: proc(fence: ^Vulkan_Fence) {
    if fence.handle != 0 {
        vk.DestroyFence(g_context.device.logical_device,
                        fence.handle,
                        g_context.allocator)
        fence.handle = 0
    }

    fence.is_signaled = false
}

// Waits for a Vulkan fence to be signaled.
//
// Parameters:
//   fence: ^Vulkan_Fence - Pointer to the Vulkan fence to wait for.
//   timeout_ns: u64 - Timeout in nanoseconds.
//
// Returns:
//   b8 - True if the fence was successfully waited for, otherwise false.
@private
vk_fence_wait :: proc(fence: ^Vulkan_Fence, timeout_ns: u64) -> b8 {
    if !fence.is_signaled {
        result := vk.WaitForFences(g_context.device.logical_device,
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

// Resets a Vulkan fence.
//
// Parameters:
//   fence: ^Vulkan_Fence - Pointer to the Vulkan fence to be reset.
@private
vk_fence_reset :: proc(fence: ^Vulkan_Fence) {
    if fence.is_signaled {
        result := vk.ResetFences(g_context.device.logical_device,
            1,
            &fence.handle)
        if result != .SUCCESS {
            log.error("Failed to reset fence")
            return
        }

        fence.is_signaled = false
    }
}