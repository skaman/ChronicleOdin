package platform

import "core:log"
import "core:thread"
import "core:sync"
import "core:strings"
import "core:time"
import "core:os"
import "core:mem"

import vmem "core:mem/virtual"
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

    event_queue: utils.Sp_Sc_Queue(Window_Event) // The event queue for the window.
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

// App_Event_Set_Window_Position is a structure that represents an event to set the position of a
// window.
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


// App_Event_Set_Window_Fullscreen is a structure that represents an event to set the fullscreen
// state of a window.
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

@(private="file")
g_instance: win32.HINSTANCE

// g_windows is a global variable that holds a free list of Window_Info structures.
@(private="file")
g_windows: map[Window_Id]^Window_Info

// g_app_to_win32_queue is a global single-producer, single-consumer queue for
// application-to-Win32 events.
@(private="file")
g_app_to_win32_queue: utils.Sp_Sc_Queue(App_Event)

// g_gamepad_queue is a global single-producer, single-consumer queue for gamepad events.
@(private="file")
g_gamepad_queue: utils.Sp_Sc_Queue(Gamepad_Event)

// g_window_class is a global variable that may hold the window class information.
@(private="file")
g_window_class: Maybe(win32.WNDCLASSEXW)

// g_key_map is a global map that translates key codes (u8) to Key enumerations.
@(private="file")
g_key_map: map[u8]Key

// g_modifier_map is a global map that translates key codes (u8) to Modifier enumerations.
@(private="file")
g_modifier_map: map[u8]Modifier

// g_surrogate is a global variable used to hold surrogate pairs for UTF-16 character encoding.
@(private="file")
g_surrogate: win32.WCHAR

// g_window_id_counter is a global counter used to generate unique window identifiers.
g_window_id_counter: Window_Id = 0

// g_main_thread is a global variable that holds the main thread.
g_main_thread: ^thread.Thread

// Adds a window to the global list of windows.
//
// Returns:
//   Window_Id - The identifier of the newly added window.
@(private="file")
win32_add_window :: proc() -> Window_Id {
    window_id := g_window_id_counter
    g_window_id_counter += 1

    window_info, _ := mem.new(Window_Info)
    utils.init_sp_sc_queue(&window_info.event_queue)
    g_windows[window_id] = window_info

    return window_id
}

// Removes a window from the global list of windows.
//
// Parameters:
//   window_id: Window_Id - The identifier of the window to remove.
win32_remove_window :: proc(window_id: Window_Id) {
    window_info := g_windows[window_id]
    utils.destroy_sp_sc_queue(&window_info.event_queue)
    mem.free(window_info)

    delete_key(&g_windows, window_id)
}

