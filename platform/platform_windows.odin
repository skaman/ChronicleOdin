package platform

import "core:log"
import "core:thread"
import "core:sync"

import win32 "core:sys/windows"
import xinput "sys_windows"

import "../utils"

// Window_Info is a structure that holds information about a window.
@(private="file")
Window_Info :: struct {
    handle: win32.HWND,        // The handle to the window.
    style: win32.DWORD,        // The style of the window.
    border_rect: win32.RECT,   // The border rectangle of the window.
    x: i32,                    // The x-coordinate of the window.
    y: i32,                    // The y-coordinate of the window.
    width: i32,                // The width of the window.
    height: i32,               // The height of the window.
    is_fullscreen: bool,       // Indicates whether the window is fullscreen.
}

// App_Event_Create_Window is a structure that represents an event to create a window.
@(private="file")
App_Event_Create_Window :: struct {
    window_id: Window_Id,      // The identifier of the window to be created.
    info: Window_Init_Info     // The initialization information for the window.
}

// App_Event_Destroy_Window is a structure that represents an event to destroy a window.
@(private="file")
App_Event_Destroy_Window :: struct {
    window_id: Window_Id       // The identifier of the window to be destroyed.
}

// App_Event_Set_Window_Position is a structure that represents an event to set the position of a window.
@(private="file")
App_Event_Set_Window_Position :: struct {
    window_id: Window_Id,      // The identifier of the window.
    x: i32,                    // The new x-coordinate of the window.
    y: i32                     // The new y-coordinate of the window.
}

// App_Event_Set_Window_Size is a structure that represents an event to set the size of a window.
@(private="file")
App_Event_Set_Window_Size :: struct {
    window_id: Window_Id,      // The identifier of the window.
    width: i32,                // The new width of the window.
    height: i32                // The new height of the window.
}

// App_Event_Set_Window_Title is a structure that represents an event to set the title of a window.
@(private="file")
App_Event_Set_Window_Title :: struct {
    window_id: Window_Id,      // The identifier of the window.
    title: string              // The new title of the window.
}


// App_Event_Set_Window_Fullscreen is a structure that represents an event to set the fullscreen state of a window.
@(private="file")
App_Event_Set_Window_Fullscreen :: struct {
    window_id: Window_Id,      // The identifier of the window.
    fullscreen: bool           // Indicates whether the window should be fullscreen.
}

// App_Event is a union that encapsulates all possible window-related events.
@(private="file")
App_Event :: union {
    App_Event_Create_Window,         // Event to create a window.
    App_Event_Destroy_Window,        // Event to destroy a window.
    App_Event_Set_Window_Position,   // Event to set window position.
    App_Event_Set_Window_Size,       // Event to set window size.
    App_Event_Set_Window_Title,      // Event to set window title.
    App_Event_Set_Window_Fullscreen, // Event to set window fullscreen state.
}

// global_windows is a global variable that holds a free list of Window_Info structures.
@(private="file")
global_windows : utils.Free_List(Window_Info)

// global_windows_lock is a global mutex used to synchronize access to the global_windows variable.
@(private="file")
global_windows_lock : sync.Mutex

// global_app_to_win32_queue is a global single-producer, single-consumer queue for application-to-Win32 events.
@(private="file")
global_app_to_win32_queue : utils.Sp_Sc_Queue(App_Event)

// global_win32_to_app_queue is a global single-producer, single-consumer queue for Win32-to-application events.
@(private="file")
global_win32_to_app_queue : utils.Sp_Sc_Queue(Platform_Event)

// global_window_class is a global variable that may hold the window class information.
@(private="file")
global_window_class : Maybe(win32.WNDCLASSEXW)

// global_key_map is a global map that translates key codes (u8) to Key enumerations.
@(private="file")
global_key_map : map[u8]Key

// global_modifier_map is a global map that translates key codes (u8) to Modifier enumerations.
@(private="file")
global_modifier_map : map[u8]Modifier

// global_surrogate is a global variable used to hold surrogate pairs for UTF-16 character encoding.
@(private="file")
global_surrogate : win32.WCHAR

// Adds a window to the global list of windows.
//
// Parameters:
//   info: Window_Info - The information of the window to add.
//
// Returns:
//   Window_Id - The identifier of the newly added window.
@(private="file")
win32_add_window :: proc(info: Window_Info) -> Window_Id {
    return Window_Id(utils.add_to_free_list(&global_windows, info) + 1)
}

// Removes a window from the global list of windows.
//
// Parameters:
//   window_id: Window_Id - The identifier of the window to remove.
win32_remove_window :: proc(window_id: Window_Id) {
    utils.remove_from_free_list(&global_windows, u32(window_id) - 1)
}

// Retrieves a window from the global list of windows.
//
// Parameters:
//   window_id: Window_Id - The identifier of the window to retrieve.
//
// Returns:
//   ^Window_Info - A pointer to the information of the retrieved window.
@(private="file")
win32_get_window :: proc(window_id: Window_Id) -> ^Window_Info {
    return utils.get_from_free_list(&global_windows, u32(window_id) - 1)
}

