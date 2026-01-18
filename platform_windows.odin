#+build windows
#+private file

package karl2d

@(private="package")
PLATFORM_WINDOWS :: Platform_Interface {
	state_size = windows_state_size,
	init = windows_init,
	shutdown = windows_shutdown,
	get_window_render_glue = windows_get_window_render_glue,
	get_events = windows_get_events,
	get_width = windows_get_width,
	get_height = windows_get_height,
	set_position = windows_set_position,
	set_size = windows_set_size,
	get_window_scale = windows_get_window_scale,
	set_window_mode = windows_set_window_mode,

	is_gamepad_active = windows_is_gamepad_active,
	get_gamepad_axis = windows_get_gamepad_axis,
	set_gamepad_vibration = windows_set_gamepad_vibration,

	set_internal_state = windows_set_internal_state,
}

import win32 "core:sys/windows"
import "base:runtime"
@require import "log"


windows_state_size :: proc() -> int {
	return size_of(Windows_State)
}

windows_init :: proc(
	window_state: rawptr,
	screen_width: int,
	screen_height: int,
	window_title: string,
	options: Init_Options,
	allocator: runtime.Allocator,
) {
	assert(window_state != nil)
	s = (^Windows_State)(window_state)
	s.allocator = allocator
	s.width = screen_width
	s.height = screen_height
	s.events = make([dynamic]Event, allocator = allocator)
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

	initial_rect := win32.RECT {
		0,
		0,
		i32(screen_width),
		i32(screen_height),
	}

	dpix, dpiy: win32.UINT
	win32.GetDpiForMonitor(win32.MonitorFromWindow(nil, .MONITOR_DEFAULTTOPRIMARY), {}, &dpix, &dpiy)
	win32.AdjustWindowRectExForDpi(&initial_rect, windows_get_style(options.window_mode), false, {}, dpix)

	// We create a window with default position and size. We set the correct size in
	// `windows_set_window_mode`.
	s.hwnd = win32.CreateWindowW(
		CLASS_NAME,
		win32.utf8_to_wstring(window_title),
		win32.WS_VISIBLE,
		win32.CW_USEDEFAULT, win32.CW_USEDEFAULT,
		i32(initial_rect.right - initial_rect.left),
		i32(initial_rect.bottom - initial_rect.top),
		nil, nil, instance, nil,
	)
	assert(s.hwnd != nil, "Failed creating window")

	windows_set_window_mode(options.window_mode)
	
	win32.XInputEnable(true)

	when RENDER_BACKEND_NAME == "d3d11" {
		s.window_render_glue = {
			state = (^Window_Render_Glue_State)(s.hwnd),
		}
	} else when RENDER_BACKEND_NAME == "gl" {
		s.window_render_glue = make_windows_gl_glue(s.hwnd, s.allocator)
	}  else when RENDER_BACKEND_NAME == "nil" {
		s.window_render_glue = {}
	} else {
		#panic("Unsupported combo of Windows platform and render backend '" + RENDER_BACKEND_NAME + "'")
	}
}

windows_shutdown :: proc() {
	win32.DestroyWindow(s.hwnd)
	delete(s.events)
}

windows_get_window_render_glue :: proc() -> Window_Render_Glue {
	return s.window_render_glue
}

windows_get_events :: proc(events: ^[dynamic]Event) {
	msg: win32.MSG

	// This loop will call `window_proc` which will add more things to `frame_events`.
	for win32.PeekMessageW(&msg, nil, 0, 0, win32.PM_REMOVE) {
		win32.TranslateMessage(&msg)
		win32.DispatchMessageW(&msg)
	}

	// 4 is the limit set by microsoft, not by us. So I'm not using MAX_GAMEPADS here.
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
			evt: Event

			if .KEYDOWN in gp_event.Flags {
				evt = Event_Gamepad_Button_Went_Down {
					gamepad = gamepad,
					button = b,
				}
			} else if .KEYUP in gp_event.Flags {
				evt = Event_Gamepad_Button_Went_Up {
					gamepad = gamepad,
					button = b,
				}
			}

			if evt != nil {
				append(&s.events, evt)
			}
		}
	}

	append(events, ..s.events[:])
	runtime.clear(&s.events)
}

