package renderer_types

import "core:math/linalg"

// Distinct type for window context identifier
Window_Context_Handle :: distinct rawptr

// Enumeration for different renderer backend types
Renderer_Backend_Type :: enum {
    Vulkan,
}

// Global uniform object
Global_Uniform_Object :: struct {
    projection: linalg.Matrix4f32,  // Projection matrix
    view: linalg.Matrix4f32,        // View matrix
    _reserved0: linalg.Matrix4f32,  // Reserved for future use
    _reserved1: linalg.Matrix4f32,  // Reserved for future use
}

Vertex_3D :: struct {
    position: linalg.Vector3f32,
}