// Processes window messages.
//
// Parameters:
//   hWnd: win32.HWND - The handle of the window receiving the message.
//   Msg: win32.UINT - The message code.
//   wParam: win32.WPARAM - Additional message information.
//   lParam: win32.LPARAM - Additional message information.
//
// Returns:
//   win32.LRESULT - The result of the message processing.
@(private="file")
win32_window_proc :: proc(hWnd: win32.HWND, Msg: win32.UINT, wParam: win32.WPARAM, lParam: win32.LPARAM) -> win32.LRESULT {
    window_id := Window_Id(win32.GetWindowLongW(hWnd, win32.GWLP_USERDATA))

    result: win32.LRESULT = 0
    switch Msg {
        case win32.WM_MOVE:
            x := win32.LOWORD(u32(lParam))
            y := win32.HIWORD(u32(lParam))
            {
                sync.mutex_lock(&global_windows_lock)
                defer sync.mutex_unlock(&global_windows_lock)
            
                window_info := win32_get_window(window_id)
                if !window_info.is_fullscreen {
                    window_info.x = i32(x)
                    window_info.y = i32(y)
                }
            }
            utils.push_sp_sc_queue(&global_win32_to_app_queue, Window_Move_Event{window_id, i32(x), i32(y)})
        case win32.WM_SIZE:
            width := win32.LOWORD(u32(lParam))
            height := win32.HIWORD(u32(lParam))
            is_fullscreen : bool
            {
                sync.mutex_lock(&global_windows_lock)
                defer sync.mutex_unlock(&global_windows_lock)
            
                window_info := win32_get_window(window_id)
                if !window_info.is_fullscreen {
                    window_info.width = i32(width)
                    window_info.height = i32(height)
                }

                is_fullscreen = window_info.is_fullscreen
            }
            utils.push_sp_sc_queue(&global_win32_to_app_queue, Window_Resized_Event{window_id, i32(width), i32(height), is_fullscreen})
        case win32.WM_CLOSE, win32.WM_QUIT:
            utils.push_sp_sc_queue(&global_win32_to_app_queue, Window_Close_Requested_Event{window_id})
        case win32.WM_DESTROY:
            utils.push_sp_sc_queue(&global_win32_to_app_queue, Window_Destroyed_Event{window_id})
        case win32.WM_SYSKEYDOWN, win32.WM_KEYDOWN, win32.WM_SYSKEYUP, win32.WM_KEYUP:
            key_event := Key_Event{
                window_id,
                win32_translate_key(u8(wParam)),
                win32_translate_key_modifier(),
                Msg == win32.WM_SYSKEYDOWN || Msg == win32.WM_KEYDOWN,
            }
            utils.push_sp_sc_queue(&global_win32_to_app_queue, key_event)
        case win32.WM_CHAR:
            utf16 := [2]win32.WCHAR {
                win32.WCHAR(wParam),
                0,
            }
            utf8 : [4]u8
            if utf16[0] >= 0xD800 && utf16[0] <= 0xDBFF {
                global_surrogate = utf16[0]
            }
            else {
                utf16_len : i32
                if utf16[0] >= 0xDC00 && utf16[0] <= 0xDFFF {
                    utf16[1] = utf16[0];
                    utf16[0] = global_surrogate;
                    global_surrogate = 0;
                    utf16_len = 2;
                } else {
                    utf16_len = 1;
                }

                len := win32.WideCharToMultiByte(win32.CP_UTF8, 0, &utf16[0], utf16_len, &utf8[0], size_of(utf8), nil, nil)
                if len > 0 {
                    char_event := Char_Event{
                        window_id,
                        rune((^u32)(&utf8[0])^),
                    }
                    utils.push_sp_sc_queue(&global_win32_to_app_queue, char_event)
                }
            }
        case win32.WM_MOUSEMOVE:
            x := win32.LOWORD(u32(lParam))
            y := win32.HIWORD(u32(lParam))
            mouse_event := Mouse_Event{
                window_id,  // window_id
                i32(x),     // x
                i32(y),     // y
                0,          // z
                .None,      // button
                false,      // pressed
                true,       // is_moving
            }
            utils.push_sp_sc_queue(&global_win32_to_app_queue, mouse_event)
        case win32.WM_MOUSEWHEEL:
            x := win32.LOWORD(u32(lParam))
            y := win32.HIWORD(u32(lParam))
            delta := win32.GET_WHEEL_DELTA_WPARAM(wParam) / win32.WHEEL_DELTA
            mouse_event := Mouse_Event{
                window_id,  // window_id
                i32(x),     // x
                i32(y),     // y
                i32(delta), // z
                .None,      // button
                false,      // pressed
                false,      // is_moving
            }
            utils.push_sp_sc_queue(&global_win32_to_app_queue, mouse_event)
        case win32.WM_LBUTTONDOWN, win32.WM_LBUTTONUP, win32.WM_LBUTTONDBLCLK:
            x := win32.LOWORD(u32(lParam))
            y := win32.HIWORD(u32(lParam))
            pressed := Msg == win32.WM_LBUTTONDOWN
            mouse_event := Mouse_Event{
                window_id,  // window_id
                i32(x),     // x
                i32(y),     // y
                0,          // z
                .Left,      // button
                pressed,    // pressed
                false,      // is_moving
            }
            utils.push_sp_sc_queue(&global_win32_to_app_queue, mouse_event)
        case win32.WM_RBUTTONDOWN, win32.WM_RBUTTONUP, win32.WM_RBUTTONDBLCLK:
            x := win32.LOWORD(u32(lParam))
            y := win32.HIWORD(u32(lParam))
            pressed := Msg == win32.WM_RBUTTONDOWN
            mouse_event := Mouse_Event{
                window_id,  // window_id
                i32(x),     // x
                i32(y),     // y
                0,          // z
                .Right,     // button
                pressed,    // pressed
                false,      // is_moving
            }
            utils.push_sp_sc_queue(&global_win32_to_app_queue, mouse_event)
        case win32.WM_MBUTTONDOWN, win32.WM_MBUTTONUP, win32.WM_MBUTTONDBLCLK:
            x := win32.LOWORD(u32(lParam))
            y := win32.HIWORD(u32(lParam))
            pressed := Msg == win32.WM_MBUTTONDOWN
            mouse_event := Mouse_Event{
                window_id,  // window_id
                i32(x),     // x
                i32(y),     // y
                0,          // z
                .Middle,    // button
                pressed,    // pressed
                false,      // is_moving
            }
            utils.push_sp_sc_queue(&global_win32_to_app_queue, mouse_event)
        case:
            result = win32.DefWindowProcW(hWnd, Msg, wParam, lParam)
    }

    return result
}

