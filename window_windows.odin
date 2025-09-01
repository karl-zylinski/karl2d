package karl2d

import win32 "core:sys/windows"
import "base:runtime"
import "core:slice"

Window_Handle :: distinct uintptr

Window_State :: struct {
	custom_context: runtime.Context,
	hwnd: win32.HWND,
	window_should_close: bool,
	events: [dynamic]Window_Event,
}

Window_Event_Key_Went_Down :: struct {
	key: Keyboard_Key,
}

Window_Event_Key_Went_Up :: struct {
	key: Keyboard_Key,
}

Window_Event :: union  {
	Window_Event_Key_Went_Down,
	Window_Event_Key_Went_Up,
}

window_state_size :: proc() -> int {
	return size_of(Window_State)
}

// TODO rename to "ws"
@(private="file")
s: ^Window_State

window_init :: proc(ws_in: rawptr, window_width: int, window_height: int, window_title: string) {
	assert(ws_in != nil)
	s = (^Window_State)(ws_in)
	s.custom_context = context
	win32.SetProcessDPIAware()
	CLASS_NAME :: "karl2d"
	instance := win32.HINSTANCE(win32.GetModuleHandleW(nil))

	cls := win32.WNDCLASSW {
		lpfnWndProc = _win32_window_proc,
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

window_shutdown :: proc() {
	win32.DestroyWindow(s.hwnd)
}

window_set_position :: proc(x: int, y: int) {
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

window_handle :: proc() -> Window_Handle {
	return Window_Handle(s.hwnd)
}

// TODO: perhaps this should be split into several procs later
window_process_events :: proc(allocator := context.temp_allocator) -> []Window_Event {
	msg: win32.MSG

	for win32.PeekMessageW(&msg, nil, 0, 0, win32.PM_REMOVE) {
		win32.TranslateMessage(&msg)
		win32.DispatchMessageW(&msg)
	}

	return slice.clone(s.events[:], allocator)
}

_window_should_close :: proc() -> bool {
	return s.window_should_close
}

_win32_window_proc :: proc "stdcall" (hwnd: win32.HWND, msg: win32.UINT, wparam: win32.WPARAM, lparam: win32.LPARAM) -> win32.LRESULT {
	context = s.custom_context
	switch msg {
	case win32.WM_DESTROY:
		win32.PostQuitMessage(0)
		s.window_should_close = true

	case win32.WM_CLOSE:
		s.window_should_close = true

	case win32.WM_KEYDOWN:
		key := VK_MAP[wparam]
		append(&s.events, Window_Event_Key_Went_Down {
			key = key,
		})

	case win32.WM_KEYUP:
		key := VK_MAP[wparam]
		append(&s.events, Window_Event_Key_Went_Up {
			key = key,
		})
	}

	return win32.DefWindowProcW(hwnd, msg, wparam, lparam)
}

VK_MAP := [255]Keyboard_Key {
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
	win32.VK_LEFT = .Left,
	win32.VK_RIGHT = .Right,
	win32.VK_UP = .Up,
	win32.VK_DOWN = .Down,
}