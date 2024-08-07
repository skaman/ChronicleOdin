package renderer_vulkan

import "core:log"
import "core:math/linalg"

import vk "vendor:vulkan"

import rt "../types"

// Create a Vulkan graphics pipeline.
//
// Parameters:
//   renderpass: Vulkan render pass.
//   attributes: Vertex input attributes.
//   descriptor_set_layouts: Descriptor set layouts.
//   stages: Shader stages.
//   viewport: Viewport.
//   scissor: Scissor.
//   is_wireframe: Indicates if the pipeline is wireframe.
//   out_pipeline: Vulkan pipeline.
//
// Returns:
//   True if the pipeline was created successfully, false otherwise.
@private
vk_graphics_pipeline_create :: proc(renderpass: ^Vulkan_Render_Pass,
                                    attributes: []vk.VertexInputAttributeDescription,
                                    descriptor_set_layouts: []vk.DescriptorSetLayout,
                                    stages: []vk.PipelineShaderStageCreateInfo,
                                    viewport: vk.Viewport,
                                    scissor: vk.Rect2D,
                                    is_wireframe: b8,
                                    out_pipeline: ^Vulkan_Pipeline) -> b8 {
    // Viewport state
    local_viewport := viewport
    local_scissor := scissor
    viewport_state := vk.PipelineViewportStateCreateInfo{
        sType = .PIPELINE_VIEWPORT_STATE_CREATE_INFO,
        viewportCount = 1,
        pViewports = &local_viewport,
        scissorCount = 1,
        pScissors = &local_scissor,
    }

    // Rasterization state
    rasterization_state := vk.PipelineRasterizationStateCreateInfo{
        sType = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
        depthClampEnable = false,
        rasterizerDiscardEnable = false,
        polygonMode = is_wireframe ? .LINE : .FILL,
        lineWidth = 1.0,
        cullMode = {.BACK},
        frontFace = .COUNTER_CLOCKWISE,
        depthBiasEnable = false,
        depthBiasConstantFactor = 0.0,
        depthBiasClamp = 0.0,
        depthBiasSlopeFactor = 0.0,
    }

    // Multisample state
    multisample_state := vk.PipelineMultisampleStateCreateInfo{
        sType = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
        sampleShadingEnable = false,
        rasterizationSamples = {._1},
        minSampleShading = 1.0,
        pSampleMask = nil,
        alphaToCoverageEnable = false,
        alphaToOneEnable = false,
    }

    // Depth and stencil state
    depth_stencil_state := vk.PipelineDepthStencilStateCreateInfo{
        sType = .PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
        depthTestEnable = true,
        depthWriteEnable = true,
        depthCompareOp = .LESS,
        depthBoundsTestEnable = false,
        stencilTestEnable = false,
    }

    // Color blend attachment state
    color_blend_attachment_state := vk.PipelineColorBlendAttachmentState{
        blendEnable = true,
        srcColorBlendFactor = .SRC_ALPHA,
        dstColorBlendFactor = .ONE_MINUS_SRC_ALPHA,
        colorBlendOp = .ADD,
        srcAlphaBlendFactor = .SRC_ALPHA,
        dstAlphaBlendFactor = .ONE_MINUS_SRC_ALPHA,
        alphaBlendOp = .ADD,
        colorWriteMask = {.R, .G, .B, .A},
    }

    // Color blend state
    color_blend_state := vk.PipelineColorBlendStateCreateInfo{
        sType = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
        logicOpEnable = false,
        logicOp = .COPY,
        attachmentCount = 1,
        pAttachments = &color_blend_attachment_state,
    }

    // Dynamic state
    DYNAMIC_STATE_COUNT :: 3
    dynamic_states := [DYNAMIC_STATE_COUNT]vk.DynamicState{
        vk.DynamicState.VIEWPORT,
        vk.DynamicState.SCISSOR,
        vk.DynamicState.LINE_WIDTH,
    }

    dynamic_state := vk.PipelineDynamicStateCreateInfo{
        sType = .PIPELINE_DYNAMIC_STATE_CREATE_INFO,
        dynamicStateCount = DYNAMIC_STATE_COUNT,
        pDynamicStates = &dynamic_states[0],
    }

    // Vertex input
    vertex_input_state := vk.VertexInputBindingDescription{
        binding = 0,
        stride = size_of(rt.Vertex_3D),
        inputRate = .VERTEX,
    }

    // Attributes
    vertex_input_info := vk.PipelineVertexInputStateCreateInfo{
        sType = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
        vertexBindingDescriptionCount = 1,
        pVertexBindingDescriptions = &vertex_input_state,
        vertexAttributeDescriptionCount = u32(len(attributes)),
        pVertexAttributeDescriptions = &attributes[0],
    }

    // Input assembly
    input_assembly_state := vk.PipelineInputAssemblyStateCreateInfo{
        sType = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
        topology = .TRIANGLE_LIST,
        primitiveRestartEnable = false,
    }

    // Push constants
    push_constant := vk.PushConstantRange{
        stageFlags = {.VERTEX},
        offset = size_of(linalg.Matrix4f32) * 0,
        size = size_of(linalg.Matrix4f32) * 2,
    }

    // Pipeline layout
    pipeline_layout_create_info := vk.PipelineLayoutCreateInfo{
        sType = .PIPELINE_LAYOUT_CREATE_INFO,
        setLayoutCount = u32(len(descriptor_set_layouts)),
        pSetLayouts = &descriptor_set_layouts[0],
        pushConstantRangeCount = 1,
        pPushConstantRanges = &push_constant,
    }

    // Create the pipeline layout
    result := vk.CreatePipelineLayout(g_context.device.logical_device,
                                      &pipeline_layout_create_info,
                                      g_context.allocator,
                                      &out_pipeline.layout)
    if result != .SUCCESS {
        log.error("Failed to create pipeline layout")
        return false
    }

    // Pipeline create
    pipeline_create_info := vk.GraphicsPipelineCreateInfo{
        sType = .GRAPHICS_PIPELINE_CREATE_INFO,
        stageCount = u32(len(stages)),
        pStages = &stages[0],
        pVertexInputState = &vertex_input_info,
        pInputAssemblyState = &input_assembly_state,
        pTessellationState = nil,
        pViewportState = &viewport_state,
        pRasterizationState = &rasterization_state,
        pMultisampleState = &multisample_state,
        pDepthStencilState = &depth_stencil_state,
        pColorBlendState = &color_blend_state,
        pDynamicState = &dynamic_state,
        layout = out_pipeline.layout,
        renderPass = renderpass.handle,
        subpass = 0,
        basePipelineHandle = 0,
        basePipelineIndex = -1,
    }

    result = vk.CreateGraphicsPipelines(g_context.device.logical_device,
                                        0,
                                        1,
                                        &pipeline_create_info,
                                        g_context.allocator,
                                        &out_pipeline.handle)
    if result != .SUCCESS {
        log.error("Failed to create graphics pipeline")
        return false
    }

    return true
}

// Destroy a Vulkan pipeline.
//
// Parameters:
//   pipeline: Vulkan pipeline.
@private
vk_pipeline_destroy :: proc(pipeline: ^Vulkan_Pipeline) {
    if pipeline.handle != 0 {
        vk.DestroyPipeline(g_context.device.logical_device,
                           pipeline.handle,
                           g_context.allocator)
        pipeline.handle = 0
    }

    if pipeline.layout != 0 {
        vk.DestroyPipelineLayout(g_context.device.logical_device,
                                 pipeline.layout,
                                 g_context.allocator)
        pipeline.layout = 0
    }
}

// Bind a Vulkan pipeline.
//
// Parameters:
//   command_buffer: Vulkan command buffer.
//   bind_point: Pipeline bind point.
//   pipeline: Vulkan pipeline.
@private
vk_pipeline_bind :: proc(command_buffer: ^Vulkan_Command_Buffer,
                         bind_point: vk.PipelineBindPoint,
                         pipeline: ^Vulkan_Pipeline) {
    vk.CmdBindPipeline(command_buffer.handle, bind_point, pipeline.handle)
}