// Creates a window based on the provided event information.
//
// Parameters:
//   evn: App_Event_Create_Window - The event containing the window creation information.
@(private="file")
win32_create_window :: proc(evn: App_Event_Create_Window) {
    instance := win32.HINSTANCE(win32.GetModuleHandleA(nil))

    if global_window_class == nil {
        global_window_class = win32.WNDCLASSEXW {
            size_of(win32.WNDCLASSEXW),                  // cbSize
            win32.CS_HREDRAW | win32.CS_VREDRAW,         // style
            win32.WNDPROC(win32_window_proc),            // lpfnWndProc
            0,                                           // cbClsExtra
            0,                                           // cbWndExtra
            instance,                                    // hInstance
            win32.LoadIconA(nil, win32.IDI_APPLICATION), // hIcon
            win32.LoadCursorA(nil, win32.IDC_ARROW),     // hCursor
            win32.CreateSolidBrush(0xFF303030),          // hbrBackground
            nil,                                         // lpszMenuName
            win32.L("ChronicleWindowClass"),             // lpszClassName
            win32.LoadIconA(nil, win32.IDI_APPLICATION), // hIconSm
        }

        if win32.RegisterClassExW(&global_window_class.?) == 0 {
            log.error("Failed to register window class")
            return
        }
    }

    info := evn.info
    x := info.x.? or_else win32.CW_USEDEFAULT
    y := info.y.? or_else win32.CW_USEDEFAULT
    width := info.width.? or_else win32.CW_USEDEFAULT
    height := info.height.? or_else win32.CW_USEDEFAULT

    style := win32.WS_OVERLAPPEDWINDOW
    ex_style := win32.WS_EX_APPWINDOW

    // Adjust the window size
    border_rect : win32.RECT
    win32.AdjustWindowRectEx(&border_rect, style, false, ex_style)
    x += border_rect.left
    y += border_rect.top
    width += border_rect.right - border_rect.left
    height += border_rect.bottom - border_rect.top

    title := win32.utf8_to_wstring(len(info.title) == 0 ? "Chronicle" : info.title);
    window_handle := win32.CreateWindowExW(
        ex_style,                                   // dwExStyle
        global_window_class.?.lpszClassName,        // lpClassName
        title,                                      // lpWindowName
        style,                                      // dwStyle
        x,                                          // x
        y,                                          // y
        width,                                      // width
        height,                                     // height
        nil,                                        // hWndParent
        nil,                                        // hMenu
        instance,                                   // hInstance
        rawptr(uintptr(evn.window_id)),             // lpParam
    )

    if window_handle != nil {
        {
            sync.mutex_lock(&global_windows_lock)
            defer sync.mutex_unlock(&global_windows_lock)
        
            window_info := win32_get_window(evn.window_id)
            window_info.handle = window_handle
            window_info.style = style
            window_info.border_rect = border_rect
            window_info.x = x
            window_info.y = y
            window_info.width = width
            window_info.height = height
        }

        win32.SetWindowLongW(window_handle, win32.GWLP_USERDATA, i32(evn.window_id))
        win32.ShowWindow(window_handle, win32.SW_SHOW)

        utils.push_sp_sc_queue(&global_win32_to_app_queue, Window_Created_Event{evn.window_id})
    }
    else {
        log.error("Failed to create window")
    }
}

// Destroys a window based on the provided event information.
//
// Parameters:
//   evn: App_Event_Destroy_Window - The event containing the window destruction information.
@(private="file")
win32_destroy_window :: proc(evn: App_Event_Destroy_Window) {
    handle : win32.HWND
    {
        sync.mutex_lock(&global_windows_lock)
        defer sync.mutex_unlock(&global_windows_lock)

        handle = win32_get_window(evn.window_id).handle
    }
    win32.DestroyWindow(handle)
    win32_remove_window(evn.window_id)
}

// Translates key modifiers.
//
// Returns:
//   bit_set[Modifier] - The set of active key modifiers.
@(private="file")
win32_translate_key_modifier :: proc() -> bit_set[Modifier] {
    result : bit_set[Modifier] = {}
    for key, modifier in global_modifier_map {
        if win32.GetKeyState(i32(key)) < 0 {
            result |= {modifier}
        }
    }
    return result
}

