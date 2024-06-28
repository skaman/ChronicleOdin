package renderer_vulkan

import "core:log"

import vk "vendor:vulkan"

@private
vk_command_buffer_allocate :: proc(pool: vk.CommandPool, is_primary: b8,
                                   out_command_buffer: ^Vulkan_Command_Buffer) {
    out_command_buffer^ = {}

    allocate_info := vk.CommandBufferAllocateInfo{
        sType = .COMMAND_BUFFER_ALLOCATE_INFO,
        commandPool = pool,
        level = is_primary ? .PRIMARY : .SECONDARY,
        commandBufferCount = 1,
        pNext = nil,
    }

    out_command_buffer.state = .Not_Allocated
    result := vk.AllocateCommandBuffers(global_context.device.logical_device,
                                        &allocate_info,
                                        &out_command_buffer.handle)
    if result != .SUCCESS {
        log.error("Failed to allocate command buffer")
        return
    }
    out_command_buffer.state = .Ready
}

@private
vk_command_buffer_free :: proc(pool: vk.CommandPool, command_buffer: ^Vulkan_Command_Buffer) {
    vk.FreeCommandBuffers(global_context.device.logical_device,
                          pool,
                          1,
                          &command_buffer.handle)

    command_buffer.state = .Not_Allocated
    command_buffer.handle = nil
}

@private
vk_command_buffer_begin :: proc(command_buffer: ^Vulkan_Command_Buffer,
                                is_single_use: b8,
                                is_renderpass_continue: b8,
                                is_simultaneous_use: b8) {
    flags: vk.CommandBufferUsageFlags;
    if is_single_use {
        flags |= {.ONE_TIME_SUBMIT}
    }
    if is_renderpass_continue {
        flags |= {.RENDER_PASS_CONTINUE}
    }
    if is_simultaneous_use {
        flags |= {.SIMULTANEOUS_USE}
    }

    begin_info := vk.CommandBufferBeginInfo{
        sType = .COMMAND_BUFFER_BEGIN_INFO,
        pNext = nil,
        flags = flags,
        pInheritanceInfo = nil,
    }

    result := vk.BeginCommandBuffer(command_buffer.handle, &begin_info)
    if result != .SUCCESS {
        log.error("Failed to begin command buffer")
        return
    }

    command_buffer.state = .Recording
}

@private
vk_command_buffer_end :: proc(command_buffer: ^Vulkan_Command_Buffer) {
    result := vk.EndCommandBuffer(command_buffer.handle)
    if result != .SUCCESS {
        log.error("Failed to end command buffer")
        return
    }

    command_buffer.state = .Recording_Ended
}

@private
vk_command_buffer_update_submitted :: proc(command_buffer: ^Vulkan_Command_Buffer) {
    command_buffer.state = .Submitted
}

@private
vk_command_buffer_reset :: proc(command_buffer: ^Vulkan_Command_Buffer) {
    command_buffer.state = .Ready
}

@private
vk_command_buffer_allocate_and_begin_single_use :: proc(pool: vk.CommandPool,
                                                       out_command_buffer: ^Vulkan_Command_Buffer) {
    vk_command_buffer_allocate(pool, true, out_command_buffer)
    vk_command_buffer_begin(out_command_buffer, true, false, false)
}

@private
vk_command_buffer_end_single_use :: proc(pool: vk.CommandPool, 
                                         out_command_buffer: ^Vulkan_Command_Buffer,
                                         queue: vk.Queue) {

    // End the command buffer
    vk_command_buffer_end(out_command_buffer)

    // Submit the queue
    submit_info := vk.SubmitInfo{
        sType = .SUBMIT_INFO,
        commandBufferCount = 1,
        pCommandBuffers = &out_command_buffer.handle,
    }
    result := vk.QueueSubmit(queue, 1, &submit_info, 0)
    if result != .SUCCESS {
        log.error("Failed to submit queue")
        return
    }

    // Wait for the queue to finish
    result = vk.QueueWaitIdle(queue)
    if result != .SUCCESS {
        log.error("Failed to wait for queue to finish")
        return
    }

    // Free the command buffer
    vk_command_buffer_free(pool, out_command_buffer)
}