// Processes window messages.
//
// We always assume that the window handle is valid and that the window is in the global list of
// windows. Windows are created and destroyed on the main worker thread and not in win32 main
// thread, but they are always created/destroyed before/after this function is called.
//
// As opposite window content is always processed in the win32 main thread, so we don't need
// additional synchronization for window content. 
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
win32_window_proc :: proc(hWnd: win32.HWND,
                          Msg: win32.UINT,
                          wParam: win32.WPARAM,
                          lParam: win32.LPARAM) -> win32.LRESULT {
    window_id := Window_Id(win32.GetWindowLongW(hWnd, win32.GWLP_USERDATA))
    window_info := g_windows[window_id]

    result: win32.LRESULT = 0
    switch Msg {
        case win32.WM_MOVE:
            x := win32.LOWORD(u32(lParam))
            y := win32.HIWORD(u32(lParam))

            if !window_info.is_fullscreen {
                window_info.x = i32(x)
                window_info.y = i32(y)
            }

            event := Window_Moved_Event{window_id, i32(x), i32(y)}
            utils.push_sp_sc_queue(&window_info.event_queue, event)

        case win32.WM_SIZE:
            width := win32.LOWORD(u32(lParam))
            height := win32.HIWORD(u32(lParam))

            if !window_info.is_fullscreen {
                window_info.width = i32(width)
                window_info.height = i32(height)
            }

            event := Window_Resized_Event{
                window_id,
                i32(width),
                i32(height),
                window_info.is_fullscreen
            }
            utils.push_sp_sc_queue(&window_info.event_queue, event)

        case win32.WM_CLOSE, win32.WM_QUIT:
            event := Window_Close_Requested_Event{window_id}
            utils.push_sp_sc_queue(&window_info.event_queue, event)

        case win32.WM_DESTROY:
            event := Window_Destroyed_Event{window_id}
            utils.push_sp_sc_queue(&window_info.event_queue, event)

        case win32.WM_SYSKEYDOWN, win32.WM_KEYDOWN, win32.WM_SYSKEYUP, win32.WM_KEYUP:
            event := Key_Event{
                window_id,
                win32_translate_key(u8(wParam)),
                win32_translate_key_modifier(),
                Msg == win32.WM_SYSKEYDOWN || Msg == win32.WM_KEYDOWN,
            }
            utils.push_sp_sc_queue(&window_info.event_queue, event)

        case win32.WM_CHAR:
            utf16 := [2]win32.WCHAR {
                win32.WCHAR(wParam),
                0,
            }
            utf8 : [4]u8
            if utf16[0] >= 0xD800 && utf16[0] <= 0xDBFF {
                g_surrogate = utf16[0]
            }
            else {
                utf16_len : i32
                if utf16[0] >= 0xDC00 && utf16[0] <= 0xDFFF {
                    utf16[1] = utf16[0];
                    utf16[0] = g_surrogate;
                    g_surrogate = 0;
                    utf16_len = 2;
                } else {
                    utf16_len = 1;
                }

                len := win32.WideCharToMultiByte(win32.CP_UTF8, 0, &utf16[0], utf16_len,
                                                 &utf8[0], size_of(utf8), nil, nil)
                if len > 0 {
                    event := Char_Event{
                        window_id,
                        rune((^u32)(&utf8[0])^),
                    }
                    utils.push_sp_sc_queue(&window_info.event_queue, event)
                }
            }

        case win32.WM_MOUSEMOVE:
            x := win32.LOWORD(u32(lParam))
            y := win32.HIWORD(u32(lParam))
            event := Mouse_Event{
                window_id,  // window_id
                i32(x),     // x
                i32(y),     // y
                0,          // z
                .None,      // button
                false,      // pressed
                true,       // is_moving
            }
            utils.push_sp_sc_queue(&window_info.event_queue, event)

        case win32.WM_MOUSEWHEEL:
            x := win32.LOWORD(u32(lParam))
            y := win32.HIWORD(u32(lParam))
            delta := win32.GET_WHEEL_DELTA_WPARAM(wParam) / win32.WHEEL_DELTA
            event := Mouse_Event{
                window_id,  // window_id
                i32(x),     // x
                i32(y),     // y
                i32(delta), // z
                .None,      // button
                false,      // pressed
                false,      // is_moving
            }
            utils.push_sp_sc_queue(&window_info.event_queue, event)

        case win32.WM_LBUTTONDOWN, win32.WM_LBUTTONUP, win32.WM_LBUTTONDBLCLK:
            x := win32.LOWORD(u32(lParam))
            y := win32.HIWORD(u32(lParam))
            pressed := Msg == win32.WM_LBUTTONDOWN
            event := Mouse_Event{
                window_id,  // window_id
                i32(x),     // x
                i32(y),     // y
                0,          // z
                .Left,      // button
                pressed,    // pressed
                false,      // is_moving
            }
            utils.push_sp_sc_queue(&window_info.event_queue, event)

        case win32.WM_RBUTTONDOWN, win32.WM_RBUTTONUP, win32.WM_RBUTTONDBLCLK:
            x := win32.LOWORD(u32(lParam))
            y := win32.HIWORD(u32(lParam))
            pressed := Msg == win32.WM_RBUTTONDOWN
            event := Mouse_Event{
                window_id,  // window_id
                i32(x),     // x
                i32(y),     // y
                0,          // z
                .Right,     // button
                pressed,    // pressed
                false,      // is_moving
            }
            utils.push_sp_sc_queue(&window_info.event_queue, event)

        case win32.WM_MBUTTONDOWN, win32.WM_MBUTTONUP, win32.WM_MBUTTONDBLCLK:
            x := win32.LOWORD(u32(lParam))
            y := win32.HIWORD(u32(lParam))
            pressed := Msg == win32.WM_MBUTTONDOWN
            event := Mouse_Event{
                window_id,  // window_id
                i32(x),     // x
                i32(y),     // y
                0,          // z
                .Middle,    // button
                pressed,    // pressed
                false,      // is_moving
            }
            utils.push_sp_sc_queue(&window_info.event_queue, event)
            
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
        g_window_class.?.lpszClassName,        // lpClassName
        title,                                      // lpWindowName
        style,                                      // dwStyle
        x,                                          // x
        y,                                          // y
        width,                                      // width
        height,                                     // height
        nil,                                        // hWndParent
        nil,                                        // hMenu
        g_instance,                            // hInstance
        rawptr(uintptr(evn.window_id)),             // lpParam
    )

    if window_handle != nil {
        window_info := g_windows[evn.window_id]
        window_info.handle = window_handle
        window_info.style = style
        window_info.border_rect = border_rect
        window_info.x = x
        window_info.y = y
        window_info.width = width
        window_info.height = height

        win32.SetWindowLongW(window_handle, win32.GWLP_USERDATA, i32(evn.window_id))
        win32.ShowWindow(window_handle, win32.SW_SHOW)

        event := Window_Created_Event{
            evn.window_id,
            Handle(window_handle),
            Instance(g_instance)
        }
        utils.push_sp_sc_queue(&window_info.event_queue, event)
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
    window_info := g_windows[evn.window_id]

    win32.DestroyWindow(window_info.handle)
}

// Translates key modifiers.
//
// Returns:
//   bit_set[Modifier] - The set of active key modifiers.
@(private="file")
win32_translate_key_modifier :: proc() -> bit_set[Modifier] {
    result : bit_set[Modifier] = {}
    for key, modifier in g_modifier_map {
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
    return g_key_map[key] or_else .None
}

// Sets the position of a window.
//
// Parameters:
//   evn: App_Event_Set_Window_Position - The event containing the new window position information.
@(private="file")
win32_set_window_position :: proc(evn: App_Event_Set_Window_Position) {
    window_info := g_windows[evn.window_id]

    x := evn.x + window_info.border_rect.left
    y := evn.y + window_info.border_rect.top
    handle := window_info.handle

    win32.SetWindowPos(handle, nil, x, y, 0, 0, win32.SWP_NOSIZE | win32.SWP_NOZORDER)
}

// Sets the size of a window.
//
// Parameters:
//   evn: App_Event_Set_Window_Size - The event containing the new window size information.
@(private="file")
win32_set_window_size :: proc(evn: App_Event_Set_Window_Size) {
    window_info := g_windows[evn.window_id]

    width := evn.width + window_info.border_rect.right - window_info.border_rect.left
    height := evn.height + window_info.border_rect.bottom - window_info.border_rect.top
    handle := window_info.handle

    win32.SetWindowPos(handle, nil, 0, 0, width, height, win32.SWP_NOMOVE | win32.SWP_NOZORDER)
}

// Sets the title of a window.
//
// Parameters:
//   evn: App_Event_Set_Window_Title - The event containing the new window title information.
@(private="file")
win32_set_window_title :: proc(evn: App_Event_Set_Window_Title) {
    window_info := g_windows[evn.window_id]

    win32.SetWindowTextW(window_info.handle, win32.utf8_to_wstring(evn.title))
}

// Sets the fullscreen state of a window.
//
// Parameters:
//   evn: App_Event_Set_Window_Fullscreen - The event containing the new fullscreen state
//                                          information.
@(private="file")
win32_set_fullscreen :: proc(evn: App_Event_Set_Window_Fullscreen) {
    window_info := g_windows[evn.window_id]
    handle := window_info.handle
    window_style := window_info.style
    window_x := window_info.x
    window_y := window_info.y
    window_width := window_info.width
    window_height := window_info.height

    window_x += window_info.border_rect.left
    window_y += window_info.border_rect.top
    window_width += window_info.border_rect.right - window_info.border_rect.left
    window_height += window_info.border_rect.bottom - window_info.border_rect.top

    window_info.is_fullscreen = evn.fullscreen

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

// g_gamepads is a global array that holds the state of all connected gamepads.
g_gamepads: [MAX_GAMEPADS]Gamepad_State

// g_gamepad_axis_states is a global array that holds the axis states for each gamepad axis.
g_gamepad_axis_states: [len(Gamepad_Axis)]Gamepad_Axis_State

// g_gamepad_button_map is a global array that maps gamepad buttons to XInput button bits.
g_gamepad_button_map: [len(Gamepad_Button)]xinput.XINPUT_GAMEPAD_BUTTON_BIT

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
    axis_state := g_gamepad_axis_states[axis]
    deadzone := axis_state.deadzone
    value^ = value^ > deadzone || value^ < -deadzone ? value^ : 0
    value^ = value^ * i32(axis_state.flip);
    return old != value^;
}

// Polls the state of all gamepads and generates events for any changes.
xinput_poll_gamepads :: proc() {
    for i in 0..<MAX_GAMEPADS {
        gamepad := &g_gamepads[i]
        
        state : xinput.XINPUT_STATE
        result := xinput.XInputGetState(xinput.XUSER(i), &state)
        is_connected := result == win32.System_Error.SUCCESS

        if gamepad.is_connected != is_connected {
            gamepad.is_connected = is_connected
            event := Gamepad_Connection_Event{
                Gamepad_Id(i),
                is_connected,
            }
            utils.push_sp_sc_queue(&g_gamepad_queue, event)
        }

        if is_connected && gamepad.state.dwPacketNumber != state.dwPacketNumber {
            changed := gamepad.state.Gamepad.wButtons ~ state.Gamepad.wButtons
            current := gamepad.state.Gamepad.wButtons;
            if (gamepad.state.Gamepad.wButtons != state.Gamepad.wButtons)
            {
                for button in Gamepad_Button {
                    bit := g_gamepad_button_map[button]
                    if bit in changed {
                        event := Gamepad_Button_Event{
                            Gamepad_Id(i),
                            button,
                            bit in current,
                        }
                        utils.push_sp_sc_queue(&g_gamepad_queue, event)
                    }
                }
            }

            if (gamepad.state.Gamepad.bLeftTrigger != state.Gamepad.bLeftTrigger)
            {
                value := i32(state.Gamepad.bLeftTrigger)
                if xinput_filter_axis(Gamepad_Axis.Left_Trigger,
                                      i32(gamepad.state.Gamepad.bLeftTrigger), &value) {
                    event := Gamepad_Axis_Event{
                        Gamepad_Id(i),
                        Gamepad_Axis.Left_Trigger,
                        f32(value) / 255,
                    }
                    utils.push_sp_sc_queue(&g_gamepad_queue, event)
                }

                gamepad.state.Gamepad.bLeftTrigger = state.Gamepad.bLeftTrigger
            }

            if (gamepad.state.Gamepad.bRightTrigger != state.Gamepad.bRightTrigger)
            {
                value := i32(state.Gamepad.bRightTrigger)
                if xinput_filter_axis(Gamepad_Axis.Right_Trigger,
                                      i32(gamepad.state.Gamepad.bRightTrigger), &value) {
                    event := Gamepad_Axis_Event{
                        Gamepad_Id(i),
                        Gamepad_Axis.Right_Trigger,
                        f32(value) / 255,
                    }
                    utils.push_sp_sc_queue(&g_gamepad_queue, event)
                }

                gamepad.state.Gamepad.bRightTrigger = state.Gamepad.bRightTrigger
            }

            if (gamepad.state.Gamepad.sThumbLX != state.Gamepad.sThumbLX)
            {
                value := i32(state.Gamepad.sThumbLX)
                if xinput_filter_axis(Gamepad_Axis.Left_Thumb_X,
                                      i32(gamepad.state.Gamepad.sThumbLX), &value) {
                    event := Gamepad_Axis_Event{
                        Gamepad_Id(i),
                        Gamepad_Axis.Left_Thumb_X,
                        f32(value) / 32767,
                    }
                    utils.push_sp_sc_queue(&g_gamepad_queue, event)
                }

                gamepad.state.Gamepad.sThumbLX = state.Gamepad.sThumbLX
            }

            if (gamepad.state.Gamepad.sThumbLY != state.Gamepad.sThumbLY)
            {
                value := i32(state.Gamepad.sThumbLY)
                if xinput_filter_axis(Gamepad_Axis.Left_Thumb_Y,
                                      i32(gamepad.state.Gamepad.sThumbLY), &value) {
                    event := Gamepad_Axis_Event{
                        Gamepad_Id(i),
                        Gamepad_Axis.Left_Thumb_Y,
                        f32(value) / 32767,
                    }
                    utils.push_sp_sc_queue(&g_gamepad_queue, event)
                }

                gamepad.state.Gamepad.sThumbLY = state.Gamepad.sThumbLY
            }

            if (gamepad.state.Gamepad.sThumbRX != state.Gamepad.sThumbRX)
            {
                value := i32(state.Gamepad.sThumbRX)
                if xinput_filter_axis(Gamepad_Axis.Right_Thumb_X,
                                      i32(gamepad.state.Gamepad.sThumbRX), &value) {
                    event := Gamepad_Axis_Event{
                        Gamepad_Id(i),
                        Gamepad_Axis.Right_Thumb_X,
                        f32(value) / 32767,
                    }
                    utils.push_sp_sc_queue(&g_gamepad_queue, event)
                }

                gamepad.state.Gamepad.sThumbRX = state.Gamepad.sThumbRX
            }

            if (gamepad.state.Gamepad.sThumbRY != state.Gamepad.sThumbRY)
            {
                value := i32(state.Gamepad.sThumbRY)
                if xinput_filter_axis(Gamepad_Axis.Right_Thumb_Y,
                                      i32(gamepad.state.Gamepad.sThumbRY), &value) {
                    event := Gamepad_Axis_Event{
                        Gamepad_Id(i),
                        Gamepad_Axis.Right_Thumb_Y,
                        f32(value) / 32767,
                    }
                    utils.push_sp_sc_queue(&g_gamepad_queue, event)
                }

                gamepad.state.Gamepad.sThumbRY = state.Gamepad.sThumbRY
            }
        }
    }
}

// Initializes the platform module.
init :: proc() -> bool {
    g_windows = make(map[Window_Id]^Window_Info)
    utils.init_sp_sc_queue(&g_app_to_win32_queue)
    utils.init_sp_sc_queue(&g_gamepad_queue)

    // Initialize the global key map
    g_key_map = make(map[u8]Key)
    g_key_map[win32.VK_ESCAPE]     = .Esc
    g_key_map[win32.VK_RETURN]     = .Return;
    g_key_map[win32.VK_TAB]        = .Tab;
    g_key_map[win32.VK_BACK]       = .Backspace;
    g_key_map[win32.VK_SPACE]      = .Space;
    g_key_map[win32.VK_UP]         = .Up;
    g_key_map[win32.VK_DOWN]       = .Down;
    g_key_map[win32.VK_LEFT]       = .Left;
    g_key_map[win32.VK_RIGHT]      = .Right;
    g_key_map[win32.VK_INSERT]     = .Insert;
    g_key_map[win32.VK_DELETE]     = .Delete;
    g_key_map[win32.VK_HOME]       = .Home;
    g_key_map[win32.VK_END]        = .End;
    g_key_map[win32.VK_PRIOR]      = .Page_Up;
    g_key_map[win32.VK_NEXT]       = .Page_Down;
    g_key_map[win32.VK_SNAPSHOT]   = .Print;
    g_key_map[win32.VK_OEM_PLUS]   = .Plus;
    g_key_map[win32.VK_OEM_MINUS]  = .Minus;
    g_key_map[win32.VK_OEM_4]      = .Left_Bracket;
    g_key_map[win32.VK_OEM_6]      = .Right_Bracket;
    g_key_map[win32.VK_OEM_1]      = .Semicolon;
    g_key_map[win32.VK_OEM_7]      = .Quote;
    g_key_map[win32.VK_OEM_COMMA]  = .Comma;
    g_key_map[win32.VK_OEM_PERIOD] = .Period;
    g_key_map[win32.VK_DECIMAL]    = .Period;
    g_key_map[win32.VK_OEM_2]      = .Slash;
    g_key_map[win32.VK_OEM_5]      = .Backslash;
    g_key_map[win32.VK_OEM_3]      = .Tilde;
    g_key_map[win32.VK_F1]         = .F1;
    g_key_map[win32.VK_F2]         = .F2;
    g_key_map[win32.VK_F3]         = .F3;
    g_key_map[win32.VK_F4]         = .F4;
    g_key_map[win32.VK_F5]         = .F5;
    g_key_map[win32.VK_F6]         = .F6;
    g_key_map[win32.VK_F7]         = .F7;
    g_key_map[win32.VK_F8]         = .F8;
    g_key_map[win32.VK_F9]         = .F9;
    g_key_map[win32.VK_F10]        = .F10;
    g_key_map[win32.VK_F11]        = .F11;
    g_key_map[win32.VK_F12]        = .F12;
    g_key_map[win32.VK_NUMPAD0]    = .Num_Pad_0;
    g_key_map[win32.VK_NUMPAD1]    = .Num_Pad_1;
    g_key_map[win32.VK_NUMPAD2]    = .Num_Pad_2;
    g_key_map[win32.VK_NUMPAD3]    = .Num_Pad_3;
    g_key_map[win32.VK_NUMPAD4]    = .Num_Pad_4;
    g_key_map[win32.VK_NUMPAD5]    = .Num_Pad_5;
    g_key_map[win32.VK_NUMPAD6]    = .Num_Pad_6;
    g_key_map[win32.VK_NUMPAD7]    = .Num_Pad_7;
    g_key_map[win32.VK_NUMPAD8]    = .Num_Pad_8;
    g_key_map[win32.VK_NUMPAD9]    = .Num_Pad_9;
    g_key_map[u8('0')]             = .Key_0;
    g_key_map[u8('1')]             = .Key_1;
    g_key_map[u8('2')]             = .Key_2;
    g_key_map[u8('3')]             = .Key_3;
    g_key_map[u8('4')]             = .Key_4;
    g_key_map[u8('5')]             = .Key_5;
    g_key_map[u8('6')]             = .Key_6;
    g_key_map[u8('7')]             = .Key_7;
    g_key_map[u8('8')]             = .Key_8;
    g_key_map[u8('9')]             = .Key_9;
    g_key_map[u8('A')]             = .Key_A;
    g_key_map[u8('B')]             = .Key_B;
    g_key_map[u8('C')]             = .Key_C;
    g_key_map[u8('D')]             = .Key_D;
    g_key_map[u8('E')]             = .Key_E;
    g_key_map[u8('F')]             = .Key_F;
    g_key_map[u8('G')]             = .Key_G;
    g_key_map[u8('H')]             = .Key_H;
    g_key_map[u8('I')]             = .Key_I;
    g_key_map[u8('J')]             = .Key_J;
    g_key_map[u8('K')]             = .Key_K;
    g_key_map[u8('L')]             = .Key_L;
    g_key_map[u8('M')]             = .Key_M;
    g_key_map[u8('N')]             = .Key_N;
    g_key_map[u8('O')]             = .Key_O;
    g_key_map[u8('P')]             = .Key_P;
    g_key_map[u8('Q')]             = .Key_Q;
    g_key_map[u8('R')]             = .Key_R;
    g_key_map[u8('S')]             = .Key_S;
    g_key_map[u8('T')]             = .Key_T;
    g_key_map[u8('U')]             = .Key_U;
    g_key_map[u8('V')]             = .Key_V;
    g_key_map[u8('W')]             = .Key_W;
    g_key_map[u8('X')]             = .Key_X;
    g_key_map[u8('Y')]             = .Key_Y;
    g_key_map[u8('Z')]             = .Key_Z;

    // Initialize the global modifier map
    g_modifier_map = make(map[u8]Modifier)
    g_modifier_map[win32.VK_LMENU]    = .Left_Alt
    g_modifier_map[win32.VK_RMENU]    = .Right_Alt
    g_modifier_map[win32.VK_LCONTROL] = .Left_Ctrl
    g_modifier_map[win32.VK_RCONTROL] = .Right_Ctrl
    g_modifier_map[win32.VK_LSHIFT]   = .Left_Shift
    g_modifier_map[win32.VK_RSHIFT]   = .Right_Shift
    g_modifier_map[win32.VK_LWIN]     = .Left_Meta
    g_modifier_map[win32.VK_RWIN]     = .Right_Meta

    // Initialize the global gamepad axis states
    g_gamepad_axis_states[Gamepad_Axis.Left_Thumb_X].deadzone  = i32(xinput.XINPUT_GAMEPAD_LEFT_THUMB_DEADZONE)
    g_gamepad_axis_states[Gamepad_Axis.Left_Thumb_X].flip      = 1
    g_gamepad_axis_states[Gamepad_Axis.Left_Thumb_Y].deadzone  = i32(xinput.XINPUT_GAMEPAD_LEFT_THUMB_DEADZONE)
    g_gamepad_axis_states[Gamepad_Axis.Left_Thumb_Y].flip      = -1
    g_gamepad_axis_states[Gamepad_Axis.Right_Thumb_X].deadzone = i32(xinput.XINPUT_GAMEPAD_RIGHT_THUMB_DEADZONE)
    g_gamepad_axis_states[Gamepad_Axis.Right_Thumb_X].flip     = 1
    g_gamepad_axis_states[Gamepad_Axis.Right_Thumb_Y].deadzone = i32(xinput.XINPUT_GAMEPAD_RIGHT_THUMB_DEADZONE)
    g_gamepad_axis_states[Gamepad_Axis.Right_Thumb_Y].flip     = -1
    g_gamepad_axis_states[Gamepad_Axis.Left_Trigger].deadzone  = i32(xinput.XINPUT_GAMEPAD_TRIGGER_THRESHOLD)
    g_gamepad_axis_states[Gamepad_Axis.Left_Trigger].flip      = 1
    g_gamepad_axis_states[Gamepad_Axis.Right_Trigger].deadzone = i32(xinput.XINPUT_GAMEPAD_TRIGGER_THRESHOLD)
    g_gamepad_axis_states[Gamepad_Axis.Right_Trigger].flip     = 1

    // Initialize the global gamepad button map
    g_gamepad_button_map[Gamepad_Button.Up]             = xinput.XINPUT_GAMEPAD_BUTTON_BIT.DPAD_UP
    g_gamepad_button_map[Gamepad_Button.Down]           = xinput.XINPUT_GAMEPAD_BUTTON_BIT.DPAD_DOWN
    g_gamepad_button_map[Gamepad_Button.Left]           = xinput.XINPUT_GAMEPAD_BUTTON_BIT.DPAD_LEFT
    g_gamepad_button_map[Gamepad_Button.Right]          = xinput.XINPUT_GAMEPAD_BUTTON_BIT.DPAD_RIGHT
    g_gamepad_button_map[Gamepad_Button.Start]          = xinput.XINPUT_GAMEPAD_BUTTON_BIT.START
    g_gamepad_button_map[Gamepad_Button.Back]           = xinput.XINPUT_GAMEPAD_BUTTON_BIT.BACK
    g_gamepad_button_map[Gamepad_Button.Left_Thumb]     = xinput.XINPUT_GAMEPAD_BUTTON_BIT.LEFT_THUMB
    g_gamepad_button_map[Gamepad_Button.Right_Thumb]    = xinput.XINPUT_GAMEPAD_BUTTON_BIT.RIGHT_THUMB
    g_gamepad_button_map[Gamepad_Button.Left_Shoulder]  = xinput.XINPUT_GAMEPAD_BUTTON_BIT.LEFT_SHOULDER
    g_gamepad_button_map[Gamepad_Button.Right_Shoulder] = xinput.XINPUT_GAMEPAD_BUTTON_BIT.RIGHT_SHOULDER
    g_gamepad_button_map[Gamepad_Button.A]              = xinput.XINPUT_GAMEPAD_BUTTON_BIT.A
    g_gamepad_button_map[Gamepad_Button.B]              = xinput.XINPUT_GAMEPAD_BUTTON_BIT.B
    g_gamepad_button_map[Gamepad_Button.X]              = xinput.XINPUT_GAMEPAD_BUTTON_BIT.X
    g_gamepad_button_map[Gamepad_Button.Y]              = xinput.XINPUT_GAMEPAD_BUTTON_BIT.Y

    // Initialize Win32 window class
    g_instance := win32.HINSTANCE(win32.GetModuleHandleA(nil))

    g_window_class = win32.WNDCLASSEXW {
        size_of(win32.WNDCLASSEXW),                  // cbSize
        win32.CS_HREDRAW | win32.CS_VREDRAW,         // style
        win32.WNDPROC(win32_window_proc),            // lpfnWndProc
        0,                                           // cbClsExtra
        0,                                           // cbWndExtra
        g_instance,                             // hInstance
        win32.LoadIconA(nil, win32.IDI_APPLICATION), // hIcon
        win32.LoadCursorA(nil, win32.IDC_ARROW),     // hCursor
        win32.CreateSolidBrush(0xFF303030),          // hbrBackground
        nil,                                         // lpszMenuName
        win32.L("ChronicleWindowClass"),             // lpszClassName
        win32.LoadIconA(nil, win32.IDI_APPLICATION), // hIconSm
    }

    if win32.RegisterClassExW(&g_window_class.?) == 0 {
        log.error("Failed to register window class")
        return false
    }

    return true
}

// Destroys the platform module.
destroy :: proc() {
    delete(g_modifier_map)
    delete(g_key_map)

    utils.destroy_sp_sc_queue(&g_gamepad_queue)
    utils.destroy_sp_sc_queue(&g_app_to_win32_queue)
    delete(g_windows)
}

// Creates a window.
//
// Parameters:
//   info: Window_Init_Info - The initialization information for the window.
//
// Returns:
//   Window_Id - The identifier of the newly created window.
create_window :: proc(info: Window_Init_Info) -> Window_Id {
    assert(os.current_thread_id() == g_main_thread.id,
           "create_window must be called from the main thread")

    window_id := win32_add_window()
    event := App_Event_Create_Window{window_id, info}
    utils.push_sp_sc_queue(&g_app_to_win32_queue, event)
    return window_id
}

// Destroys a window.
//
// Parameters:
//   window_id: Window_Id - The identifier of the window to destroy.
destroy_window :: proc(window_id: Window_Id) {
    assert(os.current_thread_id() == g_main_thread.id,
           "destroy_window must be called from the main thread")

    event := App_Event_Destroy_Window{window_id}
    utils.push_sp_sc_queue(&g_app_to_win32_queue, event)
}

// Sets the position of a window.
//
// Parameters:
//   window_id: Window_Id - The identifier of the window to move.
//   x: i32 - The new x-coordinate of the window.
//   y: i32 - The new y-coordinate of the window.
set_window_position :: proc(window_id: Window_Id, x: i32, y: i32) {
    assert(os.current_thread_id() == g_main_thread.id,
           "set_window_position must be called from the main thread")

    event := App_Event_Set_Window_Position{window_id, x, y}
    utils.push_sp_sc_queue(&g_app_to_win32_queue, event)
}

// Sets the size of a window.
//
// Parameters:
//   window_id: Window_Id - The identifier of the window to resize.
//   width: i32 - The new width of the window.
//   height: i32 - The new height of the window.
set_window_size :: proc(window_id: Window_Id, width: i32, height: i32) {
    assert(os.current_thread_id() == g_main_thread.id,
           "set_window_size must be called from the main thread")

    event := App_Event_Set_Window_Size{window_id, width, height}
    utils.push_sp_sc_queue(&g_app_to_win32_queue, event)
}

// Sets the title of a window.
//
// Parameters:
//   window_id: Window_Id - The identifier of the window to rename.
//   title: string - The new title of the window.
set_window_title :: proc(window_id: Window_Id, title: string) {
    assert(os.current_thread_id() == g_main_thread.id,
           "set_window_title must be called from the main thread")

    event := App_Event_Set_Window_Title{window_id, title}
    utils.push_sp_sc_queue(&g_app_to_win32_queue, event)
}

// Sets the fullscreen state of a window.
//
// Parameters:
//   window_id: Window_Id - The identifier of the window to modify.
//   fullscreen: bool - Indicates whether the window should be fullscreen.
set_window_fullscreen :: proc(window_id: Window_Id, fullscreen: bool) {
    assert(os.current_thread_id() == g_main_thread.id,
           "set_window_fullscreen must be called from the main thread")

    event := App_Event_Set_Window_Fullscreen{window_id, fullscreen}
    utils.push_sp_sc_queue(&g_app_to_win32_queue, event)
}

// Polls for window events.
//
// Parameters:
//   window_id: Window_Id - The identifier of the window to poll.
//
// Returns:
//   (Window_Event, bool) - A tuple containing the event and a boolean indicating success.
poll_window :: proc(window_id: Window_Id) -> (Window_Event, bool) {
    assert(os.current_thread_id() == g_main_thread.id,
           "poll_window must be called from the main thread")

    window_info, have_window := g_windows[window_id]
    if !have_window {
        return nil, false
    }

    event, ok := utils.peek_sp_sc_queue(&window_info.event_queue)

    #partial switch e in event {
    case Window_Destroyed_Event:
        win32_remove_window(window_id)
    }

    return event, ok
}

// Polls for gamepad events.
//
// Returns:
//   (Gamepad_Event, bool) - A tuple containing the event and a boolean indicating success.
poll_gamepad :: proc() -> (Gamepad_Event, bool) {
    assert(os.current_thread_id() == g_main_thread.id,
           "poll_gamepad must be called from the main thread")

    return utils.peek_sp_sc_queue(&g_gamepad_queue)
}

// Loads a module from a file.
//
// Parameters:
//  path: string - The path to the module file.
//
// Returns:
//  rawptr - A pointer to the loaded module.
load_module :: proc(path: string) -> rawptr {
    return win32.LoadLibraryW(win32.utf8_to_wstring(path))
}

// Gets a symbol from a module.
//
// Parameters:
//  module: rawptr - A pointer to the module.
//  name: string - The name of the symbol to retrieve.
//
// Returns:
//  rawptr - A pointer to the symbol.
get_module_symbol :: proc(module: rawptr, name: string) -> rawptr {
    return win32.GetProcAddress(win32.HMODULE(module), strings.unsafe_string_to_cstring(name))
}

// Runs the main event loop.
//
// Parameters:
//   worker: proc(t: ^thread.Thread) - The worker procedure to run in the thread.
run :: proc(worker: proc(t: ^thread.Thread)) {
    g_main_thread = thread.create(worker)
    if g_main_thread == nil {
        log.error("Failed to create thread")
        return
    }
    defer thread.destroy(g_main_thread)

    worker_arena: vmem.Arena
    if vmem.arena_init_growing(&worker_arena) != .None {
        log.error("Failed to initialize worker arena")
        return
    }
    defer vmem.arena_destroy(&worker_arena)

    // TODO: Create allocators for the thread
    worker_context := context
    worker_context.temp_allocator = vmem.arena_allocator(&worker_arena)
    g_main_thread.init_context = context
    thread.start(g_main_thread)

    for !thread.is_done(g_main_thread) {
        for event in utils.peek_sp_sc_queue(&g_app_to_win32_queue) {
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

        time.sleep(time.Millisecond*8) // TODO: what is the right wait time?
        thread.yield()

        free_all(context.temp_allocator)
    }

    // clean up windows that were not destroyed
    for window_id in g_windows {
        win32_remove_window(window_id)
    }
}