// Translates a key code to a Key enumeration.
//
// Parameters:
//   key: u8 - The key code to translate.
//
// Returns:
//   Key - The translated key.
@(private="file")
win32_translate_key :: proc(key: u8) -> Key {
    return global_key_map[key] or_else .None
}

// Sets the position of a window.
//
// Parameters:
//   evn: App_Event_Set_Window_Position - The event containing the new window position information.
@(private="file")
win32_set_window_position :: proc(evn: App_Event_Set_Window_Position) {
    x, y : i32
    handle : win32.HWND
    {
        sync.mutex_lock(&global_windows_lock)
        defer sync.mutex_unlock(&global_windows_lock)
        
        window_info := win32_get_window(evn.window_id)

        x = evn.x + window_info.border_rect.left
        y = evn.y + window_info.border_rect.top
        handle = window_info.handle
    }

    win32.SetWindowPos(handle, nil, x, y, 0, 0, win32.SWP_NOSIZE | win32.SWP_NOZORDER)
}

// Sets the size of a window.
//
// Parameters:
//   evn: App_Event_Set_Window_Size - The event containing the new window size information.
@(private="file")
win32_set_window_size :: proc(evn: App_Event_Set_Window_Size) {
    width, height : i32
    handle : win32.HWND
    {
        sync.mutex_lock(&global_windows_lock)
        defer sync.mutex_unlock(&global_windows_lock)

        window_info := win32_get_window(evn.window_id)

        width = evn.width + window_info.border_rect.right - window_info.border_rect.left
        height = evn.height + window_info.border_rect.bottom - window_info.border_rect.top
        handle = window_info.handle
    }

    win32.SetWindowPos(handle, nil, 0, 0, width, height, win32.SWP_NOMOVE | win32.SWP_NOZORDER)
}

// Sets the title of a window.
//
// Parameters:
//   evn: App_Event_Set_Window_Title - The event containing the new window title information.
@(private="file")
win32_set_window_title :: proc(evn: App_Event_Set_Window_Title) {
    handle : win32.HWND
    {
        sync.mutex_lock(&global_windows_lock)
        defer sync.mutex_unlock(&global_windows_lock)

        handle = win32_get_window(evn.window_id).handle
    }
    win32.SetWindowTextW(handle, win32.utf8_to_wstring(evn.title))
}

// Sets the fullscreen state of a window.
//
// Parameters:
//   evn: App_Event_Set_Window_Fullscreen - The event containing the new fullscreen state information.
@(private="file")
win32_set_fullscreen :: proc(evn: App_Event_Set_Window_Fullscreen) {
    handle : win32.HWND
    window_style : win32.DWORD
    window_x : i32
    window_y : i32
    window_width : i32
    window_height : i32
    {
        sync.mutex_lock(&global_windows_lock)
        defer sync.mutex_unlock(&global_windows_lock)

        window_info := win32_get_window(evn.window_id)
        handle = window_info.handle
        window_style = window_info.style
        window_x = window_info.x
        window_y = window_info.y
        window_width = window_info.width
        window_height = window_info.height

        window_x += window_info.border_rect.left
        window_y += window_info.border_rect.top
        window_width += window_info.border_rect.right - window_info.border_rect.left
        window_height += window_info.border_rect.bottom - window_info.border_rect.top
    
        window_info.is_fullscreen = evn.fullscreen
    }

    if evn.fullscreen {
        rect : win32.RECT
        win32.GetWindowRect(handle, &rect);
        win32.SetWindowLongW(handle, win32.GWL_STYLE, 0);
        win32.ShowWindow(handle, win32.SW_MAXIMIZE);
    }
    else {
        win32.SetWindowLongW(handle, win32.GWL_STYLE, i32(window_style));
        win32.SetWindowPos(handle, nil, window_x, window_y, window_width, window_height, 0)
        win32.ShowWindow(handle, win32.SW_SHOWNORMAL);
    }
}

// Gamepad_State is a structure that holds the connection status and state of a gamepad.
Gamepad_State :: struct {
    is_connected: bool,                // Indicates whether the gamepad is connected.
    state: xinput.XINPUT_STATE,        // The state of the gamepad.
}

// Gamepad_Axis_State is a structure that holds the configuration for a gamepad axis.
Gamepad_Axis_State :: struct {
    deadzone: i32,                     // The deadzone threshold for the axis.
    flip: i8,                          // The flip factor for the axis (1 or -1).
}

// MAX_GAMEPADS defines the maximum number of supported gamepads.
MAX_GAMEPADS :: 4

// global_gamepads is a global array that holds the state of all connected gamepads.
global_gamepads: [MAX_GAMEPADS]Gamepad_State

// global_gamepad_axis_states is a global array that holds the axis states for each gamepad axis.
global_gamepad_axis_states: [len(Gamepad_Axis)]Gamepad_Axis_State

// global_gamepad_button_map is a global array that maps gamepad buttons to XInput button bits.
global_gamepad_button_map: [len(Gamepad_Button)]xinput.XINPUT_GAMEPAD_BUTTON_BIT

