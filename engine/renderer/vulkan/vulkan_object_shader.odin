package renderer_vulkan

import "core:log"

import vk "vendor:vulkan"

import "../../mathx"

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

    // TODO: Descriptors

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
    sizes := [ATTRIBUTE_COUNT]u64{size_of(mathx.Vector3)}

    for i in 0..<ATTRIBUTE_COUNT {
        attribute_descriptions[i].location = i
        attribute_descriptions[i].binding = 0
        attribute_descriptions[i].format = formats[i]
        attribute_descriptions[i].offset = offset
        offset += u32(sizes[i])
    }

    // TODO: Descriptor set layout

    // Stages
    // NOTES: Should match the number of shader->stages
    stage_create_infos: [OBJECT_SHADER_STAGE_COUNT]vk.PipelineShaderStageCreateInfo
    for i in 0..<OBJECT_SHADER_STAGE_COUNT {
        //stage_create_infos[i].sType = out_shader.stages[i].shader_stage_create_info.sType
        stage_create_infos[i] = out_shader.stages[i].shader_stage_create_info
    }
    
    todo_fake_temp_descriptors: [1]vk.DescriptorSetLayout
    if !vk_graphics_pipeline_create(&window_context.main_render_pass,
                                    attribute_descriptions[:],
                                    todo_fake_temp_descriptors[:],
                                    stage_create_infos[:],
                                    viewport,
                                    scissor,
                                    false,
                                    &out_shader.pipeline) {
        log.errorf("Unable to create graphics pipeline for '%s'", BUILTIN_SHADER_NAME_OBJECT)
        return false
    }

    return true
}

// Destroy an object shader.
//
// Parameters:
//   shader: ^Vulkan_Object_Shader - Pointer to the object shader to be destroyed.
vk_object_shader_destroy :: proc(shader: ^Vulkan_Object_Shader) {
    if shader.pipeline.handle != 0 {
        vk_pipeline_destroy(&shader.pipeline)

        for i in 0..<OBJECT_SHADER_STAGE_COUNT {
            vk.DestroyShaderModule(global_context.device.logical_device,
                                   shader.stages[i].handle,
                                   global_context.allocator)
            shader.stages[i].handle = 0
        }
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