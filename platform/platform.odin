package platform

Window_Id :: distinct u32

Window_Init_Info :: struct {
    title: string,
    x: Maybe(i32),
    y: Maybe(i32),
    width: Maybe(i32),
    height: Maybe(i32),
}

Window_Created_Event :: struct {
    window_id: Window_Id,
}

Window_Destroyed_Event :: struct {
    window_id: Window_Id,
}

Window_Move_Event :: struct {
    window_id: Window_Id,
    x: i32,
    y: i32,
}

Window_Resized_Event :: struct {
    window_id: Window_Id,
    width: i32,
    height: i32,
    is_fullscreen: bool,
}

Window_Close_Requested_Event :: struct {
    window_id: Window_Id,
}

Key_Event :: struct {
    window_id: Window_Id,
    key: Key,
    modifier: bit_set[Modifier],
    pressed: bool,
}

Char_Event :: struct {
    window_id: Window_Id,
    character: rune,
}

Mouse_Event :: struct {
    window_id: Window_Id,
    x: i32,
    y: i32,
    z: i32,
    button: Mouse_Button,
    pressed: bool,
    is_moving: bool,
}

Platform_Event :: union {
    Window_Created_Event,
    Window_Destroyed_Event,
    Window_Close_Requested_Event,
    Window_Move_Event,
    Window_Resized_Event,
    Key_Event,
    Char_Event,
    Mouse_Event,
}

Key :: enum {
    None,
    Esc,
    Return,
    Tab,
    Space,
    Backspace,
    Up,
    Down,
    Left,
    Right,
    Insert,
    Delete,
    Home,
    End,
    Page_Up,
    Page_Down,
    Print,
    Plus,
    Minus,
    Left_Bracket,
    Right_Bracket,
    Semicolon,
    Quote,
    Comma,
    Period,
    Slash,
    Backslash,
    Tilde,
    F1,
    F2,
    F3,
    F4,
    F5,
    F6,
    F7,
    F8,
    F9,
    F10,
    F11,
    F12,
    Num_Pad_0,
    Num_Pad_1,
    Num_Pad_2,
    Num_Pad_3,
    Num_Pad_4,
    Num_Pad_5,
    Num_Pad_6,
    Num_Pad_7,
    Num_Pad_8,
    Num_Pad_9,
    Key_0,
    Key_1,
    Key_2,
    Key_3,
    Key_4,
    Key_5,
    Key_6,
    Key_7,
    Key_8,
    Key_9,
    Key_A,
    Key_B,
    Key_C,
    Key_D,
    Key_E,
    Key_F,
    Key_G,
    Key_H,
    Key_I,
    Key_J,
    Key_K,
    Key_L,
    Key_M,
    Key_N,
    Key_O,
    Key_P,
    Key_Q,
    Key_R,
    Key_S,
    Key_T,
    Key_U,
    Key_V,
    Key_W,
    Key_X,
    Key_Y,
    Key_Z
}

Modifier :: enum {
    None,
    Left_Alt,
    Right_Alt,
    Left_Ctrl,
    Right_Ctrl,
    Left_Shift,
    Right_Shift,
    Left_Meta,
    Right_Meta,
}

Mouse_Button :: enum {
    None,
    Left,
    Middle,
    Right
}