// Filters and updates the value of a gamepad axis based on the deadzone and flip settings.
//
// Parameters:
//   axis: Gamepad_Axis - The axis to filter.
//   old: i32 - The previous value of the axis.
//   value: ^i32 - A pointer to the new value of the axis.
//
// Returns:
//   bool - True if the value has changed, otherwise false.
xinput_filter_axis :: proc(axis: Gamepad_Axis, old: i32, value: ^i32) -> bool {
    axis_state := global_gamepad_axis_states[axis]
    deadzone := axis_state.deadzone
    value^ = value^ > deadzone || value^ < -deadzone ? value^ : 0
    value^ = value^ * i32(axis_state.flip);
    return old != value^;
}

// Polls the state of all gamepads and generates events for any changes.
xinput_poll_gamepads :: proc() {
    for i in 0..<MAX_GAMEPADS {
        gamepad := &global_gamepads[i]
        
        state : xinput.XINPUT_STATE
        result := xinput.XInputGetState(xinput.XUSER(i), &state)
        is_connected := result == win32.System_Error.SUCCESS

        if gamepad.is_connected != is_connected {
            gamepad.is_connected = is_connected
            event := Gamepad_Event{
                Gamepad_Id(i),
                is_connected,
            }
            utils.push_sp_sc_queue(&global_win32_to_app_queue, event)
        }

        if is_connected && gamepad.state.dwPacketNumber != state.dwPacketNumber {
            changed := gamepad.state.Gamepad.wButtons ~ state.Gamepad.wButtons
            current := gamepad.state.Gamepad.wButtons;
            if (gamepad.state.Gamepad.wButtons != state.Gamepad.wButtons)
            {
                for button in Gamepad_Button {
                    bit := global_gamepad_button_map[button]
                    if bit in changed {
                        event := Gamepad_Button_Event{
                            Gamepad_Id(i),
                            button,
                            bit in current,
                        }
                        utils.push_sp_sc_queue(&global_win32_to_app_queue, event)
                    }
                }
            }

            if (gamepad.state.Gamepad.bLeftTrigger != state.Gamepad.bLeftTrigger)
            {
                value := i32(state.Gamepad.bLeftTrigger)
                if xinput_filter_axis(Gamepad_Axis.Left_Trigger, i32(gamepad.state.Gamepad.bLeftTrigger), &value) {
                    event := Gamepad_Axis_Event{
                        Gamepad_Id(i),
                        Gamepad_Axis.Left_Trigger,
                        f32(value) / 255,
                    }
                    utils.push_sp_sc_queue(&global_win32_to_app_queue, event)
                }

                gamepad.state.Gamepad.bLeftTrigger = state.Gamepad.bLeftTrigger
            }

            if (gamepad.state.Gamepad.bRightTrigger != state.Gamepad.bRightTrigger)
            {
                value := i32(state.Gamepad.bRightTrigger)
                if xinput_filter_axis(Gamepad_Axis.Right_Trigger, i32(gamepad.state.Gamepad.bRightTrigger), &value) {
                    event := Gamepad_Axis_Event{
                        Gamepad_Id(i),
                        Gamepad_Axis.Right_Trigger,
                        f32(value) / 255,
                    }
                    utils.push_sp_sc_queue(&global_win32_to_app_queue, event)
                }

                gamepad.state.Gamepad.bRightTrigger = state.Gamepad.bRightTrigger
            }

            if (gamepad.state.Gamepad.sThumbLX != state.Gamepad.sThumbLX)
            {
                value := i32(state.Gamepad.sThumbLX)
                if xinput_filter_axis(Gamepad_Axis.Left_Thumb_X, i32(gamepad.state.Gamepad.sThumbLX), &value) {
                    event := Gamepad_Axis_Event{
                        Gamepad_Id(i),
                        Gamepad_Axis.Left_Thumb_X,
                        f32(value) / 32767,
                    }
                    utils.push_sp_sc_queue(&global_win32_to_app_queue, event)
                }

                gamepad.state.Gamepad.sThumbLX = state.Gamepad.sThumbLX
            }

            if (gamepad.state.Gamepad.sThumbLY != state.Gamepad.sThumbLY)
            {
                value := i32(state.Gamepad.sThumbLY)
                if xinput_filter_axis(Gamepad_Axis.Left_Thumb_Y, i32(gamepad.state.Gamepad.sThumbLY), &value) {
                    event := Gamepad_Axis_Event{
                        Gamepad_Id(i),
                        Gamepad_Axis.Left_Thumb_Y,
                        f32(value) / 32767,
                    }
                    utils.push_sp_sc_queue(&global_win32_to_app_queue, event)
                }

                gamepad.state.Gamepad.sThumbLY = state.Gamepad.sThumbLY
            }

            if (gamepad.state.Gamepad.sThumbRX != state.Gamepad.sThumbRX)
            {
                value := i32(state.Gamepad.sThumbRX)
                if xinput_filter_axis(Gamepad_Axis.Right_Thumb_X, i32(gamepad.state.Gamepad.sThumbRX), &value) {
                    event := Gamepad_Axis_Event{
                        Gamepad_Id(i),
                        Gamepad_Axis.Right_Thumb_X,
                        f32(value) / 32767,
                    }
                    utils.push_sp_sc_queue(&global_win32_to_app_queue, event)
                }

                gamepad.state.Gamepad.sThumbRX = state.Gamepad.sThumbRX
            }

            if (gamepad.state.Gamepad.sThumbRY != state.Gamepad.sThumbRY)
            {
                value := i32(state.Gamepad.sThumbRY)
                if xinput_filter_axis(Gamepad_Axis.Right_Thumb_Y, i32(gamepad.state.Gamepad.sThumbRY), &value) {
                    event := Gamepad_Axis_Event{
                        Gamepad_Id(i),
                        Gamepad_Axis.Right_Thumb_Y,
                        f32(value) / 32767,
                    }
                    utils.push_sp_sc_queue(&global_win32_to_app_queue, event)
                }

                gamepad.state.Gamepad.sThumbRY = state.Gamepad.sThumbRY
            }
        }
    }
}

