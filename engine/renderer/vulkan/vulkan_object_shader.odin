package renderer_vulkan

import "core:log"
import "core:math/linalg"

import vk "vendor:vulkan"

import rt "../types"

BUILTIN_SHADER_NAME_OBJECT :: "builtin_object_shader"

// Create an object shader.
//
// Parameters:
//   window_context: ^Vulkan_Window_Context - Pointer to the window context.
//   out_shader: ^Vulkan_Object_Shader - Pointer to the object shader to be created.
// Returns:
//   b8 - Whether the object shader was created successfully.
vk_object_shader_create :: proc(window_context: ^Vulkan_Window_Context,
                                out_shader: ^Vulkan_Object_Shader) -> b8 {
    stage_type_strings := [OBJECT_SHADER_STAGE_COUNT]string{"vert", "frag"}
    stage_types := [OBJECT_SHADER_STAGE_COUNT]vk.ShaderStageFlags{{.VERTEX}, {.FRAGMENT}}

    for i in 0..<OBJECT_SHADER_STAGE_COUNT {
        if !vk_create_shader_module(BUILTIN_SHADER_NAME_OBJECT,
                                    stage_type_strings[i], stage_types[i], i,
                                    out_shader.stages[:]) {
            log.errorf("Unable to create %s shader module for '%s",
                       stage_type_strings[i], BUILTIN_SHADER_NAME_OBJECT)
            return false
        }
    }

    // Global Descriptors
    global_ubo_layout_binding := vk.DescriptorSetLayoutBinding{
        binding = 0,
        descriptorCount = 1,
        descriptorType = .UNIFORM_BUFFER,
        pImmutableSamplers = nil,
        stageFlags = {.VERTEX},
    }

    global_layout_create_info := vk.DescriptorSetLayoutCreateInfo{
        sType = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
        bindingCount = 1,
        pBindings = &global_ubo_layout_binding,
    }

    result := vk.CreateDescriptorSetLayout(g_context.device.logical_device,
                                           &global_layout_create_info,
                                           g_context.allocator,
                                           &out_shader.global_descriptor_set_layout)
    if result != .SUCCESS {
        log.error("Failed to create global descriptor set layout")
        return false
    }

    // Global Descriptor Pool
    global_pool_size := vk.DescriptorPoolSize{
        type = .UNIFORM_BUFFER,
        descriptorCount = u32(len(window_context.swapchain.images)),
    }

    global_pool_info := vk.DescriptorPoolCreateInfo{
        sType = .DESCRIPTOR_POOL_CREATE_INFO,
        poolSizeCount = 1,
        pPoolSizes = &global_pool_size,
        maxSets = u32(len(window_context.swapchain.images)),
    }

    result = vk.CreateDescriptorPool(g_context.device.logical_device,
                                     &global_pool_info,
                                     g_context.allocator,
                                     &out_shader.global_descriptor_pool)
    if result != .SUCCESS {
        log.error("Failed to create global descriptor pool")
        return false
    }

    // Pipeline creation
    viewport := vk.Viewport{
        x = 0.0,
        y = f32(window_context.frame_buffer_height),
        width = f32(window_context.frame_buffer_width),
        height = -f32(window_context.frame_buffer_height),
        minDepth = 0.0,
        maxDepth = 1.0,
    }

    // Scissor
    scissor := vk.Rect2D{
        offset = vk.Offset2D{0, 0},
        extent = vk.Extent2D{window_context.frame_buffer_width,
                             window_context.frame_buffer_height},
    }

    // Attributes
    offset := u32(0)
    ATTRIBUTE_COUNT :: u32(1)
    attribute_descriptions: [ATTRIBUTE_COUNT]vk.VertexInputAttributeDescription
    
    formats := [ATTRIBUTE_COUNT]vk.Format{.R32G32B32_SFLOAT}
    sizes := [ATTRIBUTE_COUNT]u64{size_of(linalg.Vector3f32)}

    for i in 0..<ATTRIBUTE_COUNT {
        attribute_descriptions[i].location = i
        attribute_descriptions[i].binding = 0
        attribute_descriptions[i].format = formats[i]
        attribute_descriptions[i].offset = offset
        offset += u32(sizes[i])
    }

    // Descriptor set layout
    DESCRIPTOR_SET_LAYOUT_COUNT :: u32(1)
    layouts := [DESCRIPTOR_SET_LAYOUT_COUNT]vk.DescriptorSetLayout{
        out_shader.global_descriptor_set_layout
    }

    // Stages
    // NOTES: Should match the number of shader->stages
    stage_create_infos: [OBJECT_SHADER_STAGE_COUNT]vk.PipelineShaderStageCreateInfo
    for i in 0..<OBJECT_SHADER_STAGE_COUNT {
        //stage_create_infos[i].sType = out_shader.stages[i].shader_stage_create_info.sType
        stage_create_infos[i] = out_shader.stages[i].shader_stage_create_info
    }
    
    if !vk_graphics_pipeline_create(&window_context.main_render_pass,
                                    attribute_descriptions[:],
                                    layouts[:],
                                    stage_create_infos[:],
                                    viewport,
                                    scissor,
                                    false,
                                    &out_shader.pipeline) {
        log.errorf("Unable to create graphics pipeline for '%s'", BUILTIN_SHADER_NAME_OBJECT)
        return false
    }

    // Create uniform buffer
    if !vk_buffer_create(size_of(rt.Global_Uniform_Object) * 3,
                         {.TRANSFER_DST, .UNIFORM_BUFFER},
                         {.DEVICE_LOCAL, .HOST_VISIBLE, .HOST_COHERENT},
                         true,
                         &out_shader.global_ubo_buffer) {
        log.error("Failed to create global uniform buffer")
        return false
    }

    // Allocate global descriptor sets
    global_layouts := [3]vk.DescriptorSetLayout{
        out_shader.global_descriptor_set_layout,
        out_shader.global_descriptor_set_layout,
        out_shader.global_descriptor_set_layout
    }

    alloc_info := vk.DescriptorSetAllocateInfo{
        sType = .DESCRIPTOR_SET_ALLOCATE_INFO,
        descriptorPool = out_shader.global_descriptor_pool,
        descriptorSetCount = 3,
        pSetLayouts = &global_layouts[0],
    }

    result = vk.AllocateDescriptorSets(g_context.device.logical_device,
                                       &alloc_info,
                                       &out_shader.global_descriptor_sets[0])
    if result != .SUCCESS {
        log.error("Failed to allocate global descriptor sets")
        return false
    }

    return true
}

