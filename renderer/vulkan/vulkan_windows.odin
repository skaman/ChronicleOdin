package renderer_vulkan

import "core:log"

import win32 "core:sys/windows"
import vk "vendor:vulkan"

@private
VULKAN_LIBRARY_NAME :: "vulkan-1.dll"

@private
VULKAN_PLATFORM_EXTENSIONS :: [1]cstring{vk.KHR_WIN32_SURFACE_EXTENSION_NAME}

@private
vk_platform_create_vulkan_surface :: proc(window_context: ^Vulkan_Render_Window_Context) -> b8 {
    create_info := vk.Win32SurfaceCreateInfoKHR {
        sType = vk.StructureType.WIN32_SURFACE_CREATE_INFO_KHR,
        pNext = nil,
        flags = {},
        hinstance = win32.HINSTANCE(window_context.instance),
        hwnd = win32.HWND(window_context.handle),
    }

    result := vk.CreateWin32SurfaceKHR(global_context.instance, &create_info, nil, &window_context.surface)
    if result != vk.Result.SUCCESS {
        log.errorf("Failed to create Vulkan surface: %v", result)
        return false
    }

    return true
}