// Initializes the platform module.
init :: proc() {
    utils.init_free_list(&global_windows, 10)
    utils.init_sp_sc_queue(&global_app_to_win32_queue)
    utils.init_sp_sc_queue(&global_win32_to_app_queue)

    // Initialize the global key map
    global_key_map = make(map[u8]Key)
    global_key_map[win32.VK_ESCAPE]     = .Esc
    global_key_map[win32.VK_RETURN]     = .Return;
    global_key_map[win32.VK_TAB]        = .Tab;
    global_key_map[win32.VK_BACK]       = .Backspace;
    global_key_map[win32.VK_SPACE]      = .Space;
    global_key_map[win32.VK_UP]         = .Up;
    global_key_map[win32.VK_DOWN]       = .Down;
    global_key_map[win32.VK_LEFT]       = .Left;
    global_key_map[win32.VK_RIGHT]      = .Right;
    global_key_map[win32.VK_INSERT]     = .Insert;
    global_key_map[win32.VK_DELETE]     = .Delete;
    global_key_map[win32.VK_HOME]       = .Home;
    global_key_map[win32.VK_END]        = .End;
    global_key_map[win32.VK_PRIOR]      = .Page_Up;
    global_key_map[win32.VK_NEXT]       = .Page_Down;
    global_key_map[win32.VK_SNAPSHOT]   = .Print;
    global_key_map[win32.VK_OEM_PLUS]   = .Plus;
    global_key_map[win32.VK_OEM_MINUS]  = .Minus;
    global_key_map[win32.VK_OEM_4]      = .Left_Bracket;
    global_key_map[win32.VK_OEM_6]      = .Right_Bracket;
    global_key_map[win32.VK_OEM_1]      = .Semicolon;
    global_key_map[win32.VK_OEM_7]      = .Quote;
    global_key_map[win32.VK_OEM_COMMA]  = .Comma;
    global_key_map[win32.VK_OEM_PERIOD] = .Period;
    global_key_map[win32.VK_DECIMAL]    = .Period;
    global_key_map[win32.VK_OEM_2]      = .Slash;
    global_key_map[win32.VK_OEM_5]      = .Backslash;
    global_key_map[win32.VK_OEM_3]      = .Tilde;
    global_key_map[win32.VK_F1]         = .F1;
    global_key_map[win32.VK_F2]         = .F2;
    global_key_map[win32.VK_F3]         = .F3;
    global_key_map[win32.VK_F4]         = .F4;
    global_key_map[win32.VK_F5]         = .F5;
    global_key_map[win32.VK_F6]         = .F6;
    global_key_map[win32.VK_F7]         = .F7;
    global_key_map[win32.VK_F8]         = .F8;
    global_key_map[win32.VK_F9]         = .F9;
    global_key_map[win32.VK_F10]        = .F10;
    global_key_map[win32.VK_F11]        = .F11;
    global_key_map[win32.VK_F12]        = .F12;
    global_key_map[win32.VK_NUMPAD0]    = .Num_Pad_0;
    global_key_map[win32.VK_NUMPAD1]    = .Num_Pad_1;
    global_key_map[win32.VK_NUMPAD2]    = .Num_Pad_2;
    global_key_map[win32.VK_NUMPAD3]    = .Num_Pad_3;
    global_key_map[win32.VK_NUMPAD4]    = .Num_Pad_4;
    global_key_map[win32.VK_NUMPAD5]    = .Num_Pad_5;
    global_key_map[win32.VK_NUMPAD6]    = .Num_Pad_6;
    global_key_map[win32.VK_NUMPAD7]    = .Num_Pad_7;
    global_key_map[win32.VK_NUMPAD8]    = .Num_Pad_8;
    global_key_map[win32.VK_NUMPAD9]    = .Num_Pad_9;
    global_key_map[u8('0')]             = .Key_0;
    global_key_map[u8('1')]             = .Key_1;
    global_key_map[u8('2')]             = .Key_2;
    global_key_map[u8('3')]             = .Key_3;
    global_key_map[u8('4')]             = .Key_4;
    global_key_map[u8('5')]             = .Key_5;
    global_key_map[u8('6')]             = .Key_6;
    global_key_map[u8('7')]             = .Key_7;
    global_key_map[u8('8')]             = .Key_8;
    global_key_map[u8('9')]             = .Key_9;
    global_key_map[u8('A')]             = .Key_A;
    global_key_map[u8('B')]             = .Key_B;
    global_key_map[u8('C')]             = .Key_C;
    global_key_map[u8('D')]             = .Key_D;
    global_key_map[u8('E')]             = .Key_E;
    global_key_map[u8('F')]             = .Key_F;
    global_key_map[u8('G')]             = .Key_G;
    global_key_map[u8('H')]             = .Key_H;
    global_key_map[u8('I')]             = .Key_I;
    global_key_map[u8('J')]             = .Key_J;
    global_key_map[u8('K')]             = .Key_K;
    global_key_map[u8('L')]             = .Key_L;
    global_key_map[u8('M')]             = .Key_M;
    global_key_map[u8('N')]             = .Key_N;
    global_key_map[u8('O')]             = .Key_O;
    global_key_map[u8('P')]             = .Key_P;
    global_key_map[u8('Q')]             = .Key_Q;
    global_key_map[u8('R')]             = .Key_R;
    global_key_map[u8('S')]             = .Key_S;
    global_key_map[u8('T')]             = .Key_T;
    global_key_map[u8('U')]             = .Key_U;
    global_key_map[u8('V')]             = .Key_V;
    global_key_map[u8('W')]             = .Key_W;
    global_key_map[u8('X')]             = .Key_X;
    global_key_map[u8('Y')]             = .Key_Y;
    global_key_map[u8('Z')]             = .Key_Z;

    // Initialize the global modifier map
    global_modifier_map = make(map[u8]Modifier)
    global_modifier_map[win32.VK_LMENU]    = .Left_Alt
    global_modifier_map[win32.VK_RMENU]    = .Right_Alt
    global_modifier_map[win32.VK_LCONTROL] = .Left_Ctrl
    global_modifier_map[win32.VK_RCONTROL] = .Right_Ctrl
    global_modifier_map[win32.VK_LSHIFT]   = .Left_Shift
    global_modifier_map[win32.VK_RSHIFT]   = .Right_Shift
    global_modifier_map[win32.VK_LWIN]     = .Left_Meta
    global_modifier_map[win32.VK_RWIN]     = .Right_Meta

    // Initialize the global gamepad axis states
    global_gamepad_axis_states[Gamepad_Axis.Left_Thumb_X].deadzone  = i32(xinput.XINPUT_GAMEPAD_LEFT_THUMB_DEADZONE)
    global_gamepad_axis_states[Gamepad_Axis.Left_Thumb_X].flip      = 1
    global_gamepad_axis_states[Gamepad_Axis.Left_Thumb_Y].deadzone  = i32(xinput.XINPUT_GAMEPAD_LEFT_THUMB_DEADZONE)
    global_gamepad_axis_states[Gamepad_Axis.Left_Thumb_Y].flip      = -1
    global_gamepad_axis_states[Gamepad_Axis.Right_Thumb_X].deadzone = i32(xinput.XINPUT_GAMEPAD_RIGHT_THUMB_DEADZONE)
    global_gamepad_axis_states[Gamepad_Axis.Right_Thumb_X].flip     = 1
    global_gamepad_axis_states[Gamepad_Axis.Right_Thumb_Y].deadzone = i32(xinput.XINPUT_GAMEPAD_RIGHT_THUMB_DEADZONE)
    global_gamepad_axis_states[Gamepad_Axis.Right_Thumb_Y].flip     = -1
    global_gamepad_axis_states[Gamepad_Axis.Left_Trigger].deadzone  = i32(xinput.XINPUT_GAMEPAD_TRIGGER_THRESHOLD)
    global_gamepad_axis_states[Gamepad_Axis.Left_Trigger].flip      = 1
    global_gamepad_axis_states[Gamepad_Axis.Right_Trigger].deadzone = i32(xinput.XINPUT_GAMEPAD_TRIGGER_THRESHOLD)
    global_gamepad_axis_states[Gamepad_Axis.Right_Trigger].flip     = 1

    // Initialize the global gamepad button map
    global_gamepad_button_map[Gamepad_Button.Up]             = xinput.XINPUT_GAMEPAD_BUTTON_BIT.DPAD_UP
    global_gamepad_button_map[Gamepad_Button.Down]           = xinput.XINPUT_GAMEPAD_BUTTON_BIT.DPAD_DOWN
    global_gamepad_button_map[Gamepad_Button.Left]           = xinput.XINPUT_GAMEPAD_BUTTON_BIT.DPAD_LEFT
    global_gamepad_button_map[Gamepad_Button.Right]          = xinput.XINPUT_GAMEPAD_BUTTON_BIT.DPAD_RIGHT
    global_gamepad_button_map[Gamepad_Button.Start]          = xinput.XINPUT_GAMEPAD_BUTTON_BIT.START
    global_gamepad_button_map[Gamepad_Button.Back]           = xinput.XINPUT_GAMEPAD_BUTTON_BIT.BACK
    global_gamepad_button_map[Gamepad_Button.Left_Thumb]     = xinput.XINPUT_GAMEPAD_BUTTON_BIT.LEFT_THUMB
    global_gamepad_button_map[Gamepad_Button.Right_Thumb]    = xinput.XINPUT_GAMEPAD_BUTTON_BIT.RIGHT_THUMB
    global_gamepad_button_map[Gamepad_Button.Left_Shoulder]  = xinput.XINPUT_GAMEPAD_BUTTON_BIT.LEFT_SHOULDER
    global_gamepad_button_map[Gamepad_Button.Right_Shoulder] = xinput.XINPUT_GAMEPAD_BUTTON_BIT.RIGHT_SHOULDER
    global_gamepad_button_map[Gamepad_Button.A]              = xinput.XINPUT_GAMEPAD_BUTTON_BIT.A
    global_gamepad_button_map[Gamepad_Button.B]              = xinput.XINPUT_GAMEPAD_BUTTON_BIT.B
    global_gamepad_button_map[Gamepad_Button.X]              = xinput.XINPUT_GAMEPAD_BUTTON_BIT.X
    global_gamepad_button_map[Gamepad_Button.Y]              = xinput.XINPUT_GAMEPAD_BUTTON_BIT.Y
}

