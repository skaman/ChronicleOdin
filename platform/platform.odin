package platform

Window_Id :: distinct u32
Gamepad_Id :: distinct u32

Instance :: distinct rawptr
Handle :: distinct rawptr

// Structure to hold information needed to initialize a window
Window_Init_Info :: struct {
    title: string,       // The title of the window
    x: Maybe(i32),       // The x-coordinate for the window position (optional)
    y: Maybe(i32),       // The y-coordinate for the window position (optional)
    width: Maybe(i32),   // The width of the window (optional)
    height: Maybe(i32),  // The height of the window (optional)
}

// Structure for the event when a window is created
Window_Created_Event :: struct {
    window_id: Window_Id,   // The identifier for the created window
    handle: Handle,         // The handle for the created window
    instance: Instance,     // The instance for the created window
}

// Structure for the event when a window is destroyed
Window_Destroyed_Event :: struct {
    window_id: Window_Id, // The identifier for the destroyed window
}

// Structure for the event when a window is moved
Window_Moved_Event :: struct {
    window_id: Window_Id, // The identifier for the moved window
    x: i32,               // The new x-coordinate of the window
    y: i32,               // The new y-coordinate of the window
}

// Structure for the event when a window is resized
Window_Resized_Event :: struct {
    window_id: Window_Id, // The identifier for the resized window
    width: i32,           // The new width of the window
    height: i32,          // The new height of the window
    is_fullscreen: bool,  // Whether the window is in fullscreen mode
}

// Structure for the event when a window close is requested
Window_Close_Requested_Event :: struct {
    window_id: Window_Id, // The identifier for the window requested to close
}

// Structure for keyboard events
Key_Event :: struct {
    window_id: Window_Id,        // The identifier for the window receiving the key event
    key: Key,                    // The key involved in the event
    modifier: bit_set[Modifier], // The modifiers (like Ctrl, Alt) active during the event
    pressed: bool,               // Whether the key was pressed (true) or released (false)
}

// Structure for character input events
Char_Event :: struct {
    window_id: Window_Id, // The identifier for the window receiving the character input
    character: rune,      // The character input
}

// Structure for mouse events
Mouse_Event :: struct {
    window_id: Window_Id, // The identifier for the window receiving the mouse event
    x: i32,               // The x-coordinate of the mouse position
    y: i32,               // The y-coordinate of the mouse position
    z: i32,               // The z-coordinate or scroll value of the mouse (optional, usually for scrolling)
    button: Mouse_Button, // The mouse button involved in the event
    pressed: bool,        // Whether the button was pressed (true) or released (false)
    is_moving: bool,      // Whether the mouse is moving (true) or not (false)
}

// Structure for gamepad connection events
Gamepad_Event :: struct {
    gamepad_id: Gamepad_Id, // The identifier for the connected gamepad
    is_connected: bool,     // Whether the gamepad is connected (true) or disconnected (false)
}

// Structure for gamepad axis events
Gamepad_Axis_Event :: struct {
    gamepad_id: Gamepad_Id, // The identifier for the gamepad
    axis: Gamepad_Axis,     // The axis involved in the event
    value: f32,             // The value of the axis
}

// Structure for gamepad button events
Gamepad_Button_Event :: struct {
    gamepad_id: Gamepad_Id, // The identifier for the gamepad
    button: Gamepad_Button, // The button involved in the event
    pressed: bool,          // Whether the button was pressed (true) or released (false)
}

// Union of all possible platform events
Platform_Event :: union {
    Window_Created_Event,          // Event for window creation
    Window_Destroyed_Event,        // Event for window destruction
    Window_Close_Requested_Event,  // Event for window close request
    Window_Moved_Event,            // Event for window move
    Window_Resized_Event,          // Event for window resize
    Key_Event,                     // Event for key actions
    Char_Event,                    // Event for character input
    Mouse_Event,                   // Event for mouse actions
    Gamepad_Event,                 // Event for gamepad connection
    Gamepad_Axis_Event,            // Event for gamepad axis
    Gamepad_Button_Event,          // Event for gamepad button
}

// Enumeration of possible keys
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

// Enumeration of possible key modifiers
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

// Enumeration of possible mouse buttons
Mouse_Button :: enum {
    None,
    Left,
    Middle,
    Right
}

// Enumeration of possible gamepad analogic axis
Gamepad_Axis :: enum {
    Left_Thumb_X,
    Left_Thumb_Y,
    Right_Thumb_X,
    Right_Thumb_Y,
    Left_Trigger,
    Right_Trigger,
}

// Enumeration of possible gamepad buttons
Gamepad_Button :: enum {
    Up,
    Down,
    Left,
    Right,
    Start,
    Back,
    Left_Thumb,
    Right_Thumb,
    Left_Shoulder,
    Right_Shoulder,
    A,
    B,
    X,
    Y,
}