// Destroy an object shader.
//
// Parameters:
//   shader: ^Vulkan_Object_Shader - Pointer to the object shader to be destroyed.
vk_object_shader_destroy :: proc(shader: ^Vulkan_Object_Shader) {
    logical_device := g_context.device.logical_device

    // Destroy global descriptor set layout
    vk.DestroyDescriptorSetLayout(logical_device, shader.global_descriptor_set_layout,
                                  g_context.allocator)

    // Destroy uniform buffer
    vk_buffer_destroy(&shader.global_ubo_buffer)

    // Destroy pipeline
    vk_pipeline_destroy(&shader.pipeline)

    // Destroy global descriptor pool
    vk.DestroyDescriptorPool(logical_device, shader.global_descriptor_pool,
                             g_context.allocator)

    // Destroy shader modules
    for i in 0..<OBJECT_SHADER_STAGE_COUNT {
        vk.DestroyShaderModule(logical_device, shader.stages[i].handle,
                                g_context.allocator)
        shader.stages[i].handle = 0
    }
}

// Use an object shader.
//
// Parameters:
//   window_context: ^Vulkan_Window_Context - Pointer to the window context.
//   shader: ^Vulkan_Object_Shader - Pointer to the object shader to be used.
vk_object_shader_use :: proc(window_context: ^Vulkan_Window_Context,
                             shader: ^Vulkan_Object_Shader) {
    
}

// Update the global state of an object shader.
//
// Parameters:
//   window_context: ^Vulkan_Window_Context - Pointer to the window context.
//   shader: ^Vulkan_Object_Shader - Pointer to the object shader to be updated.
vk_object_shader_update_global_state :: proc(window_context: ^Vulkan_Window_Context,
                                             shader: ^Vulkan_Object_Shader) {
    image_index := window_context.image_index
    command_buffer := window_context.graphics_command_buffers[image_index].handle
    global_descriptor := shader.global_descriptor_sets[image_index]

    // Configure the descriptors for the given index
    range := u64(size_of(rt.Global_Uniform_Object))
    offset := u64(size_of(rt.Global_Uniform_Object) * image_index)

    // Copy data to buffer
    vk_buffer_load_data(&shader.global_ubo_buffer, offset, range, {}, &shader.global_ubo)

    buffer_info := vk.DescriptorBufferInfo{
        buffer = shader.global_ubo_buffer.handle,
        offset = vk.DeviceSize(offset),
        range = vk.DeviceSize(range),
    }

    // Update the descriptor set
    write_descriptor_set := vk.WriteDescriptorSet{
        sType = .WRITE_DESCRIPTOR_SET,
        dstSet = shader.global_descriptor_sets[image_index],
        dstBinding = 0,
        dstArrayElement = 0,
        descriptorType = .UNIFORM_BUFFER,
        descriptorCount = 1,
        pBufferInfo = &buffer_info,
        pImageInfo = nil,
        pTexelBufferView = nil,
    }

    vk.UpdateDescriptorSets(g_context.device.logical_device,
                            1, &write_descriptor_set, 0, nil)

    // Bind the global descriptor set to be updated
    vk.CmdBindDescriptorSets(command_buffer, .GRAPHICS, shader.pipeline.layout,
                             0, 1, &global_descriptor, 0, nil)
}

vk_object_shader_update_object :: proc(window_context: ^Vulkan_Window_Context,
                                       shader: ^Vulkan_Object_Shader,
                                       model: linalg.Matrix4f32) {
    image_index := window_context.image_index
    command_buffer := window_context.graphics_command_buffers[image_index].handle

    loc_model := model
    vk.CmdPushConstants(command_buffer, shader.pipeline.layout,
                        {.VERTEX}, 0, size_of(linalg.Matrix4f32), &loc_model)
}