// Destroys the platform module.
destroy :: proc() {
    delete(global_modifier_map)
    delete(global_key_map)

    utils.destroy_sp_sc_queue(&global_win32_to_app_queue)
    utils.destroy_sp_sc_queue(&global_app_to_win32_queue)
    utils.destroy_free_list(&global_windows)
}

// Creates a window.
//
// Parameters:
//   info: Window_Init_Info - The initialization information for the window.
//
// Returns:
//   Window_Id - The identifier of the newly created window.
create_window :: proc(info: Window_Init_Info) -> Window_Id {
    window_id : Window_Id
    {
        sync.mutex_lock(&global_windows_lock)
        defer sync.mutex_unlock(&global_windows_lock)

        window_id = win32_add_window(Window_Info{})
    }

    utils.push_sp_sc_queue(&global_app_to_win32_queue, App_Event_Create_Window{window_id, info})
    return window_id
}

// Destroys a window.
//
// Parameters:
//   window_id: Window_Id - The identifier of the window to destroy.
destroy_window :: proc(window_id: Window_Id) {
    utils.push_sp_sc_queue(&global_app_to_win32_queue, App_Event_Destroy_Window{window_id})
}

// Sets the position of a window.
//
// Parameters:
//   window_id: Window_Id - The identifier of the window to move.
//   x: i32 - The new x-coordinate of the window.
//   y: i32 - The new y-coordinate of the window.
set_window_position :: proc(window_id: Window_Id, x: i32, y: i32) {
    utils.push_sp_sc_queue(&global_app_to_win32_queue, App_Event_Set_Window_Position{window_id, x, y})
}

