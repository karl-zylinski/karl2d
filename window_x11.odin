#+build linux
#+private file

package karl2d

@(private="package")
WINDOW_INTERFACE_X11 :: Window_Interface {
	state_size = x11_state_size,
	init = x11_init,
	shutdown = x11_shutdown,
	window_handle = x11_window_handle,
	process_events = x11_process_events,
	get_events = x11_get_events,
	get_width = x11_get_width,
	get_height = x11_get_height,
	clear_events = x11_clear_events,
	set_position = x11_set_position,
	set_size = x11_set_size,
	get_window_scale = x11_get_window_scale,
	set_window_mode = x11_set_window_mode,
	is_gamepad_active = x11_is_gamepad_active,
	get_gamepad_axis = x11_get_gamepad_axis,
	set_gamepad_vibration = x11_set_gamepad_vibration,

	set_internal_state = x11_set_internal_state,
}

import X "vendor:x11/xlib"
import "base:runtime"
import "core:log"
import "core:fmt"

_ :: log
_ :: fmt

x11_state_size :: proc() -> int {
	return size_of(X11_State)
}

x11_init :: proc(
	window_state: rawptr,
	window_width: int,
	window_height: int,
	window_title: string,
	init_options: Init_Options,
	allocator: runtime.Allocator,
) {
	s = (^X11_State)(window_state)
	s.allocator = allocator
	s.windowed_width = window_width
	s.windowed_height = window_height
	s.display = X.OpenDisplay(nil)

	s.window = X.CreateSimpleWindow(
		s.display,
		X.DefaultRootWindow(s.display),
		0, 0,
		u32(window_width), u32(window_height),
		0,
		0,
		0,
	)

	X.StoreName(s.display, s.window, frame_cstring(window_title))
	
	X.SelectInput(s.display, s.window, {
		.KeyPress,
		.KeyRelease,
		.ButtonPress,
		.ButtonRelease,
		.PointerMotion,
		.StructureNotify,
		.FocusChange,
	})

	X.MapWindow(s.display, s.window)

	s.delete_msg = X.InternAtom(s.display, "WM_DELETE_WINDOW", false)
	X.SetWMProtocols(s.display, s.window, &s.delete_msg, 1)

	s.window_handle = {
		display = s.display,
		screen = X.DefaultScreen(s.display),
		window = s.window,
	}

	x11_set_window_mode(init_options.window_mode)
}

x11_shutdown :: proc() {
	delete(s.events)
	X.DestroyWindow(s.display, s.window)
}

x11_window_handle :: proc() -> Window_Handle {
	return Window_Handle(&s.window_handle)
}

x11_process_events :: proc() {
	for X.Pending(s.display) > 0 {
		event: X.XEvent
		X.NextEvent(s.display, &event)

		#partial switch event.type {
		case .ClientMessage:
			if X.Atom(event.xclient.data.l[0]) == s.delete_msg {
				append(&s.events, Window_Event_Close_Wanted{})
			}
		case .KeyPress:
			key := key_from_xkeycode(event.xkey.keycode)

			if key != .None {
				append(&s.events, Window_Event_Key_Went_Down {
					key = key,
				})
			}

		case .KeyRelease:
			key := key_from_xkeycode(event.xkey.keycode)

			if key != .None {
				append(&s.events, Window_Event_Key_Went_Up {
					key = key,
				})
			}

		case .ButtonPress:
			btn: Mouse_Button

			switch event.xbutton.button {
			case .Button1: btn = .Left
			case .Button2: btn = .Middle
			case .Button3: btn = .Right
			case .Button4: btn = Mouse_Button(3)
			case .Button5: btn = Mouse_Button(4)
			}

			append(&s.events, Window_Event_Mouse_Button_Went_Down {
				button = btn,
			})

		case .ButtonRelease:
			btn: Mouse_Button

			switch event.xbutton.button {
			case .Button1: btn = .Left
			case .Button2: btn = .Middle
			case .Button3: btn = .Right
			case .Button4: btn = Mouse_Button(3)
			case .Button5: btn = Mouse_Button(4)
			}

			append(&s.events, Window_Event_Mouse_Button_Went_Up {
				button = btn,
			})

		case .MotionNotify:
			append(&s.events, Window_Event_Mouse_Move {
				position = { f32(event.xmotion.x), f32(event.xmotion.y) }, 
			})

		case .ConfigureNotify:
			w := int(event.xconfigure.width)
			h := int(event.xconfigure.height)

			if w != s.width || h != s.height {
				s.width = w
				s.height = h

				if s.window_mode == .Windowed || s.window_mode == .Windowed_Resizable {
					s.windowed_width = w
					s.windowed_height = h
				}

				append(&s.events, Window_Event_Resize {
					width = w,
					height = h,
				})
			}
		case .FocusIn:
			append(&s.events, Window_Event_Focused{})

		case .FocusOut:
			append(&s.events, Window_Event_Unfocused{})
		}
	}
}

