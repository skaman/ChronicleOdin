package renderer_vulkan

import vk "vendor:vulkan"

@private
vk_result_to_string :: proc(result: vk.Result) -> (string, string) {
    // From: https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkResult.html
    #partial switch result {
    case:
        return "SUCCESS", "Command successfully completed"
    case .NOT_READY:
        return "NOT_READY", "A fence or query has not yet completed"
    case .TIMEOUT:
        return "TIMEOUT", "A wait operation has not completed in the specified time"
    case .EVENT_SET:
        return "EVENT_SET", "An event is signaled"
    case .EVENT_RESET:
        return "EVENT_RESET", "An event is unsignaled"
    case .INCOMPLETE:
        return "INCOMPLETE", "A return array was too small for the result"
    case .SUBOPTIMAL_KHR:
        return "SUBOPTIMAL_KHR", "A swapchain no longer matches the surface properties exactly, but can still be used to present to the surface successfully."
    case .THREAD_IDLE_KHR:
        return "VK_THREAD_IDLE_KHR", "A deferred operation is not complete but there is currently no work for this thread to do at the time of this call."
    case .THREAD_DONE_KHR:
        return "VK_THREAD_DONE_KHR", "A deferred operation is not complete but there is no work remaining to assign to additional threads."
    case .OPERATION_DEFERRED_KHR:
        return "VK_OPERATION_DEFERRED_KHR", "A deferred operation was requested and at least some of the work was deferred."
    case .OPERATION_NOT_DEFERRED_KHR:
        return "VK_OPERATION_NOT_DEFERRED_KHR", "A deferred operation was requested and no operations were deferred."
    case .PIPELINE_COMPILE_REQUIRED_EXT:
        return "VK_PIPELINE_COMPILE_REQUIRED_EXT", "A requested pipeline creation would have required compilation, but the application requested compilation to not be performed."

    // Error codes
    case .ERROR_OUT_OF_HOST_MEMORY:
        return "VK_ERROR_OUT_OF_HOST_MEMORY", "A host memory allocation has failed."
    case .ERROR_OUT_OF_DEVICE_MEMORY:
        return "VK_ERROR_OUT_OF_DEVICE_MEMORY", "A device memory allocation has failed."
    case .ERROR_INITIALIZATION_FAILED:
        return "VK_ERROR_INITIALIZATION_FAILED", "Initialization of an object could not be completed for implementation-specific reasons."
    case .ERROR_DEVICE_LOST:
        return "VK_ERROR_DEVICE_LOST", "The logical or physical device has been lost. See Lost Device"
    case .ERROR_MEMORY_MAP_FAILED:
        return "VK_ERROR_MEMORY_MAP_FAILED", "Mapping of a memory object has failed."
    case .ERROR_LAYER_NOT_PRESENT:
        return "VK_ERROR_LAYER_NOT_PRESENT", "A requested layer is not present or could not be loaded."
    case .ERROR_EXTENSION_NOT_PRESENT:
        return "VK_ERROR_EXTENSION_NOT_PRESENT", "A requested extension is not supported."
    case .ERROR_FEATURE_NOT_PRESENT:
        return "VK_ERROR_FEATURE_NOT_PRESENT", "A requested feature is not supported."
    case .ERROR_INCOMPATIBLE_DRIVER:
        return "VK_ERROR_INCOMPATIBLE_DRIVER", "The requested version of Vulkan is not supported by the driver or is otherwise incompatible for implementation-specific reasons."
    case .ERROR_TOO_MANY_OBJECTS:
        return "VK_ERROR_TOO_MANY_OBJECTS", "Too many objects of the type have already been created."
    case .ERROR_FORMAT_NOT_SUPPORTED:
        return "VK_ERROR_FORMAT_NOT_SUPPORTED", "A requested format is not supported on this device."
    case .ERROR_FRAGMENTED_POOL:
        return "VK_ERROR_FRAGMENTED_POOL", "A pool allocation has failed due to fragmentation of the pool’s memory. This must only be returned if no attempt to allocate host or device memory was made to accommodate the new allocation. This should be returned in preference to VK_ERROR_OUT_OF_POOL_MEMORY, but only if the implementation is certain that the pool allocation failure was due to fragmentation."
    case .ERROR_SURFACE_LOST_KHR:
        return "VK_ERROR_SURFACE_LOST_KHR", "A surface is no longer available."
    case .ERROR_NATIVE_WINDOW_IN_USE_KHR:
        return "VK_ERROR_NATIVE_WINDOW_IN_USE_KHR", "The requested window is already in use by Vulkan or another API in a manner which prevents it from being used again."
    case .ERROR_OUT_OF_DATE_KHR:
        return "VK_ERROR_OUT_OF_DATE_KHR", "A surface has changed in such a way that it is no longer compatible with the swapchain, and further presentation requests using the swapchain will fail. Applications must query the new surface properties and recreate their swapchain if they wish to continue presenting to the surface."
    case .ERROR_INCOMPATIBLE_DISPLAY_KHR:
        return "VK_ERROR_INCOMPATIBLE_DISPLAY_KHR", "The display used by a swapchain does not use the same presentable image layout, or is incompatible in a way that prevents sharing an image."
    case .ERROR_INVALID_SHADER_NV:
        return "VK_ERROR_INVALID_SHADER_NV", "One or more shaders failed to compile or link. More details are reported back to the application via VK_EXT_debug_report if enabled."
    case .ERROR_OUT_OF_POOL_MEMORY:
        return "VK_ERROR_OUT_OF_POOL_MEMORY", "A pool memory allocation has failed. This must only be returned if no attempt to allocate host or device memory was made to accommodate the new allocation. If the failure was definitely due to fragmentation of the pool, VK_ERROR_FRAGMENTED_POOL should be returned instead."
    case .ERROR_INVALID_EXTERNAL_HANDLE:
        return "VK_ERROR_INVALID_EXTERNAL_HANDLE", "An external handle is not a valid handle of the specified type."
    case .ERROR_FRAGMENTATION:
        return "VK_ERROR_FRAGMENTATION", "A descriptor pool creation has failed due to fragmentation."
    case .ERROR_INVALID_DEVICE_ADDRESS_EXT:
        return "VK_ERROR_INVALID_DEVICE_ADDRESS_EXT", "A buffer creation failed because the requested address is not available."
    // NOTE: Same as above
    //case .ERROR_INVALID_OPAQUE_CAPTURE_ADDRESS:
    //    return "VK_ERROR_INVALID_OPAQUE_CAPTURE_ADDRESS", "A buffer creation or memory allocation failed because the requested address is not available. A shader group handle assignment failed because the requested shader group handle information is no longer valid."
    case .ERROR_FULL_SCREEN_EXCLUSIVE_MODE_LOST_EXT:
        return "VK_ERROR_FULL_SCREEN_EXCLUSIVE_MODE_LOST_EXT", "An operation on a swapchain created with VK_FULL_SCREEN_EXCLUSIVE_APPLICATION_CONTROLLED_EXT failed as it did not have exlusive full-screen access. This may occur due to implementation-dependent reasons, outside of the application’s control."
    case .ERROR_UNKNOWN:
        return "VK_ERROR_UNKNOWN", "An unknown error has occurred; either the application has provided invalid input, or an implementation failure has occurred."
    }
}

