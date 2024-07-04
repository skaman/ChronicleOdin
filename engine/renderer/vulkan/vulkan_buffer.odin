package renderer_vulkan

import "core:log"
import "core:math"
import "core:mem"

import vk "vendor:vulkan"

// Allocates a Vulkan buffer.
//
// Parameters:
//   size: u64 - The size of the buffer.
//   usage: vk.BufferUsageFlags - The usage flags of the buffer.
//   memory_property_flags: vk.MemoryPropertyFlags - The memory property flags of the buffer.
//   bind_on_create: b8 - Flag indicating whether to bind the buffer on creation.
//   out_buffer: ^Vulkan_Buffer - Pointer to the Vulkan buffer to be allocated.
// Returns:
//   b8 - Whether the buffer was allocated successfully.
@private
vk_buffer_create :: proc(size: u64,
                         usage: vk.BufferUsageFlags,
                         memory_property_flags: vk.MemoryPropertyFlags,
                         bind_on_create: b8,
                         out_buffer: ^Vulkan_Buffer) -> b8 {

    out_buffer^ = {}
    out_buffer.total_size = size
    out_buffer.usage = usage
    out_buffer.memory_property_flags = memory_property_flags

    buffer_create_info := vk.BufferCreateInfo{
        sType = .BUFFER_CREATE_INFO,
        size = vk.DeviceSize(size),
        usage = usage,
        sharingMode = .EXCLUSIVE,   // NOTE: only used in one queue
    }

    result := vk.CreateBuffer(g_context.device.logical_device,
                              &buffer_create_info,
                              g_context.allocator,
                              &out_buffer.handle)
    if result != .SUCCESS {
        log.error("Failed to create buffer")
        return false
    }
    
    // Memory requirements
    memory_requirements: vk.MemoryRequirements
    vk.GetBufferMemoryRequirements(g_context.device.logical_device,
                                   out_buffer.handle,
                                   &memory_requirements)
    out_buffer.memory_index = g_context.find_memory_index(memory_requirements.memoryTypeBits,
                                                               out_buffer.memory_property_flags)
    if out_buffer.memory_index == math.max(u32) {
        log.error("Failed to find memory index")
        return false
    }

    // Allocate memory
    memory_allocate_info := vk.MemoryAllocateInfo{
        sType = .MEMORY_ALLOCATE_INFO,
        allocationSize = memory_requirements.size,
        memoryTypeIndex = out_buffer.memory_index,
    }
    result = vk.AllocateMemory(g_context.device.logical_device,
                               &memory_allocate_info,
                               g_context.allocator,
                               &out_buffer.memory)
    if result != .SUCCESS {
        log.error("Failed to allocate memory")
        return false
    }

    // Bind memory
    if bind_on_create {
        vk_buffer_bind(out_buffer, 0)
    }

    return true
}

// Destroys a Vulkan buffer.
//
// Parameters:
//   buffer: ^Vulkan_Buffer - Pointer to the Vulkan buffer to be destroyed.
@private
vk_buffer_destroy :: proc(buffer: ^Vulkan_Buffer) {
    if buffer.memory != 0 {
        vk.FreeMemory(g_context.device.logical_device,
                      buffer.memory,
                      g_context.allocator)
        buffer.memory = 0
    }

    if buffer.handle != 0 {
        vk.DestroyBuffer(g_context.device.logical_device,
                         buffer.handle,
                         g_context.allocator)
        buffer.handle = 0
    }

    buffer.total_size = 0
    buffer.usage = {}
    buffer.is_locked = false
}

// Resizes a Vulkan buffer.
//
// Parameters:
//   new_size: u64 - The new size of the buffer.
//   buffer: ^Vulkan_Buffer - Pointer to the Vulkan buffer to be resized.
//   queue: vk.Queue - The queue to use for the resize operation.
//   pool: vk.CommandPool - The command pool to use for the resize operation.
// Returns:
//   b8 - Whether the buffer was resized successfully.
@private
vk_buffer_resize :: proc(new_size: u64,
                         buffer: ^Vulkan_Buffer,
                         queue: vk.Queue,
                         pool: vk.CommandPool) -> b8 {
    // Crate new buffer
    buffer_info := vk.BufferCreateInfo{
        sType = .BUFFER_CREATE_INFO,
        size = vk.DeviceSize(new_size),
        usage = buffer.usage,
        sharingMode = .EXCLUSIVE,
    }

    new_buffer: vk.Buffer
    result := vk.CreateBuffer(g_context.device.logical_device,
                              &buffer_info,
                              g_context.allocator,
                              &new_buffer)
    if result != .SUCCESS {
        log.error("Failed to create new buffer")
        return false
    }

    // Memory requirements
    memory_requirements: vk.MemoryRequirements
    vk.GetBufferMemoryRequirements(g_context.device.logical_device,
                                   new_buffer,
                                   &memory_requirements)

    // Allocate memory
    memory_allocate_info := vk.MemoryAllocateInfo{
        sType = .MEMORY_ALLOCATE_INFO,
        allocationSize = memory_requirements.size,
        memoryTypeIndex = buffer.memory_index,
    }

    new_memory: vk.DeviceMemory
    result = vk.AllocateMemory(g_context.device.logical_device,
                               &memory_allocate_info,
                               g_context.allocator,
                               &new_memory)
    if result != .SUCCESS {
        log.error("Failed to allocate new memory")
        return false
    }

    // Bind the new memory
    result = vk.BindBufferMemory(g_context.device.logical_device,
                                 new_buffer,
                                 new_memory,
                                 0)
    if result != .SUCCESS {
        log.error("Failed to bind new memory")
        return false
    }

    // Copy data
    vk_buffer_copy_to(pool, 0, queue, buffer.handle, 0, new_buffer, 0,
                      buffer.total_size)

    // Destroy old buffer
    if buffer.memory != 0 {
        vk.FreeMemory(g_context.device.logical_device,
                      buffer.memory,
                      g_context.allocator)
        buffer.memory = 0
    }

    if buffer.handle != 0 {
        vk.DestroyBuffer(g_context.device.logical_device,
                         buffer.handle,
                         g_context.allocator)
        buffer.handle = 0
    }

    // Set new properties
    buffer.handle = new_buffer
    buffer.memory = new_memory
    buffer.total_size = new_size

    return true
}

