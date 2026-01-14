#+build linux
#+private file

package karl2d

@(private="package")
LINUX_WINDOW_X11 :: Linux_Window_Interface {
	state_size = x11_state_size,
	init = x11_init,
	shutdown = x11_shutdown,
	get_window_render_glue = x11_get_window_render_glue,
	after_frame_present = x11_after_frame_present,
	get_events = x11_get_events,
	get_width = x11_get_width,
	get_height = x11_get_height,
	set_position = x11_set_position,
	set_size = x11_set_size,
	get_window_scale = x11_get_window_scale,
	set_window_mode = x11_set_window_mode,
	set_internal_state = x11_set_internal_state,
}

import X "vendor:x11/xlib"
import "base:runtime"
import "log"
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

	x11_set_window_mode(init_options.window_mode)

	when RENDER_BACKEND_NAME == "gl" {
		s.window_render_glue = make_linux_gl_x11_glue(s.display, s.window, s.allocator)
	} else when RENDER_BACKEND_NAME == "nil" {
		s.window_render_glue = {}
	} else {
		#panic("Unsupported combo of Linux + X11 and render backend '" + RENDER_BACKEND_NAME + "'")
	}
}

x11_shutdown :: proc() {
	X.DestroyWindow(s.display, s.window)
}

x11_get_window_render_glue :: proc() -> Window_Render_Glue {
	return s.window_render_glue
}

x11_after_frame_present :: proc() {
	
}

x11_get_events :: proc(events: ^[dynamic]Event) {
	for X.Pending(s.display) > 0 {
		event: X.XEvent
		X.NextEvent(s.display, &event)

		#partial switch event.type {
		case .ClientMessage:
			if X.Atom(event.xclient.data.l[0]) == s.delete_msg {
				append(events, Event_Close_Window_Requested{})
			}
		case .KeyPress:
			key := key_from_xkeycode(event.xkey.keycode)

			if key != .None {
				append(events, Event_Key_Went_Down {
					key = key,
				})
			}

		case .KeyRelease:
			key := key_from_xkeycode(event.xkey.keycode)

			if key != .None {
				append(events, Event_Key_Went_Up {
					key = key,
				})
			}

		case .ButtonPress:
			if event.xbutton.button <= .Button3 {
				btn: Mouse_Button

				#partial switch event.xbutton.button {
				case .Button1: btn = .Left
				case .Button2: btn = .Middle
				case .Button3: btn = .Right
				}

				append(events, Event_Mouse_Button_Went_Down {
					button = btn,
				})
			} else if event.xbutton.button <= .Button5 {
				// LOL X11!!! Mouse wheel is button 4 and 5 being pressed.

				append(events, Event_Mouse_Wheel {
					event.xbutton.button == .Button4 ? -1 : 1,
				})
			}

		case .ButtonRelease:
			if event.xbutton.button <= .Button3 {
				btn: Mouse_Button

				#partial switch event.xbutton.button {
				case .Button1: btn = .Left
				case .Button2: btn = .Middle
				case .Button3: btn = .Right
				}

				append(events, Event_Mouse_Button_Went_Up {
					button = btn,
				})
			}

		case .MotionNotify:
			append(events, Event_Mouse_Move {
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

				append(events, Event_Resize {
					width = w,
					height = h,
				})
			}
		case .FocusIn:
			append(events, Event_Window_Focused{})

		case .FocusOut:
			append(events, Event_Window_Unfocused{})
		}
	}
}

x11_get_width :: proc() -> int {
	return s.width
}

x11_get_height :: proc() -> int {
	return s.height
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

	old_window_mode := s.window_mode
	s.window_mode = window_mode

	switch window_mode {
	case .Windowed:
		if old_window_mode == .Borderless_Fullscreen {
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
		if old_window_mode == .Borderless_Fullscreen {
			leave_borderless_fullscreen()
		}

		hints := X.XSizeHints {
			flags = {.USSize},
		}

		X.SetWMNormalHints(s.display, s.window, &hints)
	case .Borderless_Fullscreen:
		enter_borderless_fullscreen()
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
	display: ^X.Display,
	window: X.Window,
	delete_msg: X.Atom,
	window_mode: Window_Mode,
	window_render_glue: Window_Render_Glue,
}

s: ^X11_State

