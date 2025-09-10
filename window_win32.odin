#+build windows
#+private file

package karl2d

@(private="package")
WINDOW_INTERFACE_WIN32 :: Window_Interface {
	state_size = win32_state_size,
	init = win32_init,
	window_handle = win32_window_handle,
	process_events = win32_process_events,
	get_events = win32_get_events,
	clear_events = win32_clear_events,
	set_position = win32_set_position,
	set_size = win32_set_size,
	set_internal_state = win32_set_internal_state,
}

import win32 "core:sys/windows"
import "base:runtime"

win32_state_size :: proc() -> int {
	return size_of(Win32_State)
}

win32_init :: proc(window_state: rawptr, window_width: int, window_height: int, window_title: string, allocator := context.allocator) {
	assert(window_state != nil)
	s = (^Win32_State)(window_state)
	s.allocator = allocator
	s.events = make([dynamic]Window_Event, allocator)
	s.custom_context = context
	win32.SetProcessDPIAware()
	CLASS_NAME :: "karl2d"
	instance := win32.HINSTANCE(win32.GetModuleHandleW(nil))

	cls := win32.WNDCLASSW {
		lpfnWndProc = window_proc,
		lpszClassName = CLASS_NAME,
		hInstance = instance,
		hCursor = win32.LoadCursorA(nil, win32.IDC_ARROW),
	}

	win32.RegisterClassW(&cls)

	r: win32.RECT
	r.right = i32(window_width)
	r.bottom = i32(window_height)

	style := win32.WS_OVERLAPPEDWINDOW | win32.WS_VISIBLE
	win32.AdjustWindowRect(&r, style, false)

	hwnd := win32.CreateWindowW(CLASS_NAME,
		win32.utf8_to_wstring(window_title),
		style,
		100, 10, r.right - r.left, r.bottom - r.top,
		nil, nil, instance, nil,
	)

	assert(hwnd != nil, "Failed creating window")

	s.hwnd = hwnd
}

win32_shutdown :: proc() {
	delete(s.events)
	win32.DestroyWindow(s.hwnd)
}

win32_window_handle :: proc() -> Window_Handle {
	return Window_Handle(s.hwnd)
}

win32_process_events :: proc() {
	msg: win32.MSG

	for win32.PeekMessageW(&msg, nil, 0, 0, win32.PM_REMOVE) {
		win32.TranslateMessage(&msg)
		win32.DispatchMessageW(&msg)
	}
}

win32_get_events :: proc() -> []Window_Event {
	return s.events[:]
}

win32_clear_events :: proc() {
	runtime.clear(&s.events)
}

win32_set_position :: proc(x: int, y: int) {
	// TODO: Does x, y respect monitor DPI?

	win32.SetWindowPos(
		s.hwnd,
		{},
		i32(x),
		i32(y),
		0,
		0,
		win32.SWP_NOACTIVATE | win32.SWP_NOZORDER | win32.SWP_NOSIZE,
	)
}

win32_set_size :: proc(w, h: int) {
	win32.SetWindowPos(
		s.hwnd,
		{},
		0,
		0,
		i32(w),
		i32(h),
		win32.SWP_NOACTIVATE | win32.SWP_NOZORDER | win32.SWP_NOMOVE,
	)
}

win32_set_internal_state :: proc(state: rawptr) {
	assert(state != nil)
	s = (^Win32_State)(state)
}

Win32_State :: struct {
	allocator: runtime.Allocator,
	custom_context: runtime.Context,
	hwnd: win32.HWND,
	window_should_close: bool,
	events: [dynamic]Window_Event,
}

s: ^Win32_State

window_proc :: proc "stdcall" (hwnd: win32.HWND, msg: win32.UINT, wparam: win32.WPARAM, lparam: win32.LPARAM) -> win32.LRESULT {
	context = s.custom_context
	switch msg {
	case win32.WM_DESTROY:
		win32.PostQuitMessage(0)

	case win32.WM_CLOSE:
		append(&s.events, Window_Event_Close_Wanted{})

	case win32.WM_KEYDOWN:
		key := WIN32_VK_MAP[wparam]
		append(&s.events, Window_Event_Key_Went_Down {
			key = key,
		})

		return 0

	case win32.WM_KEYUP:
		key := WIN32_VK_MAP[wparam]
		append(&s.events, Window_Event_Key_Went_Up {
			key = key,
		})

		return 0

	case win32.WM_MOUSEMOVE:
		x := win32.GET_X_LPARAM(lparam)
		y := win32.GET_Y_LPARAM(lparam)
		append(&s.events, Window_Event_Mouse_Move {
			position = {f32(x), f32(y)},
		})

		return 0

	case win32.WM_MOUSEWHEEL:
		delta := f32(win32.GET_WHEEL_DELTA_WPARAM(wparam))/win32.WHEEL_DELTA

		append(&s.events, Window_Event_Mouse_Wheel {
			delta = delta,
		})

	case win32.WM_SIZE:
		width := win32.LOWORD(lparam)
		height := win32.HIWORD(lparam)

		append(&s.events, Window_Event_Resize {
			width = int(width),
			height = int(height),
		})
	}

	return win32.DefWindowProcW(hwnd, msg, wparam, lparam)
}

WIN32_VK_MAP := [255]Keyboard_Key {
	win32.VK_F1 = .F1,
	win32.VK_F2 = .F2,
	win32.VK_F3 = .F3,
	win32.VK_F4 = .F4,
	win32.VK_F5 = .F5,
	win32.VK_F6 = .F6,
	win32.VK_F7 = .F7,
	win32.VK_F8 = .F8,
	win32.VK_F9 = .F9,
	win32.VK_F10 = .F10,
	win32.VK_F11 = .F11,
	win32.VK_F12 = .F12,
	win32.VK_A = .A,
	win32.VK_B = .B,
	win32.VK_C = .C,
	win32.VK_D = .D,
	win32.VK_E = .E,
	win32.VK_F = .F,
	win32.VK_G = .G,
	win32.VK_H = .H,
	win32.VK_I = .I,
	win32.VK_J = .J,
	win32.VK_K = .K,
	win32.VK_L = .L,
	win32.VK_M = .M,
	win32.VK_N = .N,
	win32.VK_O = .O,
	win32.VK_P = .P,
	win32.VK_Q = .Q,
	win32.VK_R = .R,
	win32.VK_S = .S,
	win32.VK_T = .T,
	win32.VK_U = .U,
	win32.VK_V = .V,
	win32.VK_W = .W,
	win32.VK_X = .X,
	win32.VK_Y = .Y,
	win32.VK_Z = .Z,
	win32.VK_SPACE = .Space,
	win32.VK_LEFT = .Left,
	win32.VK_RIGHT = .Right,
	win32.VK_UP = .Up,
	win32.VK_DOWN = .Down,
	win32.VK_RETURN = .Enter,
}