windows_get_width :: proc() -> int {
	return s.width
}

windows_get_height :: proc() -> int {
	return s.height
}

// Because positions can be offset in Windows: There is an "inivisble border" on Windows. This makes
// windows end up at slight offset positions. For example, if you set a window to be at (0, 0), then
// it won't be at (0, 0) unless you add this offset.
windows_get_window_offset :: proc() -> (x, y: i32) {
	real_r: win32.RECT
	win32.DwmGetWindowAttribute(s.hwnd, u32(win32.DWMWINDOWATTRIBUTE.DWMWA_EXTENDED_FRAME_BOUNDS), &real_r, size_of(win32.RECT))

	r: win32.RECT
	win32.GetWindowRect(s.hwnd, &r)

	return real_r.left - r.left, real_r.top - r.top
}

windows_set_position :: proc(x: int, y: int) {
	offx, offy := windows_get_window_offset()

	win32.SetWindowPos(
		s.hwnd,
		{},
		i32(x) - offx,
		i32(y) - offy,
		0,
		0,
		win32.SWP_NOACTIVATE | win32.SWP_NOZORDER | win32.SWP_NOSIZE,
	)
}

windows_get_style :: proc(window_mode: Window_Mode) -> win32.DWORD {
	style: win32.DWORD

	switch s.window_mode {
	case .Windowed:
		style = win32.WS_OVERLAPPED |
	            win32.WS_CAPTION |
	            win32.WS_SYSMENU |
	            win32.WS_MINIMIZEBOX |
	            win32.WS_VISIBLE

	case .Windowed_Resizable:
		style = win32.WS_OVERLAPPED |
	            win32.WS_CAPTION |
	            win32.WS_SYSMENU |
	            win32.WS_MINIMIZEBOX |
	            win32.WS_VISIBLE |
	            win32.WS_THICKFRAME |
	            win32.WS_MAXIMIZEBOX

	case .Borderless_Fullscreen:
		style = win32.WS_VISIBLE
	}

	return style
}

windows_set_size :: proc(w, h: int) {
	s.width = w
	s.height = h

	r: win32.RECT
	r.left = 0
	r.top = 0
	r.right = i32(w)
	r.bottom = i32(h)

	win32.AdjustWindowRectExForDpi(&r, windows_get_style(s.window_mode), false, 0, win32.GetDpiForWindow(s.hwnd))
	win32.SetWindowPos(
		s.hwnd,
		{},
		0,
		0,
		r.right - r.left,
		r.bottom - r.top,
		win32.SWP_NOACTIVATE | win32.SWP_NOZORDER | win32.SWP_NOMOVE,
	)
}

windows_get_window_scale :: proc() -> f32 {
	return f32(win32.GetDpiForWindow(s.hwnd))/96.0
}

windows_is_gamepad_active :: proc(gamepad: int) -> bool {
	if gamepad < 0 || gamepad >= MAX_GAMEPADS {
		return false
	}

	gp_state: win32.XINPUT_STATE
	return win32.XInputGetState(win32.XUSER(gamepad), &gp_state) == .SUCCESS
}

