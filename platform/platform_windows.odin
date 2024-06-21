package platform

import "core:log"
import "core:thread"
import "core:sync"

import win32 "core:sys/windows"

// TODO: remove
import "core:fmt"

import "../utils"

@(private="file")
Window_Info :: struct {
    handle: win32.HWND,
    //title: string,
    //x: Maybe(i32),
    //y: Maybe(i32),
    //width: Maybe(i32),
    //height: Maybe(i32),
    
}

@(private="file")
App_Event_Create_Window :: struct {
    window_id: Window_Id,
    info: Window_Init_Info
}

@(private="file")
App_Event_Destroy_Window :: struct {
    window_id: Window_Id
}

@(private="file")
App_Event :: union {
    App_Event_Create_Window,
    App_Event_Destroy_Window,
}

@(private="file")
global_windows : utils.Free_List(Window_Info)

@(private="file")
global_windows_lock : sync.Mutex

@(private="file")
global_app_to_win32_queue : utils.Sp_Sc_Queue(App_Event)

@(private="file")
global_win32_to_app_queue : utils.Sp_Sc_Queue(Platform_Event)

@(private="file")
global_window_class : Maybe(win32.WNDCLASSEXW)

@(private="file")
global_key_map : map[u8]Key

@(private="file")
global_modifier_map : map[u8]Modifier

@(private="file")
global_surrogate : win32.WCHAR

@(private="file")
win32_window_proc :: proc(hWnd: win32.HWND, Msg: win32.UINT, wParam: win32.WPARAM, lParam: win32.LPARAM) -> win32.LRESULT {
    window_id := Window_Id(win32.GetWindowLongW(hWnd, win32.GWLP_USERDATA))

    result: win32.LRESULT = 0
    switch Msg {
        case win32.WM_SIZE:
            fmt.println("WM_SIZE")
        case win32.WM_CLOSE:
            utils.push_sp_sc_queue(&global_win32_to_app_queue, Window_Close_Requested_Event{window_id})
        //case win32.WM_DESTROY:
        //    fmt.println("WM_DESTROY")
        //    win32.PostQuitMessage(0)
        //case win32.WM_ACTIVATEAPP:
        //    fmt.println("WM_ACTIVATEAPP")
        case win32.WM_SYSKEYDOWN, win32.WM_KEYDOWN:
            key_event := Key_Event{
                window_id,
                win32_translate_key(u8(wParam)),
                win32_translate_key_modifier(),
                true,
            }
            utils.push_sp_sc_queue(&global_win32_to_app_queue, key_event)
        case win32.WM_SYSKEYUP, win32.WM_KEYUP:
            key_event := Key_Event{
                window_id,
                win32_translate_key(u8(wParam)),
                win32_translate_key_modifier(),
                false,
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

@(private="file")
win32_create_window :: proc(evn: App_Event_Create_Window) {
    instance := win32.HINSTANCE(win32.GetModuleHandleA(nil))

    sync.mutex_lock(&global_windows_lock)
    defer sync.mutex_unlock(&global_windows_lock)

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

    title := win32.utf8_to_wstring(len(info.title) == 0 ? "Chronicle" : info.title);
    window_handle := win32.CreateWindowExW(
        0,                                          // dwExStyle
        global_window_class.?.lpszClassName,        // lpClassName
        title,                                      // lpWindowName
        win32.WS_OVERLAPPEDWINDOW|win32.WS_VISIBLE, // dwStyle
        x,                                          // x
        y,                                          // y
        width,                                      // width
        height,                                     // height
        nil,                                        // hWndParent
        nil,                                        // hMenu
        instance,                                   // hInstance
        nil,                                        // lpParam
    )

    if window_handle != nil {
        win32.SetWindowLongW(window_handle, win32.GWLP_USERDATA, i32(evn.window_id))

        window_info := utils.get_from_free_list(&global_windows, u32(evn.window_id))
        window_info.handle = window_handle
    }
    else {
        log.error("Failed to create window")
    }
}

@(private="file")
win32_destroy_window :: proc(evn: App_Event_Destroy_Window) {
    sync.mutex_lock(&global_windows_lock)
    defer sync.mutex_unlock(&global_windows_lock)

    window_info := utils.get_from_free_list(&global_windows, u32(evn.window_id))
    win32.DestroyWindow(window_info.handle)
    utils.remove_from_free_list(&global_windows, u32(evn.window_id))
}

win32_translate_key_modifier :: proc() -> bit_set[Modifier] {
    result : bit_set[Modifier] = {}
    for key, modifier in global_modifier_map {
        if win32.GetKeyState(i32(key)) < 0 {
            result |= {modifier}
        }
    }
    return result
}

win32_translate_key :: proc(key: u8) -> Key {
    return global_key_map[key] or_else .None
}

init :: proc() {
    utils.init_free_list(&global_windows, 10)
    utils.init_sp_sc_queue(&global_app_to_win32_queue)
    utils.init_sp_sc_queue(&global_win32_to_app_queue)

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

    global_modifier_map = make(map[u8]Modifier)
    global_modifier_map[win32.VK_LMENU]    = .Left_Alt
    global_modifier_map[win32.VK_RMENU]    = .Right_Alt
    global_modifier_map[win32.VK_LCONTROL] = .Left_Ctrl
    global_modifier_map[win32.VK_RCONTROL] = .Right_Ctrl
    global_modifier_map[win32.VK_LSHIFT]   = .Left_Shift
    global_modifier_map[win32.VK_RSHIFT]   = .Right_Shift
    global_modifier_map[win32.VK_LWIN]     = .Left_Meta
    global_modifier_map[win32.VK_RWIN]     = .Right_Meta
}

destroy :: proc() {
    delete(global_modifier_map)
    delete(global_key_map)

    utils.destroy_sp_sc_queue(&global_win32_to_app_queue)
    utils.destroy_sp_sc_queue(&global_app_to_win32_queue)
    utils.destroy_free_list(&global_windows)
}

create_window :: proc(info: Window_Init_Info) -> Window_Id {
    sync.mutex_lock(&global_windows_lock)
    defer sync.mutex_unlock(&global_windows_lock)

    window_id := Window_Id(utils.add_to_free_list(&global_windows, Window_Info{}))

    utils.push_sp_sc_queue(&global_app_to_win32_queue, App_Event_Create_Window{window_id, info})
    return window_id
}

destroy_window :: proc(window_id: Window_Id) {
    utils.push_sp_sc_queue(&global_app_to_win32_queue, App_Event_Destroy_Window{window_id})
}

poll :: proc() -> (Platform_Event, bool) {
    return utils.peek_sp_sc_queue(&global_win32_to_app_queue)
}

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
            }
        }

        message: win32.MSG
        for win32.PeekMessageW(&message, nil, 0, 0, win32.PM_REMOVE) {
            win32.TranslateMessage(&message)
            win32.DispatchMessageW(&message)
        }

        thread.yield()
    }

    thread.destroy(t)
}