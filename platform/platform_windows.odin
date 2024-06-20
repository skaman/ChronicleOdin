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
win32_window_proc :: proc(hWnd: win32.HWND, Msg: win32.UINT, wParam: win32.WPARAM, lParam: win32.LPARAM) -> win32.LRESULT {
    window_id := Window_Id(win32.GetWindowLongW(hWnd, win32.GWLP_USERDATA))

    result: win32.LRESULT = 0
    switch Msg {
        case win32.WM_SIZE:
            fmt.println("WM_SIZE")
        case win32.WM_CLOSE:
            fmt.println("WM_CLOSE")
            utils.push_sp_sc_queue(&global_win32_to_app_queue, Window_Close_Requested{window_id})
        //case win32.WM_DESTROY:
        //    fmt.println("WM_DESTROY")
        //    win32.PostQuitMessage(0)
        case win32.WM_ACTIVATEAPP:
            fmt.println("WM_ACTIVATEAPP")
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
        win32.HWND(info.parent_handle),             // hWndParent
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

init :: proc() {
    utils.init_free_list(&global_windows, 10)
    utils.init_sp_sc_queue(&global_app_to_win32_queue)
    utils.init_sp_sc_queue(&global_win32_to_app_queue)
}

destroy :: proc() {
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