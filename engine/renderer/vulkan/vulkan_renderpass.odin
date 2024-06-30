package renderer_vulkan

import "core:log"
import "core:math/linalg"

import vk "vendor:vulkan"

// Creates a Vulkan render pass.
//
// Parameters:
//   window_context: ^Vulkan_Window_Context - Pointer to the window context.
//   out_render_pass: ^Vulkan_Render_Pass - Pointer to the render pass to be created.
//   render_area: linalg.Vector4f32 - The render area dimensions.
//   clear_color: linalg.Vector4f32 - The clear color for the render pass.
//   depth: f32 - The depth value for clearing the depth buffer.
//   stencil: u32 - The stencil value for clearing the stencil buffer.
@private
vk_render_pass_create :: proc(window_context: ^Vulkan_Window_Context,
                              out_render_pass: ^Vulkan_Render_Pass,
                              render_area: linalg.Vector4f32,
                              clear_color: linalg.Vector4f32,
                              depth: f32, stencil: u32) {
    out_render_pass.render_area = render_area
    out_render_pass.clear_color = clear_color
    out_render_pass.depth = depth
    out_render_pass.stencil = stencil
                                
    // Main subpass
    subpass := vk.SubpassDescription{
        pipelineBindPoint = .GRAPHICS,
    }

    // Attachments. TODO: make this configurable
    attachment_description_count := u32(2)
    attachment_descriptions := make([]vk.AttachmentDescription, attachment_description_count,
                                    context.temp_allocator)

    // Color attachment
    attachment_descriptions[0] = vk.AttachmentDescription{
        format = window_context.swapchain.image_format.format, // TODO: make this configurable
        samples = {._1},
        loadOp = .CLEAR,
        storeOp = .STORE,
        stencilLoadOp = .DONT_CARE,
        stencilStoreOp = .DONT_CARE,
        initialLayout = .UNDEFINED, // Do not expect any particular layout before render pass start
        finalLayout = .PRESENT_SRC_KHR, // Transitioned to after the render pass
        flags = {},
    }
    
    // Color attachment reference
    color_attachment_ref := vk.AttachmentReference{
        attachment = 0,
        layout = .COLOR_ATTACHMENT_OPTIMAL,
    }
    subpass.colorAttachmentCount = 1
    subpass.pColorAttachments = &color_attachment_ref

    // Depth attachment, if there is one
    attachment_descriptions[1] = vk.AttachmentDescription{
        format = global_context.device.depth_format,
        samples = {._1},
        loadOp = .CLEAR,
        storeOp = .DONT_CARE,
        stencilLoadOp = .DONT_CARE,
        stencilStoreOp = .DONT_CARE,
        initialLayout = .UNDEFINED,
        finalLayout = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
        flags = {},
    }

    // Depth attachment reference
    depth_attachment_ref := vk.AttachmentReference{
        attachment = 1,
        layout = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
    }
    
    // TODO: other attachment types (input, resolve, preserve)

    // Depth stencil data
    subpass.pDepthStencilAttachment = &depth_attachment_ref

    // Input from a shader
    subpass.inputAttachmentCount = 0
    subpass.pInputAttachments = nil

    // Attachments used for multisampling color attachments
    subpass.pResolveAttachments = nil

    // Attachments that are not used by this subpass, but must be preserved
    subpass.preserveAttachmentCount = 0
    subpass.pPreserveAttachments = nil

    // Render pass dependencies. TODO: make this configurable
    dependency := vk.SubpassDependency{
        srcSubpass = vk.SUBPASS_EXTERNAL,
        dstSubpass = 0,
        srcStageMask = {.COLOR_ATTACHMENT_OUTPUT},
        srcAccessMask = {},
        dstStageMask = {.COLOR_ATTACHMENT_OUTPUT},
        dstAccessMask = {.COLOR_ATTACHMENT_READ, .COLOR_ATTACHMENT_WRITE},
        dependencyFlags = {},
    }

    // Render pass create info
    render_pass_create_info := vk.RenderPassCreateInfo{
        sType = .RENDER_PASS_CREATE_INFO,
        attachmentCount = attachment_description_count,
        pAttachments = &attachment_descriptions[0],
        subpassCount = 1,
        pSubpasses = &subpass,
        dependencyCount = 1,
        pDependencies = &dependency,
        pNext = nil,
        flags = {},
    }

    result := vk.CreateRenderPass(global_context.device.logical_device,
                                  &render_pass_create_info,
                                  global_context.allocator,
                                  &out_render_pass.handle)
    if result != .SUCCESS {
        log.error("Failed to create render pass")
        return
    }
}

// Destroys a Vulkan render pass.
//
// Parameters:
//   render_pass: ^Vulkan_Render_Pass - Pointer to the render pass to be destroyed.
@private
vk_render_pass_destroy :: proc(render_pass: ^Vulkan_Render_Pass) {
    if render_pass.handle != 0 {
        vk.DestroyRenderPass(global_context.device.logical_device,
                             render_pass.handle,
                             global_context.allocator)
        render_pass.handle = 0
    }
}

// Begins a Vulkan render pass.
//
// Parameters:
//   command_buffer: ^Vulkan_Command_Buffer - Pointer to the command buffer.
//   render_pass: ^Vulkan_Render_Pass - Pointer to the render pass.
//   framebuffer: vk.Framebuffer - The framebuffer to be used.
@private
vk_render_pass_begin :: proc(command_buffer: ^Vulkan_Command_Buffer,
                             render_pass: ^Vulkan_Render_Pass,
                             framebuffer: vk.Framebuffer) {

    clear_values := [2]vk.ClearValue{
        vk.ClearValue{color = vk.ClearColorValue{float32 = ([4]f32)(render_pass.clear_color)}},
        vk.ClearValue{depthStencil = vk.ClearDepthStencilValue{depth = render_pass.depth,
                                                               stencil = render_pass.stencil}},
    }

    begin_info := vk.RenderPassBeginInfo{
        sType = .RENDER_PASS_BEGIN_INFO,
        renderPass = render_pass.handle,
        framebuffer = framebuffer,
        renderArea = vk.Rect2D{
            offset = vk.Offset2D{i32(render_pass.render_area.x),
                                 i32(render_pass.render_area.y)},
            extent = vk.Extent2D{u32(render_pass.render_area.z),
                                 u32(render_pass.render_area.w)},
        },
        clearValueCount = 2,
        pClearValues = &clear_values[0],
    }

    vk.CmdBeginRenderPass(command_buffer.handle, &begin_info, .INLINE)
    render_pass.state = .In_Render_Pass
}

// Ends a Vulkan render pass.
//
// Parameters:
//   command_buffer: ^Vulkan_Command_Buffer - Pointer to the command buffer.
//   render_pass: ^Vulkan_Render_Pass - Pointer to the render pass.
@private
vk_render_pass_end :: proc(command_buffer: ^Vulkan_Command_Buffer,
                           render_pass: ^Vulkan_Render_Pass) {
    vk.CmdEndRenderPass(command_buffer.handle)
    render_pass.state = .Recording
}