#+build linux
#+private file

package karl2d

@(private="package")
LINUX_WINDOW_X11 :: Linux_Window_Interface {
	state_size = x11_state_size,
	init = x11_init,
	shutdown = x11_shutdown,
	get_window_render_glue = x11_get_window_render_glue,
	get_events = x11_get_events,
	set_title = x11_set_title,
	get_screen_width = x11_get_screen_width,
	get_screen_height = x11_get_screen_height,
	set_position = x11_set_position,
	set_screen_size = x11_set_screen_size,
	get_window_scale = x11_get_window_scale,
	set_window_mode = x11_set_window_mode,
	set_cursor_hidden = x11_set_cursor_hidden,
	is_cursor_hidden = x11_is_cursor_hidden,
	set_mouse_locked = x11_set_mouse_locked,
	is_mouse_locked = x11_is_mouse_locked,
	create_custom_cursor = x11_create_custom_cursor,
	set_cursor = x11_set_cursor,
	destroy_custom_cursor = x11_destroy_custom_cursor,
	set_internal_state = x11_set_internal_state,
}

import X "vendor:x11/xlib"
import "base:runtime"
import "log"
import "core:fmt"
import "core:slice"
import hm "core:container/handle_map"

_ :: log
_ :: fmt

x11_state_size :: proc() -> int {
	return size_of(X11_State)
}

x11_init :: proc(
	window_state: rawptr,
	screen_width: int,
	screen_height: int,
	window_title: string,
	init_options: Init_Options,
	allocator: runtime.Allocator,
) {
	s = (^X11_State)(window_state)
	s.allocator = allocator
	s.screen_width = screen_width
	s.screen_height = screen_height
	s.display = X.OpenDisplay(nil)
	s.events = make([dynamic]Event, allocator)
	hm.dynamic_init(&s.custom_cursors, allocator)

	s.window = X.CreateSimpleWindow(
		s.display,
		X.DefaultRootWindow(s.display),
		0, 0,
		u32(screen_width), u32(screen_height),
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

	// blank cursor for hiding it
	{
		blank_pixmap := X.CreatePixmap(s.display, s.window, 1, 1, 1)
		black: X.XColor

		// The binding for this proc is broken, so I fixed it locally.
		CreatePixmapCursor_Correct :: proc(
			display:   ^X.Display,
			source:    X.Pixmap,
			mask:      X.Pixmap,
			fg:        ^X.XColor,
			bg:        ^X.XColor,
			x:         u32,
			y:         u32,
		) -> X.Cursor

		binding := cast(CreatePixmapCursor_Correct)(X.CreatePixmapCursor)

		s.blank_cursor = binding(s.display, blank_pixmap, blank_pixmap, &black, &black, 0, 0)
		X.FreePixmap(s.display, blank_pixmap)
	}
	
	when RENDER_BACKEND_NAME == "gl" {
		s.window_render_glue = make_linux_gl_x11_glue(s.display, s.window, s.allocator)
	} else when RENDER_BACKEND_NAME == "nil" {
		s.window_render_glue = {}
	} else {
		#panic("Unsupported combo of Linux + X11 and render backend '" + RENDER_BACKEND_NAME + "'")
	}
}

x11_shutdown :: proc() {
	delete(s.events)

	for cached in s.standard_cursors {
		if cursor, ok := cached.?; ok && cursor != 0 {
			X.FreeCursor(s.display, cursor)
		}
	}

	for it := hm.dynamic_iterator_make(&s.custom_cursors); cd, _ in hm.dynamic_iterate(&it) {
		X.FreeCursor(s.display, cd.cursor)
	}
	hm.dynamic_destroy(&s.custom_cursors)

	X.FreeCursor(s.display, s.blank_cursor)
	X.DestroyWindow(s.display, s.window)
}

x11_get_window_render_glue :: proc() -> Window_Render_Glue {
	return s.window_render_glue
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
			if s.mouse_locked {
				cx := i32(s.screen_width / 2)
				cy := i32(s.screen_height / 2)

				if event.xmotion.x != cx || event.xmotion.y != cy {
					append(events, Event_Mouse_Move {
						position = {f32(event.xmotion.x), f32(event.xmotion.y)},
					})
					_x11_teleport_cursor_to_center()
				}
			} else {
				append(events, Event_Mouse_Move {
					position = {f32(event.xmotion.x), f32(event.xmotion.y)},
				})
			}

		case .ConfigureNotify:
			w := int(event.xconfigure.width)
			h := int(event.xconfigure.height)

			if w != s.last_configure_width || h != s.last_configure_height {
				s.last_configure_width = w
				s.last_configure_height = h

				if s.window_mode == .Windowed || s.window_mode == .Windowed_Resizable {
					s.last_configure_windowed_width = w
					s.last_configure_windowed_height = h
				}

				s.screen_width = w
				s.screen_height = h

				append(events, Event_Screen_Resize {
					width = w,
					height = h,
				})
			}
		case .FocusIn:
			append(events, Event_Window_Focused{})

		case .FocusOut:
			// X11 unlocks the mouse if program loses focus
			s.mouse_locked = false
			append(events, Event_Window_Unfocused{})
		}
	}

	append(events, ..s.events[:])
	runtime.clear(&s.events)
}

