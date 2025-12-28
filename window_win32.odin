#+build windows
#+private file

package karl2d

@(private="package")
WINDOW_INTERFACE_WIN32 :: Window_Interface {
	state_size = win32_state_size,
	init = win32_init,
	shutdown = win32_shutdown,
	window_handle = win32_window_handle,
	process_events = win32_process_events,
	get_events = win32_get_events,
	get_width = win32_get_width,
	get_height = win32_get_height,
	clear_events = win32_clear_events,
	set_position = win32_set_position,
	set_size = win32_set_size,
	get_window_scale = win32_get_window_scale,
	set_flags = win32_set_flags,
	is_gamepad_active = win32_is_gamepad_active,
	get_gamepad_axis = win32_get_gamepad_axis,
	set_gamepad_vibration = win32_set_gamepad_vibration,

	set_internal_state = win32_set_internal_state,
}

import win32 "core:sys/windows"
import "base:runtime"

win32_state_size :: proc() -> int {
	return size_of(Win32_State)
}

win32_init :: proc(window_state: rawptr, window_width: int, window_height: int, window_title: string,
	               flags: Window_Flags, allocator: runtime.Allocator) {
	assert(window_state != nil)
	s = (^Win32_State)(window_state)
	s.allocator = allocator
	s.events = make([dynamic]Window_Event, allocator)
	s.width = window_width
	s.height = window_height
	s.custom_context = context
	
	win32.SetProcessDpiAwarenessContext(win32.DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2)
	win32.SetProcessDPIAware()
	CLASS_NAME :: "karl2d"
	instance := win32.HINSTANCE(win32.GetModuleHandleW(nil))

	cls := win32.WNDCLASSW {
		style = win32.CS_OWNDC,
		lpfnWndProc = window_proc,
		lpszClassName = CLASS_NAME,
		hInstance = instance,
		hCursor = win32.LoadCursorA(nil, win32.IDC_ARROW),
	}

	win32.RegisterClassW(&cls)

	r: win32.RECT
	r.right = i32(window_width)
	r.bottom = i32(window_height)

	s.flags = flags

	style := style_from_flags(flags)

	win32.AdjustWindowRect(&r, style, false)

	hwnd := win32.CreateWindowW(CLASS_NAME,
		win32.utf8_to_wstring(window_title),
		style,
		win32.CW_USEDEFAULT, win32.CW_USEDEFAULT,
		r.right - r.left, r.bottom - r.top,
		nil, nil, instance, nil,
	)

	win32.XInputEnable(true)

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

	for gamepad in 0..<4 {
		gp_event: win32.XINPUT_KEYSTROKE

		for win32.XInputGetKeystroke(win32.XUSER(gamepad), 0, &gp_event) == .SUCCESS {
			button: Maybe(Gamepad_Button)

			#partial switch gp_event.VirtualKey {
			case .DPAD_UP:    button = .Left_Face_Up
			case .DPAD_DOWN:  button = .Left_Face_Down
			case .DPAD_LEFT:  button = .Left_Face_Left
			case .DPAD_RIGHT: button = .Left_Face_Right

			case .Y: button = .Right_Face_Up
			case .A: button = .Right_Face_Down
			case .X: button = .Right_Face_Left
			case .B: button = .Right_Face_Right

			case .LSHOULDER: button = .Left_Shoulder
			case .LTRIGGER:  button = .Left_Trigger

			case .RSHOULDER: button = .Right_Shoulder
			case .RTRIGGER:  button = .Right_Trigger

			case .BACK: button = .Middle_Face_Left
			
			// Not sure you can get the "middle button" with XInput (the one that goe to dashboard)

			case .START: button = .Middle_Face_Right

			case .LTHUMB_PRESS: button = .Left_Stick_Press
			case .RTHUMB_PRESS: button = .Right_Stick_Press
			}

			b := button.? or_continue
			evt: Window_Event

			if .KEYDOWN in gp_event.Flags {
				evt = Window_Event_Gamepad_Button_Went_Down {
					gamepad = gamepad,
					button = b,
				}
			} else if .KEYUP in gp_event.Flags {
				evt = Window_Event_Gamepad_Button_Went_Up {
					gamepad = gamepad,
					button = b,
				}
			}

			if evt != nil {
				append(&s.events, evt)
			}
		}
	}
	
}

win32_get_events :: proc() -> []Window_Event {
	return s.events[:]
}

win32_get_width :: proc() -> int {
	return s.width
}