@rodata
KEY_FROM_XKEYCODE := [255]Keyboard_Key {
	8 = .Space,
	9 = .Escape,
	10 = .N1,
	11 = .N2,
	12 = .N3,
	13 = .N4,
	14 = .N5,
	15 = .N6,
	16 = .N7,
	17 = .N8,
	18 = .N9,
	19 = .N0,
	20 = .Minus,
	21 = .Equal,
	22 = .Backspace,
	23 = .Tab,
	24 = .Q,
	25 = .W,
	26 = .E,
	27 = .R,
	28 = .T,
	29 = .Y,
	30 = .U,
	31 = .I,
	32 = .O,
	33 = .P,
	34 = .Left_Bracket,
	35 = .Right_Bracket,
	36 = .Enter,
	37 = .Left_Control,
	38 = .A,
	39 = .S,
	40 = .D,
	41 = .F,
	42 = .G,
	43 = .H,
	44 = .J,
	45 = .K,
	46 = .L,
	47 = .Semicolon,
	48 = .Apostrophe,
	49 = .Backtick,
	50 = .Left_Shift,
	51 = .Backslash,
	52 = .Z,
	53 = .X,
	54 = .C,
	55 = .V,
	56 = .B,
	57 = .N,
	58 = .M,
	59 = .Comma,
	60 = .Period,
	61 = .Slash,
	62 = .Right_Shift,
	63 = .NP_Multiply,
	64 = .Left_Alt,
	65 = .Space,
	66 = .Caps_Lock,
	67 = .F1,
	68 = .F2,
	69 = .F3,
	70 = .F4,
	71 = .F5,
	72 = .F6,
	73 = .F7,
	74 = .F8,
	75 = .F9,
	76 = .F10,
	77 = .Num_Lock,
	78 = .Scroll_Lock,
	82 = .NP_Subtract,
	86 = .NP_Add,
	95 = .F11,
	96 = .F12,
	104 = .NP_Enter,
	105 = .Right_Control,
	106 = .NP_Divide,
	107 = .Print_Screen,
	108 = .Right_Alt,
	110 = .Home,
	111 = .Up,
	112 = .Page_Up,
	113 = .Left,
	114 = .Right,
	115 = .End,
	116 = .Down,
	117 = .Page_Down,
	118 = .Insert,
	119 = .Delete,
	125 = .NP_Equal,
	127 = .Pause,
	129 = .NP_Decimal,
	133 = .Left_Super,
	134 = .Right_Super,
	135 = .Menu,
}

key_from_xkeycode :: proc(kc: u32) -> Keyboard_Key {
	if kc >= 255 {
		return .None
	}

	return KEY_FROM_XKEYCODE[u8(kc)]
}

x11_get_events :: proc() -> []Window_Event {
	return s.events[:]
}

x11_get_width :: proc() -> int {
	return s.width
}

x11_get_height :: proc() -> int {
	return s.height
}

x11_clear_events :: proc() {
	runtime.clear(&s.events)
}

x11_set_position :: proc(x: int, y: int) {
	X.MoveWindow(s.display, s.window, i32(x), i32(y))
}

