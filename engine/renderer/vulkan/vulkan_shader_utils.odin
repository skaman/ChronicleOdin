package renderer_vulkan

import "core:log"
import "core:fmt"
import "core:strings"
import "core:os"
import "core:bufio"

import vk "vendor:vulkan"

// Creates a Vulkan shader module.
//
// Parameters:
//   name: string - The name of the shader file.
//   type_str: string - The type of the shader file.
//   shader_stage_flags: vk.ShaderStageFlags - The shader stage flags.
//   stage_index: u32 - The index of the shader stage.
//   shader_stages: []Vulkan_Shader_Stage - The shader stages.
// Returns:
//   b8 - Whether the shader module was created successfully.
@private
vk_create_shader_module :: proc(name: string,
                                type_str: string,
                                shader_stage_flags: vk.ShaderStageFlags,
                                stage_index: u32,
                                shader_stages: []Vulkan_Shader_Stage) -> b8 {
    builder := strings.builder_make(context.temp_allocator)
    file_name := fmt.sbprintf(&builder, "assets/shaders/%s.%s.spv", name, type_str)

    shader_stages[stage_index].create_info = {}
    shader_stages[stage_index].create_info.sType = .SHADER_MODULE_CREATE_INFO

    file_buffer, ok := os.read_entire_file(file_name, context.temp_allocator)
    if !ok {
        log.errorf("Failed to read shader file: %s", file_name)
        return false
    }
    shader_stages[stage_index].create_info.codeSize = len(file_buffer);
    shader_stages[stage_index].create_info.pCode = (^u32)(&file_buffer[0]);

    result := vk.CreateShaderModule(global_context.device.logical_device,
                                    &shader_stages[stage_index].create_info,
                                    global_context.allocator,
                                    &shader_stages[stage_index].handle)
    if result != .SUCCESS {
        log.errorf("Failed to create shader module: %v", result)
        return false
    }

    shader_stages[stage_index].shader_stage_create_info = {}
    shader_stages[stage_index].shader_stage_create_info.sType = .PIPELINE_SHADER_STAGE_CREATE_INFO
    shader_stages[stage_index].shader_stage_create_info.stage = shader_stage_flags
    shader_stages[stage_index].shader_stage_create_info.module = shader_stages[stage_index].handle
    shader_stages[stage_index].shader_stage_create_info.pName = "main"

    return true
}