win32_get_height :: proc() -> int {
	return s.height
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

win32_get_window_scale :: proc() -> f32 {
	return f32(win32.GetDpiForWindow(s.hwnd))/96.0
}

win32_set_flags :: proc(flags: Window_Flags) {
	s.flags = flags
	style := style_from_flags(flags)
	win32.SetWindowLongW(s.hwnd, win32.GWL_STYLE, i32(style))
}

win32_is_gamepad_active :: proc(gamepad: int) -> bool {
	if gamepad < 0 || gamepad >= MAX_GAMEPADS {
		return false
	}

	gp_state: win32.XINPUT_STATE
	return win32.XInputGetState(win32.XUSER(gamepad), &gp_state) == .SUCCESS
}

win32_get_gamepad_axis :: proc(gamepad: int, axis: Gamepad_Axis) -> f32 {
	if gamepad < 0 || gamepad >= MAX_GAMEPADS {
		return 0
	}

	gp_state: win32.XINPUT_STATE
	if win32.XInputGetState(win32.XUSER(gamepad), &gp_state) == .SUCCESS {
		gp := gp_state.Gamepad

		// Numbers from https://learn.microsoft.com/en-us/windows/win32/api/xinput/ns-xinput-xinput_gamepad
		STICK_MAX   :: 32767
		TRIGGER_MAX :: 255

		switch axis {
		case .Left_Stick_X: return f32(gp.sThumbLX) / STICK_MAX
		case .Left_Stick_Y: return -f32(gp.sThumbLY) / STICK_MAX
		case .Right_Stick_X: return f32(gp.sThumbRX) / STICK_MAX
		case .Right_Stick_Y: return -f32(gp.sThumbRY) / STICK_MAX
		case .Left_Trigger: return f32(gp.bLeftTrigger) / TRIGGER_MAX
		case .Right_Trigger: return f32(gp.bRightTrigger) / TRIGGER_MAX
		}
	}

	return 0
}

win32_set_gamepad_vibration :: proc(gamepad: int, left: f32, right: f32) {
	if gamepad < 0 || gamepad >= MAX_GAMEPADS {
		return
	}

	vib := win32.XINPUT_VIBRATION {
		wLeftMotorSpeed = win32.WORD(left * 65535),
		wRightMotorSpeed = win32.WORD(right * 65535),
	}

	win32.XInputSetState(win32.XUSER(gamepad), &vib)
}

win32_set_internal_state :: proc(state: rawptr) {
	assert(state != nil)
	s = (^Win32_State)(state)
}

Win32_State :: struct {
	allocator: runtime.Allocator,
	custom_context: runtime.Context,
	hwnd: win32.HWND,
	flags: Window_Flags,
	width: int,
	height: int,
	events: [dynamic]Window_Event,
}

style_from_flags :: proc(flags: Window_Flags) -> win32.DWORD {
	style := win32.WS_OVERLAPPED | win32.WS_CAPTION | win32.WS_SYSMENU |
	         win32.WS_MINIMIZEBOX | win32.WS_MAXIMIZEBOX | win32.WS_VISIBLE |
	         win32.CS_OWNDC

	if .Resizable in flags {
		style |= win32.WS_THICKFRAME
	}

	return style
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
		key := key_from_event_params(wparam, lparam)
		append(&s.events, Window_Event_Key_Went_Down {
			key = key,
		})

		return 0

	case win32.WM_KEYUP:
		key := key_from_event_params(wparam, lparam)
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

	case win32.WM_LBUTTONDOWN:
		append(&s.events, Window_Event_Mouse_Button_Went_Down {
			button = .Left,
		})

	case win32.WM_LBUTTONUP:
		append(&s.events, Window_Event_Mouse_Button_Went_Up {
			button = .Left,
		})

	case win32.WM_MBUTTONDOWN:
		append(&s.events, Window_Event_Mouse_Button_Went_Down {
			button = .Middle,
		})

	case win32.WM_MBUTTONUP:
		append(&s.events, Window_Event_Mouse_Button_Went_Up {
			button = .Middle,
		})

	case win32.WM_RBUTTONDOWN:
		append(&s.events, Window_Event_Mouse_Button_Went_Down {
			button = .Right,
		})

	case win32.WM_RBUTTONUP:
		append(&s.events, Window_Event_Mouse_Button_Went_Up {
			button = .Right,
		})

	case win32.WM_SIZE:
		width := win32.LOWORD(lparam)
		height := win32.HIWORD(lparam)

		s.width = int(width)
		s.height = int(height)

		append(&s.events, Window_Event_Resize {
			width = int(width),
			height = int(height),
		})
	}

	return win32.DefWindowProcW(hwnd, msg, wparam, lparam)
}