x11_set_size :: proc(w, h: int) {
	X.ResizeWindow(s.display, s.window, u32(w), u32(h))
}

x11_get_window_scale :: proc() -> f32 {
	return 1
}

enter_borderless_fullscreen :: proc() {

	wm_state := X.InternAtom(s.display, "_NET_WM_STATE", true)
	wm_fullscreen := X.InternAtom(s.display, "_NET_WM_STATE_FULLSCREEN", true)

	go_to_fullscreen := X.XEvent {
		xclient = {
			type = .ClientMessage,
			window = s.window,
			message_type = wm_state,
			format = 32,
			data = {
				l = {
					0 = 1,
					1 = int(wm_fullscreen),
					2 = 0,
					3 = 1,
					4 = 0,
				},
			},
		},
	}

	X.SendEvent(s.display, X.DefaultRootWindow(s.display), false, {.SubstructureNotify, .SubstructureRedirect}, &go_to_fullscreen)
}

leave_borderless_fullscreen :: proc() {
	X.ResizeWindow(s.display, s.window, u32(s.windowed_width), u32(s.windowed_height))
	s.width = s.windowed_width
	s.height = s.windowed_height

	wm_state := X.InternAtom(s.display, "_NET_WM_STATE", true)
	wm_fullscreen := X.InternAtom(s.display, "_NET_WM_STATE_FULLSCREEN", true)


	exit_fullscreen := X.XEvent {
		xclient = {
			type = .ClientMessage,
			window = s.window,
			message_type = wm_state,
			format = 32,
			data = {
				l = {
					0 = 0,
					1 = int(wm_fullscreen),
					2 = 0,
					3 = 1,
					4 = 0,
				},
			},
		},
	}

	X.SendEvent(s.display, X.DefaultRootWindow(s.display), false, {.SubstructureNotify, .SubstructureRedirect}, &exit_fullscreen)
}

x11_set_window_mode :: proc(window_mode: Window_Mode) {
	if window_mode == s.window_mode {
		return
	}

	switch window_mode {
	case .Windowed:
		if s.window_mode == .Borderless_Fullscreen {
			leave_borderless_fullscreen()
		}

		hints := X.XSizeHints {
			flags = { .PMinSize, .PMaxSize },
			min_width = i32(s.width),
			max_width = i32(s.width),
			min_height = i32(s.height),
			max_height = i32(s.height),
		}

		X.SetWMNormalHints(s.display, s.window, &hints)

	case .Windowed_Resizable: 
		if s.window_mode == .Borderless_Fullscreen {
			leave_borderless_fullscreen()
		}

		hints := X.XSizeHints {
			flags = {.USSize},
		}

		X.SetWMNormalHints(s.display, s.window, &hints)
	case .Borderless_Fullscreen:
		enter_borderless_fullscreen()
	}

	s.window_mode = window_mode
}

x11_is_gamepad_active :: proc(gamepad: int) -> bool {
	if gamepad < 0 || gamepad >= MAX_GAMEPADS {
		return false
	}

	return false
}

x11_get_gamepad_axis :: proc(gamepad: int, axis: Gamepad_Axis) -> f32 {
	if gamepad < 0 || gamepad >= MAX_GAMEPADS {
		return 0
	}

	return 0
}

x11_set_gamepad_vibration :: proc(gamepad: int, left: f32, right: f32) {
	if gamepad < 0 || gamepad >= MAX_GAMEPADS {
		return
	}
}

x11_set_internal_state :: proc(state: rawptr) {
	assert(state != nil)
	s = (^X11_State)(state)
}

X11_State :: struct {
	allocator: runtime.Allocator,
	width: int,
	height: int,
	windowed_width: int,
	windowed_height: int,
	events: [dynamic]Window_Event,
	display: ^X.Display,
	window: X.Window,
	window_handle: Window_Handle_Linux,
	delete_msg: X.Atom,
	window_mode: Window_Mode,
}

s: ^X11_State

@(private="package")
Window_Handle_Linux :: struct {
	display: ^X.Display,
	window: X.Window,
	screen: i32,
}