// Binds a Vulkan buffer to memory.
//
// Parameters:
//   buffer: ^Vulkan_Buffer - Pointer to the Vulkan buffer to bind.
//   offset: u64 - The offset to bind the buffer to.
@private
vk_buffer_bind :: proc(buffer: ^Vulkan_Buffer, offset: u64) {
    result := vk.BindBufferMemory(g_context.device.logical_device,
                                  buffer.handle,
                                  buffer.memory,
                                  vk.DeviceSize(offset))
    if result != .SUCCESS {
        log.error("Failed to bind buffer memory")
    }
}

// Locks Vulkan buffer memory.
//
// Parameters:
//   buffer: ^Vulkan_Buffer - Pointer to the Vulkan buffer to lock.
//   offset: u64 - The offset to lock the buffer at.
//   size: u64 - The size of the buffer to lock.
//   flags: vk.MemoryMapFlags - The memory map flags to use.
// Returns:
//   rawptr - The pointer to the locked memory.
@private
vk_buffer_lock_memory :: proc(buffer: ^Vulkan_Buffer, offset: u64, size: u64,
                              flags: vk.MemoryMapFlags) -> rawptr {
    data: rawptr
    result := vk.MapMemory(g_context.device.logical_device,
                           buffer.memory,
                           vk.DeviceSize(offset),
                           vk.DeviceSize(size),
                           flags,
                           &data)
    if result != .SUCCESS {
        log.error("Failed to map memory")
        return nil
    }

    return data
}

// Unlocks Vulkan buffer memory.
//
// Parameters:
//   buffer: ^Vulkan_Buffer - Pointer to the Vulkan buffer to unlock.
@private
vk_buffer_unlock_memory :: proc(buffer: ^Vulkan_Buffer) {
    vk.UnmapMemory(g_context.device.logical_device, buffer.memory)
}

// Loads data into a Vulkan buffer.
//
// Parameters:
//   buffer: ^Vulkan_Buffer - Pointer to the Vulkan buffer to load data into.
//   offset: u64 - The offset to load the data into.
//   size: u64 - The size of the data to load.
//   flags: vk.MemoryMapFlags - The memory map flags to use.
//   data: rawptr - The data to load into the buffer.
@private
vk_buffer_load_data :: proc(buffer: ^Vulkan_Buffer, offset: u64, size: u64,
                            flags: vk.MemoryMapFlags, data: rawptr) {
    data_ptr: rawptr
    result := vk.MapMemory(g_context.device.logical_device,
                           buffer.memory,
                           vk.DeviceSize(offset),
                           vk.DeviceSize(size),
                           flags,
                           &data_ptr)
    if result != .SUCCESS {
        log.error("Failed to map memory")
        return
    }

    mem.copy(data_ptr, data, int(size))

    vk.UnmapMemory(g_context.device.logical_device, buffer.memory)
}

// Copies data from one Vulkan buffer to another.
//
// Parameters:
//   pool: vk.CommandPool - The command pool to use for the copy operation.
//   fence: vk.Fence - The fence to use for the copy operation.
//   queue: vk.Queue - The queue to use for the copy operation.
//   source: vk.Buffer - The source buffer.
//   source_offset: u64 - The offset in the source buffer.
//   dest: vk.Buffer - The destination buffer.
//   dest_offset: u64 - The offset in the destination buffer.
//   size: u64 - The size of the data to copy.
@private
vk_buffer_copy_to :: proc(pool: vk.CommandPool,
                          fence: vk.Fence,
                          queue: vk.Queue,
                          source: vk.Buffer,
                          source_offset: u64,
                          dest: vk.Buffer,
                          dest_offset: u64,
                          size: u64) {
    vk.QueueWaitIdle(queue)

    // Create one-time-use command buffer
    temp_command_buffer: Vulkan_Command_Buffer
    vk_command_buffer_allocate_and_begin_single_use(pool, &temp_command_buffer)

    // Prepare the copy command and add it to the command buffer.
    copy_region := vk.BufferCopy{
        srcOffset = vk.DeviceSize(source_offset),
        dstOffset = vk.DeviceSize(dest_offset),
        size = vk.DeviceSize(size),
    }

    vk.CmdCopyBuffer(temp_command_buffer.handle, source, dest, 1, &copy_region)

    // Submit the buffer for execution and wait for it to complete.
    vk_command_buffer_end_single_use(pool, &temp_command_buffer, queue)
}