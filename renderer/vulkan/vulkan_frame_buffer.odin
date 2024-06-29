package renderer_vulkan

import "core:log"

import vk "vendor:vulkan"

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

    result := vk.CreateFramebuffer(global_context.device.logical_device,
                                   &frame_buffer_create_info,
                                   global_context.allocator,
                                   &out_frame_buffer.handle)
    if result != .SUCCESS {
        log.error("Failed to create frame buffer")
        return
    }
}

@private
vk_frame_buffer_destroy :: proc(frame_buffer: ^Vulkan_Frame_Buffer) {
    vk.DestroyFramebuffer(global_context.device.logical_device,
                          frame_buffer.handle,
                          global_context.allocator)

    if (frame_buffer.attachments != nil) {
        delete(frame_buffer.attachments)
        frame_buffer.attachments = nil
    }

    frame_buffer.handle = 0
}