x11_set_title :: proc(title: string) {
	X.StoreName(s.display, s.window, frame_cstring(title))
}

x11_get_screen_width :: proc() -> int {
	return s.screen_width
}

x11_get_screen_height :: proc() -> int {
	return s.screen_height
}

x11_set_position :: proc(x: int, y: int) {
	X.MoveWindow(s.display, s.window, i32(x), i32(y))
}

x11_set_screen_size :: proc(w, h: int) {
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
	X.ResizeWindow(
		s.display,
		s.window,
		u32(s.last_configure_windowed_width),
		u32(s.last_configure_windowed_height),
	)
	s.screen_width = s.last_configure_windowed_width
	s.screen_height = s.last_configure_windowed_height

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
			min_width = i32(s.screen_width),
			max_width = i32(s.screen_width),
			min_height = i32(s.screen_height),
			max_height = i32(s.screen_height),
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

x11_set_cursor_hidden :: proc(hidden: bool) {
	s.cursor_hidden = hidden
	x11_apply_cursor()
}

// Applies s.cursor_hidden and s.current_cursor to the window. They all share the same underlying
// X11 state (whatever DefineCursor/UndefineCursor last set), so every entry point goes through
// this instead of touching it independently and clobbering the others.
x11_apply_cursor :: proc() {
	switch {
	case s.cursor_hidden:
		X.DefineCursor(s.display, s.window, s.blank_cursor)

	case:
		defined := false

		if c, is_custom := s.current_cursor.(Custom_Cursor); is_custom {
			if cd := hm.get(&s.custom_cursors, c); cd != nil {
				X.DefineCursor(s.display, s.window, cd.cursor)
				defined = true
			}
			// Otherwise it was destroyed while on screen; fall through to the default cursor.
		}

		if !defined {
			standard := Standard_Cursor.Default
			if sc, ok := s.current_cursor.(Standard_Cursor); ok {
				standard = sc
			}

			if theme_cursor := x11_standard_cursor(standard); theme_cursor != 0 {
				X.DefineCursor(s.display, s.window, theme_cursor)
			} else {
				// The theme has no cursor under either name, so let the window inherit whatever
				// its parent uses, which is normally the default arrow.
				X.UndefineCursor(s.display, s.window)
			}
		}
	}

	X.Flush(s.display)
}

// Loads a standard cursor out of the user's cursor theme, or returns 0 if the theme has no cursor
// for it.
//
// The results are cached because each one is a server-side resource that we own and have to free,
// and because setting a standard cursor is the kind of thing a game calls every frame.
x11_standard_cursor :: proc(standard: Standard_Cursor) -> X.Cursor {
	if cached, ok := s.standard_cursors[standard].?; ok {
		return cached
	}

	name, fallback := linux_standard_cursor_names(standard)
	cursor := X.cursorLibraryLoadCursor(s.display, name)

	if cursor == 0 {
		cursor = X.cursorLibraryLoadCursor(s.display, fallback)
	}

	// Cached even when it's 0, so a theme missing one doesn't mean two round trips per frame.
	s.standard_cursors[standard] = cursor
	return cursor
}

x11_is_cursor_hidden :: proc() -> bool {
	return s.cursor_hidden	
}

x11_set_mouse_locked :: proc(locked: bool) {
	s.mouse_locked = locked

	if locked {
		// Confine pointer to window (equivalent of Windows' ClipCursor)
		X.GrabPointer(
			s.display,
			s.window,
			false, // owner_events
			{.PointerMotion, .ButtonPress, .ButtonRelease},
			.GrabModeAsync,
			.GrabModeAsync,
			s.window, // confine_to: restrict to this window
			0, // cursor: 0 = keep current
			X.CurrentTime,
		)

		_x11_teleport_cursor_to_center()
	} else {
		X.UngrabPointer(s.display, X.CurrentTime)
		X.Flush(s.display)
	}
}

x11_is_mouse_locked :: proc() -> bool {
	return s.mouse_locked
}

_x11_teleport_cursor_to_center :: proc() {
	cx := s.screen_width / 2
	cy := s.screen_height / 2
	X.WarpPointer(s.display, 0, s.window, 0, 0, 0, 0, i32(cx), i32(cy))
	X.Flush(s.display)
	append(&s.events, Event_Mouse_Teleported {
		position = {f32(cx), f32(cy)},
	})
}

x11_create_custom_cursor :: proc(image: Image, hotspot: [2]int) -> Custom_Cursor {
	img := X.cursorImageCreate(i32(image.width), i32(image.height))
	defer X.cursorImageDestroy(img)

	// Convert to ARGB and premultiply alpha into a temporary. The image is not ours to mutate, and
	// Xcursor's buffer holds packed X.CursorPixel (u32) values rather than Color.
	premultiplied := make([]Color, len(image.pixels), frame_allocator)

	for i in 0 ..< len(image.pixels) {
		src := image.pixels[i]
		a := src.a
		r := u8(f32(src.r) * (f32(a) / 255))
		g := u8(f32(src.g) * (f32(a) / 255))
		b := u8(f32(src.b) * (f32(a) / 255))
		premultiplied[i] = {b, g, r, a}
	}

	// Copy into the buffer Xcursor allocated for us. Overwriting `img.pixels` with our own pointer
	// would leak that buffer and make cursorImageDestroy free memory it does not own.
	dst := slice.from_ptr(img.pixels, len(premultiplied))
	copy(dst, slice.reinterpret([]X.CursorPixel, premultiplied))
	img.xhot = X.CursorDim(hotspot.x)
	img.yhot = X.CursorDim(hotspot.y)

	cursor := X.cursorImageLoadCursor(s.display, img)

	if cursor == 0 {
		log.error("cursorImageLoadCursor failed")
		return {}
	}

	handle, add_err := hm.add(&s.custom_cursors, X11_Cursor_Data{cursor = cursor})

	if add_err != nil {
		log.errorf("Failed to create cursor. Error: %v", add_err)
		X.FreeCursor(s.display, cursor)
		return {}
	}

	return handle
}

x11_set_cursor :: proc(cursor: Cursor) {
	// Reject a stale handle before storing it, so the cursor on screen is left alone on a
	// programming error rather than silently reverting to the default.
	if c, is_custom := cursor.(Custom_Cursor); is_custom {
		if hm.get(&s.custom_cursors, c) == nil {
			log.errorf("Trying to set invalid cursor %v. It may have been destroyed.", c)
			return
		}
	}

	s.current_cursor = cursor
	x11_apply_cursor()
}

x11_destroy_custom_cursor :: proc(custom_cursor: Custom_Cursor) {
	cd := hm.get(&s.custom_cursors, custom_cursor)

	if cd == nil {
		log.errorf(
			"Trying to destroy invalid cursor %v. It may already be destroyed.",
			custom_cursor,
		)
		return
	}

	X.FreeCursor(s.display, cd.cursor)
	hm.remove(&s.custom_cursors, custom_cursor)

	// If that was the cursor on screen it no longer resolves, so re-applying falls back to the
	// default. Cheap enough to do unconditionally.
	x11_apply_cursor()
}

x11_set_internal_state :: proc(state: rawptr) {
	assert(state != nil)
	s = (^X11_State)(state)
}

X11_State :: struct {
	allocator: runtime.Allocator,
	
	screen_width: int,
	screen_height: int,
	
	last_configure_width: int,
	last_configure_height: int,
	last_configure_windowed_width: int,
	last_configure_windowed_height: int,
	
	display: ^X.Display,
	window: X.Window,
	delete_msg: X.Atom,
	window_mode: Window_Mode,
	window_render_glue: Window_Render_Glue,
	blank_cursor: X.Cursor,

	custom_cursors: hm.Dynamic_Handle_Map(X11_Cursor_Data, Custom_Cursor),

	// The cursor most recently passed to x11_set_cursor. The zero value is Standard_Cursor.Default.
	current_cursor: Cursor,

	// Lazily loaded theme cursors, one per standard cursor. See x11_standard_cursor.
	standard_cursors: [Standard_Cursor]Maybe(X.Cursor),

	cursor_hidden: bool,
	mouse_locked: bool,
	events: [dynamic]Event,
}

X11_Cursor_Data :: struct {
	handle: Custom_Cursor,
	cursor: X.Cursor,
}

s: ^X11_State