// Sets the size of a window.
//
// Parameters:
//   window_id: Window_Id - The identifier of the window to resize.
//   width: i32 - The new width of the window.
//   height: i32 - The new height of the window.
set_window_size :: proc(window_id: Window_Id, width: i32, height: i32) {
    utils.push_sp_sc_queue(&global_app_to_win32_queue, App_Event_Set_Window_Size{window_id, width, height})
}

// Sets the title of a window.
//
// Parameters:
//   window_id: Window_Id - The identifier of the window to rename.
//   title: string - The new title of the window.
set_window_title :: proc(window_id: Window_Id, title: string) {
    utils.push_sp_sc_queue(&global_app_to_win32_queue, App_Event_Set_Window_Title{window_id, title})
}

// Sets the fullscreen state of a window.
//
// Parameters:
//   window_id: Window_Id - The identifier of the window to modify.
//   fullscreen: bool - Indicates whether the window should be fullscreen.
set_window_fullscreen :: proc(window_id: Window_Id, fullscreen: bool) {
    utils.push_sp_sc_queue(&global_app_to_win32_queue, App_Event_Set_Window_Fullscreen{window_id, fullscreen})
}

// Polls for platform events.
//
// Returns:
//   (Platform_Event, bool) - A tuple containing the event and a boolean indicating success.
poll :: proc() -> (Platform_Event, bool) {
    return utils.peek_sp_sc_queue(&global_win32_to_app_queue)
}

// Runs the main event loop.
//
// Parameters:
//   worker: proc(t: ^thread.Thread) - The worker procedure to run in the thread.
run :: proc(worker: proc(t: ^thread.Thread)) {
    t := thread.create(worker)
    if t == nil {
        log.error("Failed to create thread")
        return
    }

    t.init_context = context
    thread.start(t)

    for !thread.is_done(t) {
        for event in utils.peek_sp_sc_queue(&global_app_to_win32_queue) {
            switch _ in event {
                case App_Event_Create_Window:
                    win32_create_window(event.(App_Event_Create_Window))
                case App_Event_Destroy_Window:
                    win32_destroy_window(event.(App_Event_Destroy_Window))
                case App_Event_Set_Window_Position:
                    win32_set_window_position(event.(App_Event_Set_Window_Position))
                case App_Event_Set_Window_Size:
                    win32_set_window_size(event.(App_Event_Set_Window_Size))
                case App_Event_Set_Window_Title:
                    win32_set_window_title(event.(App_Event_Set_Window_Title))
                case App_Event_Set_Window_Fullscreen:
                    win32_set_fullscreen(event.(App_Event_Set_Window_Fullscreen))
            }
        }

        message: win32.MSG
        for win32.PeekMessageW(&message, nil, 0, 0, win32.PM_REMOVE) {
            win32.TranslateMessage(&message)
            win32.DispatchMessageW(&message)
        }

        xinput_poll_gamepads()

        thread.yield()
    }

    thread.destroy(t)
}