package renderer_vulkan

import "core:log"

import vk "vendor:vulkan"

// Allocates a Vulkan command buffer.
//
// Parameters:
//   pool: vk.CommandPool - The command pool from which to allocate the command buffer.
//   is_primary: b8 - Flag indicating whether the command buffer is primary.
//   out_command_buffer: ^Vulkan_Command_Buffer - Pointer to the Vulkan command buffer to be allocated.
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
    result := vk.AllocateCommandBuffers(g_context.device.logical_device,
                                        &allocate_info,
                                        &out_command_buffer.handle)
    if result != .SUCCESS {
        log.error("Failed to allocate command buffer")
        return
    }
    out_command_buffer.state = .Ready
}

// Frees a Vulkan command buffer.
//
// Parameters:
//   pool: vk.CommandPool - The command pool from which to free the command buffer.
//   command_buffer: ^Vulkan_Command_Buffer - Pointer to the Vulkan command buffer to be freed.
@private
vk_command_buffer_free :: proc(pool: vk.CommandPool, command_buffer: ^Vulkan_Command_Buffer) {
    vk.FreeCommandBuffers(g_context.device.logical_device,
                          pool,
                          1,
                          &command_buffer.handle)

    command_buffer.state = .Not_Allocated
    command_buffer.handle = nil
}

// Begins recording a Vulkan command buffer.
//
// Parameters:
//   command_buffer: ^Vulkan_Command_Buffer - Pointer to the Vulkan command buffer to begin recording.
//   is_single_use: b8 - Flag indicating whether the command buffer is for single use.
//   is_render_pass_continue: b8 - Flag indicating whether the command buffer is for render pass continuation.
//   is_simultaneous_use: b8 - Flag indicating whether the command buffer can be used simultaneously.
@private
vk_command_buffer_begin :: proc(command_buffer: ^Vulkan_Command_Buffer,
                                is_single_use: b8,
                                is_render_pass_continue: b8,
                                is_simultaneous_use: b8) {
    flags: vk.CommandBufferUsageFlags;
    if is_single_use {
        flags |= {.ONE_TIME_SUBMIT}
    }
    if is_render_pass_continue {
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

// Ends recording a Vulkan command buffer.
//
// Parameters:
//   command_buffer: ^Vulkan_Command_Buffer - Pointer to the Vulkan command buffer to end recording.
@private
vk_command_buffer_end :: proc(command_buffer: ^Vulkan_Command_Buffer) {
    result := vk.EndCommandBuffer(command_buffer.handle)
    if result != .SUCCESS {
        log.error("Failed to end command buffer")
        return
    }

    command_buffer.state = .Recording_Ended
}

// Updates the state of a submitted Vulkan command buffer.
//
// Parameters:
//   command_buffer: ^Vulkan_Command_Buffer - Pointer to the Vulkan command buffer to update.
@private
vk_command_buffer_update_submitted :: proc(command_buffer: ^Vulkan_Command_Buffer) {
    command_buffer.state = .Submitted
}

// Resets a Vulkan command buffer.
//
// Parameters:
//   command_buffer: ^Vulkan_Command_Buffer - Pointer to the Vulkan command buffer to reset.
@private
vk_command_buffer_reset :: proc(command_buffer: ^Vulkan_Command_Buffer) {
    command_buffer.state = .Ready
}

// Allocates and begins a single-use Vulkan command buffer.
//
// Parameters:
//   pool: vk.CommandPool - The command pool from which to allocate the command buffer.
//   out_command_buffer: ^Vulkan_Command_Buffer - Pointer to the Vulkan command buffer to be allocated and started.
@private
vk_command_buffer_allocate_and_begin_single_use :: proc(pool: vk.CommandPool,
                                                       out_command_buffer: ^Vulkan_Command_Buffer) {
    vk_command_buffer_allocate(pool, true, out_command_buffer)
    vk_command_buffer_begin(out_command_buffer, true, false, false)
}

// Ends a single-use Vulkan command buffer.
//
// Parameters:
//   pool: vk.CommandPool - The command pool from which to free the command buffer.
//   out_command_buffer: ^Vulkan_Command_Buffer - Pointer to the Vulkan command buffer to end.
//   queue: vk.Queue - The queue to submit the command buffer to.
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