package renderer_vulkan

import "core:log"

import vk "vendor:vulkan"

// Creates a Vulkan frame buffer.
//
// Parameters:
//   render_pass: ^Vulkan_Render_Pass - Pointer to the render pass associated with the frame buffer.
//   width: u32 - The width of the frame buffer.
//   height: u32 - The height of the frame buffer.
//   attachments: []vk.ImageView - Array of image views to be attached to the frame buffer.
//   out_frame_buffer: ^Vulkan_Frame_Buffer - Pointer to the Vulkan frame buffer to be created.
@private
vk_frame_buffer_create :: proc(render_pass: ^Vulkan_Render_Pass,
                               width: u32, height: u32,
                               attachments: []vk.ImageView,
                               out_frame_buffer: ^Vulkan_Frame_Buffer) {
    // Take a copy of the attachments and render pass
    out_frame_buffer.attachments = make([]vk.ImageView, len(attachments))
    copy(out_frame_buffer.attachments, attachments)
    out_frame_buffer.render_pass = render_pass

    // Create info
    frame_buffer_create_info := vk.FramebufferCreateInfo{
        sType = .FRAMEBUFFER_CREATE_INFO,
        renderPass = render_pass.handle,
        attachmentCount = u32(len(out_frame_buffer.attachments)),
        pAttachments = &out_frame_buffer.attachments[0],
        width = width,
        height = height,
        layers = 1,
    }

    result := vk.CreateFramebuffer(g_context.device.logical_device,
                                   &frame_buffer_create_info,
                                   g_context.allocator,
                                   &out_frame_buffer.handle)
    if result != .SUCCESS {
        log.error("Failed to create frame buffer")
        return
    }
}

// Destroys a Vulkan frame buffer.
//
// Parameters:
//   frame_buffer: ^Vulkan_Frame_Buffer - Pointer to the Vulkan frame buffer to be destroyed.
@private
vk_frame_buffer_destroy :: proc(frame_buffer: ^Vulkan_Frame_Buffer) {
    vk.DestroyFramebuffer(g_context.device.logical_device,
                          frame_buffer.handle,
                          g_context.allocator)

    if (frame_buffer.attachments != nil) {
        delete(frame_buffer.attachments)
        frame_buffer.attachments = nil
    }

    frame_buffer.handle = 0
}