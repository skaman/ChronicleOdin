package platform

Window_Id :: distinct u32

Window_Init_Info :: struct {
    title: string,
    x: Maybe(i32),
    y: Maybe(i32),
    width: Maybe(i32),
    height: Maybe(i32),
    parent_handle: rawptr,
}

Window_Created :: struct {
    window_id: Window_Id,
}

Window_Destroyed :: struct {
    window_id: Window_Id,
}

Window_Close_Requested :: struct {
    window_id: Window_Id,
}

Platform_Event :: union {
    Window_Created,
    Window_Destroyed,
    Window_Close_Requested,
}