windows_get_gamepad_axis :: proc(gamepad: int, axis: Gamepad_Axis) -> f32 {
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

windows_set_gamepad_vibration :: proc(gamepad: int, left: f32, right: f32) {
	if gamepad < 0 || gamepad >= MAX_GAMEPADS {
		return
	}

	vib := win32.XINPUT_VIBRATION {
		wLeftMotorSpeed = win32.WORD(left * 65535),
		wRightMotorSpeed = win32.WORD(right * 65535),
	}

	win32.XInputSetState(win32.XUSER(gamepad), &vib)
}

windows_set_internal_state :: proc(state: rawptr) {
	assert(state != nil)
	s = (^Windows_State)(state)
}

Windows_State :: struct {
	allocator: runtime.Allocator,
	custom_context: runtime.Context,
	hwnd: win32.HWND,
	window_mode: Window_Mode,

	width: int,
	height: int,

	in_resize_move_state: bool,
	width_before_resize_move: int,
	height_before_resize_move: int,

	events: [dynamic]Event,

	// for when returning from fullscreen to window mode
	restore_pos_x: int,
	restore_pos_y: int,
	restore_width: int,
	restore_height: int,

	window_render_glue: Window_Render_Glue,
}

windows_set_window_mode :: proc(window_mode: Window_Mode) {
	old_window_mode := s.window_mode
	s.window_mode = window_mode
	style := windows_get_style(window_mode)
	win32.SetWindowLongW(s.hwnd, win32.GWL_STYLE, i32(style))

	switch window_mode {
	case .Windowed, .Windowed_Resizable:
		r: win32.RECT
		set_window_pos_style: win32.DWORD = win32.SWP_NOACTIVATE | win32.SWP_NOZORDER

		if old_window_mode == .Borderless_Fullscreen {
			r.left = i32(s.restore_pos_x)
			r.top = i32(s.restore_pos_y)
			r.right = r.left + i32(s.restore_width)
			r.bottom = r.top + i32(s.restore_height)
		} else {
			r.left = 0
			r.top = 0
			r.right = i32(s.width)
			r.bottom = i32(s.height)
			set_window_pos_style |= win32.SWP_NOMOVE
		}

		win32.AdjustWindowRectExForDpi(&r, style, false, 0, win32.GetDpiForWindow(s.hwnd))

		win32.SetWindowPos(
			s.hwnd,
			{},
			i32(r.left),
			i32(r.top),
			i32(r.right - r.left),
			i32(r.bottom - r.top),
			set_window_pos_style,
		)

	case .Borderless_Fullscreen:
		mi := win32.MONITORINFO { cbSize = size_of (win32.MONITORINFO)}
		mon := win32.MonitorFromWindow(s.hwnd, .MONITOR_DEFAULTTONEAREST)

		if win32.GetMonitorInfoW(mon, &mi) {
			win32.SetWindowPos(s.hwnd, win32.HWND_TOP,
			mi.rcMonitor.left, mi.rcMonitor.top,
			mi.rcMonitor.right - mi.rcMonitor.left,
			mi.rcMonitor.bottom - mi.rcMonitor.top,
			win32.SWP_NOOWNERZORDER | win32.SWP_FRAMECHANGED)
		}
	}
}

s: ^Windows_State

window_proc :: proc "stdcall" (hwnd: win32.HWND, msg: win32.UINT, wparam: win32.WPARAM, lparam: win32.LPARAM) -> win32.LRESULT {
	context = s.custom_context

	switch msg {
	case win32.WM_DESTROY:
		win32.PostQuitMessage(0)

	case win32.WM_CLOSE:
		append(&s.events, Event_Close_Window_Requested{})

	case win32.WM_SYSKEYDOWN, win32.WM_KEYDOWN:
		repeat := bool(lparam & (1 << 30))

		if !repeat {
			key := key_from_event_params(wparam, lparam)

			if key != .None {
				append(&s.events, Event_Key_Went_Down {
					key = key,
				})
			}
		}

	case win32.WM_SYSKEYUP, win32.WM_KEYUP:
		key := key_from_event_params(wparam, lparam)
		if key != .None {
			append(&s.events, Event_Key_Went_Up {
				key = key,
			})
		}

	case win32.WM_MOUSEMOVE:
		x := win32.GET_X_LPARAM(lparam)
		y := win32.GET_Y_LPARAM(lparam)
		append(&s.events, Event_Mouse_Move {
			position = {f32(x), f32(y)},
		})

	case win32.WM_MOUSEWHEEL:
		delta := f32(win32.GET_WHEEL_DELTA_WPARAM(wparam))/win32.WHEEL_DELTA

		append(&s.events, Event_Mouse_Wheel {
			delta = delta,
		})

	case win32.WM_LBUTTONDOWN:
		append(&s.events, Event_Mouse_Button_Went_Down {
			button = .Left,
		})
		win32.SetCapture(s.hwnd)

	case win32.WM_LBUTTONUP:
		append(&s.events, Event_Mouse_Button_Went_Up {
			button = .Left,
		})
		win32.ReleaseCapture()

	case win32.WM_MBUTTONDOWN:
		append(&s.events, Event_Mouse_Button_Went_Down {
			button = .Middle,
		})
		win32.SetCapture(s.hwnd)

	case win32.WM_MBUTTONUP:
		append(&s.events, Event_Mouse_Button_Went_Up {
			button = .Middle,
		})
		win32.ReleaseCapture()

	case win32.WM_RBUTTONDOWN:
		append(&s.events, Event_Mouse_Button_Went_Down {
			button = .Right,
		})
		win32.SetCapture(s.hwnd)

	case win32.WM_RBUTTONUP:
		append(&s.events, Event_Mouse_Button_Went_Up {
			button = .Right,
		})
		win32.ReleaseCapture()

	case win32.WM_MOVE:
		if s.window_mode == .Windowed || s.window_mode == .Windowed_Resizable {
			x := win32.LOWORD(lparam)
			y := win32.HIWORD(lparam)

			s.restore_pos_x = int(x)
			s.restore_pos_y = int(y)
		}

	case win32.WM_DPICHANGED:
		// Set the window mode again so everything is correct size after DPI change.
		windows_set_window_mode(s.window_mode)

		append(&s.events, Event_Window_Scale_Changed {
			scale = windows_get_window_scale(),
		})

	case win32.WM_ENTERSIZEMOVE:
		s.in_resize_move_state = true
		s.width_before_resize_move = s.width
		s.height_before_resize_move = s.height

	case win32.WM_EXITSIZEMOVE:
		s.in_resize_move_state = false

		if s.width_before_resize_move != s.width || s.height_before_resize_move != s.height {
			append(&s.events, Event_Resize {
				width = s.width,
				height = s.height,
			})
		}

	case win32.WM_SIZE:
		width := win32.LOWORD(lparam)
		height := win32.HIWORD(lparam)

		s.width = int(width)
		s.height = int(height)

		if s.window_mode == .Windowed || s.window_mode == .Windowed_Resizable {
			s.restore_width = s.width
			s.restore_height = s.height
		}

		// We are actively resizing or moving the window, we'll save the event for later so it does
		// not get spammy.
		if !s.in_resize_move_state {
			append(&s.events, Event_Resize {
				width = int(width),
				height = int(height),
			})
		}

	case win32.WM_SETFOCUS:
		append(&s.events, Event_Window_Focused {})

	case win32.WM_KILLFOCUS:
		append(&s.events, Event_Window_Unfocused {})
	}


	return win32.DefWindowProcW(hwnd, msg, wparam, lparam)
}

key_from_event_params :: proc(wparam: win32.WPARAM, lparam: win32.LPARAM) -> Keyboard_Key{
	switch wparam {
	case win32.VK_SHIFT:
    	scancode := (lparam & 0x00ff0000) >> 16
    	new_vk := win32.MapVirtualKeyW(u32(scancode), win32.MAPVK_VSC_TO_VK_EX)
		return new_vk == win32.VK_LSHIFT ? .Left_Shift : .Right_Shift

	case win32.VK_CONTROL:
		is_right := win32.HIWORD(lparam) & win32.KF_EXTENDED != 0
		return is_right ? .Right_Control : .Left_Control

	case win32.VK_MENU:
		is_right := win32.HIWORD(lparam) & win32.KF_EXTENDED != 0
		return is_right ? .Right_Alt : .Left_Alt

	case win32.VK_RETURN:
		if win32.HIWORD(lparam) & win32.KF_EXTENDED != 0 {
			return .NP_Enter
		}
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

	// Alt, shift and control are handled in key_from_event_params
	win32.VK_LWIN     = .Left_Super,
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