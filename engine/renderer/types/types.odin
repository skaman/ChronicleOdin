package renderer_types

// Distinct type for window context identifier
//Window_Context_Id :: distinct u32
Window_Context_Handle :: distinct rawptr

// Enumeration for different renderer backend types
Renderer_Backend_Type :: enum {
    Vulkan,
}