key_from_event_params :: proc(wparam: win32.WPARAM, lparam: win32.LPARAM) -> Keyboard_Key{
	if wparam == win32.VK_RETURN && win32.HIWORD(lparam) & win32.KF_EXTENDED != 0 {
		return .NP_Enter
	}

	return WIN32_VK_MAP[wparam]
}

WIN32_VK_MAP := [255]Keyboard_Key {
	win32.VK_0 = .N0,
	win32.VK_1 = .N1,
	win32.VK_2 = .N2,
	win32.VK_3 = .N3,
	win32.VK_4 = .N4,
	win32.VK_5 = .N5,
	win32.VK_6 = .N6,
	win32.VK_7 = .N7,
	win32.VK_8 = .N8,
	win32.VK_9 = .N9,

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

	win32.VK_OEM_7      = .Apostrophe,
	win32.VK_OEM_COMMA  = .Comma,
	win32.VK_OEM_MINUS  = .Minus,
	win32.VK_OEM_PERIOD = .Period,
	win32.VK_OEM_2      = .Slash,
	win32.VK_OEM_1      = .Semicolon,
	win32.VK_OEM_PLUS   = .Equal,
	win32.VK_OEM_4      = .Left_Bracket,
	win32.VK_OEM_5      = .Backslash,
	win32.VK_OEM_6      = .Right_Bracket,
	win32.VK_OEM_3      = .Backtick,

	win32.VK_SPACE   = .Space,
	win32.VK_ESCAPE  = .Escape,
	win32.VK_RETURN  = .Enter,
	win32.VK_TAB     = .Tab,
	win32.VK_BACK    = .Backspace,
	win32.VK_INSERT  = .Insert,
	win32.VK_DELETE  = .Delete,
	win32.VK_RIGHT   = .Right,
	win32.VK_LEFT    = .Left,
	win32.VK_DOWN    = .Down,
	win32.VK_UP      = .Up,
	win32.VK_PRIOR   = .Page_Up,
	win32.VK_NEXT    = .Page_Down,
	win32.VK_HOME    = .Home,
	win32.VK_END     = .End,
	win32.VK_CAPITAL = .Caps_Lock,
	win32.VK_SCROLL  = .Scroll_Lock,
	win32.VK_NUMLOCK = .Num_Lock,
	win32.VK_PRINT   = .Print_Screen,
	win32.VK_PAUSE   = .Pause,

	win32.VK_F1  = .F1,
	win32.VK_F2  = .F2,
	win32.VK_F3  = .F3,
	win32.VK_F4  = .F4,
	win32.VK_F5  = .F5,
	win32.VK_F6  = .F6,
	win32.VK_F7  = .F7,
	win32.VK_F8  = .F8,
	win32.VK_F9  = .F9,
	win32.VK_F10 = .F10,
	win32.VK_F11 = .F11,
	win32.VK_F12 = .F12,

	win32.VK_LSHIFT   = .Left_Shift,
	win32.VK_LCONTROL = .Left_Control,
	win32.VK_LMENU    = .Left_Alt,
	win32.VK_MENU     = .Left_Alt,
	win32.VK_LWIN     = .Left_Super,
	win32.VK_RSHIFT   = .Right_Shift,
	win32.VK_RCONTROL = .Right_Control,
	win32.VK_RMENU    = .Right_Alt,
	win32.VK_RWIN     = .Right_Super,
	win32.VK_APPS     = .Menu,

	win32.VK_NUMPAD0 = .NP_0,
	win32.VK_NUMPAD1 = .NP_1,
	win32.VK_NUMPAD2 = .NP_2,
	win32.VK_NUMPAD3 = .NP_3,
	win32.VK_NUMPAD4 = .NP_4,
	win32.VK_NUMPAD5 = .NP_5,
	win32.VK_NUMPAD6 = .NP_6,
	win32.VK_NUMPAD7 = .NP_7,
	win32.VK_NUMPAD8 = .NP_8,
	win32.VK_NUMPAD9 = .NP_9,
	
	win32.VK_DECIMAL = .NP_Decimal,
	win32.VK_DIVIDE  = .NP_Divide,
	win32.VK_MULTIPLY = .NP_Multiply,
	win32.VK_SUBTRACT = .NP_Subtract,
	win32.VK_ADD = .NP_Add,

	// NP_Enter is handled separately

	win32.VK_OEM_NEC_EQUAL = .NP_Equal,
}