vk_result_is_success :: proc(result: vk.Result) -> b8 {
    // From: https://www.khronos.org/registry/vulkan/specs/1.2-extensions/man/html/VkResult.html
    #partial switch result {
    // Success Codes
    case:
        return true;

    // Error codes
    case .ERROR_OUT_OF_HOST_MEMORY,
         .ERROR_OUT_OF_DEVICE_MEMORY,
         .ERROR_INITIALIZATION_FAILED,
         .ERROR_DEVICE_LOST,
         .ERROR_MEMORY_MAP_FAILED,
         .ERROR_LAYER_NOT_PRESENT,
         .ERROR_EXTENSION_NOT_PRESENT,
         .ERROR_FEATURE_NOT_PRESENT,
         .ERROR_INCOMPATIBLE_DRIVER,
         .ERROR_TOO_MANY_OBJECTS,
         .ERROR_FORMAT_NOT_SUPPORTED,
         .ERROR_FRAGMENTED_POOL,
         .ERROR_SURFACE_LOST_KHR,
         .ERROR_NATIVE_WINDOW_IN_USE_KHR,
         .ERROR_OUT_OF_DATE_KHR,
         .ERROR_INCOMPATIBLE_DISPLAY_KHR,
         .ERROR_INVALID_SHADER_NV,
         .ERROR_OUT_OF_POOL_MEMORY,
         .ERROR_INVALID_EXTERNAL_HANDLE,
         .ERROR_FRAGMENTATION,
         .ERROR_INVALID_DEVICE_ADDRESS_EXT,
        // NOTE: Same as above
        //.ERROR_INVALID_OPAQUE_CAPTURE_ADDRESS:
         .ERROR_FULL_SCREEN_EXCLUSIVE_MODE_LOST_EXT,
         .ERROR_UNKNOWN:
        return false;
    }
}