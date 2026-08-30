#+build linux
#+private file

package karl2d

@(private="package")
LINUX_WINDOW_X11 :: Linux_Window_Interface {
	state_size = x11_state_size,
	try_load = x11_try_load,
	init = x11_init,
	shutdown = x11_shutdown,
	get_window_render_glue = x11_get_window_render_glue,
	get_events = x11_get_events,
	set_title = x11_set_title,
	get_screen_width = x11_get_screen_width,
	get_screen_height = x11_get_screen_height,
	set_position = x11_set_position,
	get_position = x11_get_position,
	set_screen_size = x11_set_screen_size,
	get_window_scale = x11_get_window_scale,
	set_window_mode = x11_set_window_mode,
	set_window_icon = x11_set_window_icon,
	set_cursor_hidden = x11_set_cursor_hidden,
	is_cursor_hidden = x11_is_cursor_hidden,
	set_mouse_locked = x11_set_mouse_locked,
	is_mouse_locked = x11_is_mouse_locked,
	create_custom_cursor = x11_create_custom_cursor,
	set_cursor = x11_set_cursor,
	destroy_custom_cursor = x11_destroy_custom_cursor,
	set_internal_state = x11_set_internal_state,
}

import X "platform_bindings/linux/x11"
import "base:runtime"
import "log"
import "core:fmt"
import "core:slice"
import "core:strconv"
import hm "core:container/handle_map"

_ :: log
_ :: fmt

// The horizontal wheel is button 6 and 7. Xlib stops naming buttons at 5.
BUTTON_WHEEL_LEFT :: X.MouseButton(6)
BUTTON_WHEEL_RIGHT :: X.MouseButton(7)

// The DPI that X11 and every toolkit on it treat as 100% scale.
DEFAULT_DPI :: 96

x11_state_size :: proc() -> int {
	return size_of(X11_State)
}

x11_try_load :: proc(
	failure_reason_allocator: runtime.Allocator,
) -> (
	failure_reason: string,
	ok: bool,
) {
	missing, load_ok := X.load()

	if !load_ok {
		return fmt.aprintf("Not using X11. Could not load %v.", missing,
			allocator = failure_reason_allocator), false
	}

	// The libraries being installed does not mean there is a server to talk to, so open a display
	// and throw it away again. `x11_init` opens the one that gets used.
	display := X.OpenDisplay(nil)

	if display == nil {
		X.unload()
		return "Not using X11. Could not open a display.", false
	}

	X.CloseDisplay(display)
	return "", true
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
	s.events = make([dynamic]Event, allocator)
	hm.dynamic_init(&s.custom_cursors, allocator)

	// Xlib wants this before anything touches the resource database.
	X.XrmInitialize()
	s.display = X.OpenDisplay(nil)

	// The resource database, holding the DPI setting among other things, lives in this property on
	// the root window. See x11_fetch_window_scale.
	s.resource_manager = X.InternAtom(s.display, "RESOURCE_MANAGER", false)
	s.window_scale = x11_fetch_window_scale()

	if init_options.disable_auto_scale_hint {
		s.screen_width = screen_width
		s.screen_height = screen_height
	} else {
		s.screen_width = int(f32(screen_width) * s.window_scale)
		s.screen_height = int(f32(screen_height) * s.window_scale)
	}

	s.window = X.CreateSimpleWindow(
		s.display,
		X.DefaultRootWindow(s.display),
		0, 0,
		u32(s.screen_width), u32(s.screen_height),
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

	// Detectable auto-repeat means a held-down key produces repeated KeyPress events without an
	// interleaved KeyRelease between them, so we can tell an initial press from a repeat by
	// tracking which keys are currently held (see `x11_get_events`). If unsupported, we fall back
	// to peeking the event queue for the release/press pair X11 sends per repeat by default.
	autorepeat_supported: b32
	X.XkbSetDetectableAutoRepeat(s.display, true, &autorepeat_supported)
	s.detectable_autorepeat = bool(autorepeat_supported)

	// Set up an input method so we can translate key presses into typed text (taking the current
	// keyboard layout into account) via `Xutf8LookupString`. If no input method is available, we
	// fall back to `XLookupString` in `x11_get_events`, which only supports Latin-1.
	X.SetLocaleModifiers("")
	s.xim = X.OpenIM(s.display, nil, nil, nil)

	if s.xim != nil {
		s.xic = X.CreateIC(
			s.xim,
			X.XNInputStyle, X.XIMPreeditNothing | X.XIMStatusNothing,
			X.XNClientWindow, s.window,
			X.XNFocusWindow, s.window,
			cstring(nil),
		)
	}

	// A DPI change shows up as a PropertyNotify for the resource database on the root window. This
	// is also how GTK and Qt notice. It means we see every other root property the window manager
	// touches too, which is why x11_get_events checks the atom.
	//
	// SelectInput replaces our mask for a window rather than adding to it, and the input method
	// above shares this display connection and may select on the root window too. So we run after
	// it and keep whatever it asked for.
	root := X.DefaultRootWindow(s.display)
	root_attribs: X.XWindowAttributes
	X.GetWindowAttributes(s.display, root, &root_attribs)
	X.SelectInput(s.display, root, root_attribs.your_event_mask | {.PropertyChange})

	x11_set_window_mode(init_options.window_mode)

	// blank cursor for hiding it
	{
		blank_pixmap := X.CreatePixmap(s.display, s.window, 1, 1, 1)
		black: X.XColor

		s.blank_cursor = X.CreatePixmapCursor(
			s.display,
			blank_pixmap,
			blank_pixmap,
			&black,
			&black,
			0,
			0,
		)
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

	if s.xic != nil {
		X.DestroyIC(s.xic)
	}

	if s.xim != nil {
		X.CloseIM(s.xim)
	}

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

		// The input method gets first look at each event. It swallows the ones that are part of
		// composing a character (dead keys, CJK input methods etc), and hands us the finished text
		// later via `Xutf8LookupString`. Skipping this makes those keystrokes arrive twice.
		//
		// Passing window 0 (`None`) means "use the window the event was generated for", which also
		// covers events on windows the input method made for itself.
		if s.xic != nil && X.FilterEvent(&event, 0) {
			continue
		}

		#partial switch event.type {
		case .ClientMessage:
			if X.Atom(event.xclient.data.l[0]) == s.delete_msg {
				append(events, Event_Close_Window_Requested{})
			}
		case .KeyPress:
			key := key_from_xkeycode(event.xkey.keycode)
			kc := u8(min(event.xkey.keycode, 255))

			if key != .None {
				if s.key_held[kc] {
					append(events, Event_Key_Repeat {
						key = key,
					})
				} else {
					s.key_held[kc] = true
					append(events, Event_Key_Went_Down {
						key = key,
					})
				}
			}

			_x11_append_typed_runes(events, &event.xkey)

		case .KeyRelease:
			key := key_from_xkeycode(event.xkey.keycode)
			kc := u8(min(event.xkey.keycode, 255))

			if !s.detectable_autorepeat && X.Pending(s.display) > 0 {
				next: X.XEvent
				X.PeekEvent(s.display, &next)

				is_autorepeat := next.type == .KeyPress &&
					next.xkey.keycode == event.xkey.keycode &&
					next.xkey.time == event.xkey.time

				if is_autorepeat {
					// This release is immediately followed by a press of the same key at the same
					// time, which is how X11 signals auto-repeat when detectable auto-repeat isn't
					// supported. Swallow it -- `s.key_held[kc]` stays true, so the upcoming
					// KeyPress will correctly be treated as a repeat.
					continue
				}
			}

			s.key_held[kc] = false

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
					event.xbutton.button == .Button4 ? 1 : -1,
				})
			} else if event.xbutton.button <= BUTTON_WHEEL_RIGHT {
				append(events, Event_Mouse_Wheel_Horizontal {
					event.xbutton.button == BUTTON_WHEEL_LEFT ? -1 : 1,
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

		case .PropertyNotify:
			is_resource_manager := event.xproperty.state == .NewValue &&
				event.xproperty.window == X.DefaultRootWindow(s.display) &&
				event.xproperty.atom == s.resource_manager

			if is_resource_manager {
				new_scale := x11_fetch_window_scale()

				if new_scale != s.window_scale {
					s.window_scale = new_scale

					append(events, Event_Window_Scale_Changed {
						scale = new_scale,
						screen_width = s.screen_width,
						screen_height = s.screen_height,
					})
				}
			}

		case .FocusIn:
			if s.xic != nil {
				X.SetICFocus(s.xic)
			}

			append(events, Event_Window_Focused{})

		case .FocusOut:
			if s.xic != nil {
				X.UnsetICFocus(s.xic)
			}

			// X11 unlocks the mouse if program loses focus
			s.mouse_locked = false

			// We won't see the KeyRelease for anything held while we're unfocused. Without this a
			// key held during focus loss stays marked as held, making the next press of it look
			// like a repeat instead of a fresh press.
			s.key_held = {}

			append(events, Event_Window_Unfocused{})
		}
	}

	append(events, ..s.events[:])
	runtime.clear(&s.events)
}

_x11_append_typed_runes :: proc(events: ^[dynamic]Event, key_event: ^X.XKeyPressedEvent) {
	buf: [32]u8
	keysym: X.KeySym

	if s.xic != nil {
		status: X.LookupStringStatus

		n := X.Xutf8LookupString(
			s.xic, key_event, cstring(raw_data(buf[:])), i32(len(buf)), &keysym, &status,
		)

		if status == .BufferOverflow || n <= 0 {
			return
		}

		count := min(int(n), len(buf))

		for r in string(buf[:count]) {
			if is_typable_rune(r) {
				append(events, Event_Typed_Rune { typed = r })
			}
		}
	} else {
		// No input method available. Fall back to XLookupString, which only supports Latin-1 (no
		// keyboard layout / IME support).
		n := X.LookupString(key_event, raw_data(buf[:]), i32(len(buf)), &keysym, nil)

		if n <= 0 {
			return
		}

		count := min(int(n), len(buf))

		for b in buf[:count] {
			r := rune(b)

			if is_typable_rune(r) {
				append(events, Event_Typed_Rune { typed = r })
			}
		}
	}
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

x11_get_position :: proc() -> Vec2 {
	x, y: i32
	child: X.Window
	X.TranslateCoordinates(
		s.display,
		s.window,
		X.DefaultRootWindow(s.display),
		0,
		0,
		&x,
		&y,
		&child,
	)
	return {f32(x), f32(y)}
}

x11_set_screen_size :: proc(w, h: int) {
	X.ResizeWindow(s.display, s.window, u32(w), u32(h))
}

x11_get_window_scale :: proc() -> f32 {
	return s.window_scale
}

// Reads the DPI scale from the X resource database. `Xft.dpi` is what GTK and Qt use, so this
// matches the rest of the desktop. There is no per-monitor DPI in X11: one number covers
// everything. Desktops that would set it to 96 tend to remove the entry instead, so a missing
// entry means 100%.
//
// We fetch the root window property ourselves instead of calling XResourceManagerString. That one
// returns the copy Xlib took when the display connection was opened, so it never reflects a change
// made while the game is running.
x11_fetch_window_scale :: proc() -> f32 {
	// A length in 32-bit units. The server sends only what is actually there, so this just has to
	// be bigger than any real resource database.
	MAX_RESOURCE_WORDS :: 1024 * 1024

	actual_type: X.Atom
	actual_format: i32
	num_items: uint
	bytes_after: uint
	prop: rawptr

	get_status := X.GetWindowProperty(
		s.display,
		X.DefaultRootWindow(s.display),
		s.resource_manager,
		0,
		MAX_RESOURCE_WORDS,
		false,
		X.AnyPropertyType,
		&actual_type,
		&actual_format,
		&num_items,
		&bytes_after,
		&prop,
	)

	if get_status != .Success || prop == nil {
		return 1
	}

	// Xlib puts a zero byte after the data it hands back, so this is a valid cstring even though
	// the property itself is not terminated.
	db := X.XrmGetStringDatabase(cstring(prop))
	X.Free(prop)

	if db == nil {
		return 1
	}

	scale: f32 = 1
	res_type: cstring
	res_value: X.XrmValue

	found := bool(X.XrmGetResource(db, "Xft.dpi", "Xft.Dpi", &res_type, &res_value))

	if found && res_type == "String" && res_value.addr != nil {
		dpi, dpi_ok := strconv.parse_f32(string(cstring(res_value.addr)))

		if dpi_ok && dpi > 0 {
			scale = dpi/DEFAULT_DPI
		}
	}

	X.XrmDestroyDatabase(db)
	return scale
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

x11_set_window_icon :: proc(image: Image, _: bool) -> bool {
	// `_NET_WM_ICON` holds a list of icons, each one its width and height followed by its pixels
	// in ARGB. We send a single icon and let the window manager scale it to the sizes it wants.
	//
	// The property has a format of 32, which in Xlib means an array of C `long`. That is 64 bits
	// wide on 64-bit Linux, so each pixel travels in the low half of its own `uint`. Handing this
	// call a `[]u32` is the usual way to get garbage on screen instead of an icon.
	data, data_err := make([]uint, 2 + image.width*image.height, frame_allocator)

	if data_err != nil {
		log.errorf("Failed setting window icon: allocating the property failed with %v", data_err)
		return false
	}

	data[0] = uint(image.width)
	data[1] = uint(image.height)

	for i in 0..<len(image.pixels) {
		col := image.pixels[i]
		data[2 + i] = uint(col.a) << 24 | uint(col.r) << 16 | uint(col.g) << 8 | uint(col.b)
	}

	X.ChangeProperty(
		s.display,
		s.window,
		X.InternAtom(s.display, "_NET_WM_ICON", false),
		X.XA_CARDINAL,
		32,
		X.PropModeReplace,
		raw_data(data),
		i32(len(data)),
	)

	X.Flush(s.display)

	// The X server reports a rejected property change asynchronously, so true here means the
	// request was sent, not that the icon reached the screen.
	return true
}

x11_set_cursor_hidden :: proc(hidden: bool) {
	s.cursor_hidden = hidden
	x11_apply_cursor()
}

// Applies s.cursor_hidden and s.current_cursor to the window. They share the window's one cursor
// (whatever DefineCursor last set), so every entry point goes through this.
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

// Loads a standard cursor from the user's cursor theme, or 0 if the theme has none for it. Cached:
// each one is a server-side resource we have to free, and games set cursors every frame.
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

x11_create_custom_cursor :: proc(image: Image, hotspot: [2]int) -> (Custom_Cursor, bool) {
	img := X.cursorImageCreate(i32(image.width), i32(image.height))

	if img == nil {
		log.error("cursorImageCreate failed")
		return {}, false
	}

	// Convert to ARGB and premultiply alpha, straight into the buffer Xcursor allocated for us.
	// Overwriting `img.pixels` with our own pointer would leak that buffer and make
	// cursorImageDestroy free memory it does not own.
	pixel_data := slice.from_ptr(img.pixels, len(image.pixels))

	for i in 0..<len(image.pixels) {
		col := image.pixels[i]
		a := u32(col.a)
		r := u32(col.r) * a / 255
		g := u32(col.g) * a / 255
		b := u32(col.b) * a / 255
		pixel_data[i] = a << 24 | r << 16 | g << 8 | b
	}

	img.xhot = X.CursorDim(hotspot.x)
	img.yhot = X.CursorDim(hotspot.y)

	cursor := X.cursorImageLoadCursor(s.display, img)
	X.cursorImageDestroy(img)

	if cursor == 0 {
		log.error("cursorImageLoadCursor failed")
		return {}, false
	}

	handle, add_err := hm.add(&s.custom_cursors, X11_Cursor{cursor = cursor})

	if add_err != nil {
		log.errorf("Failed to create cursor. Error: %v", add_err)
		X.FreeCursor(s.display, cursor)
		return {}, false
	}

	return handle, true
}

x11_set_cursor :: proc(cursor: Cursor) {
	// Reject a stale handle, so a programming error leaves the cursor alone.
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

	// Falls back to the default if that was the cursor on screen.
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
	
	// The scale from the OS. 1 means 100%. See x11_fetch_window_scale.
	window_scale: f32,

	// The root window property holding the X resource database. We watch it to notice DPI changes.
	resource_manager: X.Atom,

	display: ^X.Display,
	window: X.Window,
	delete_msg: X.Atom,
	window_mode: Window_Mode,
	window_render_glue: Window_Render_Glue,
	blank_cursor: X.Cursor,

	custom_cursors: hm.Dynamic_Handle_Map(X11_Cursor, Custom_Cursor),

	// The cursor most recently passed to x11_set_cursor. The zero value is Standard_Cursor.Default.
	current_cursor: Cursor,

	// Lazily loaded theme cursors, one per standard cursor. See x11_standard_cursor.
	standard_cursors: [Standard_Cursor]Maybe(X.Cursor),

	cursor_hidden: bool,
	mouse_locked: bool,
	events: [dynamic]Event,

	xim: X.XIM,
	xic: X.XIC,
	detectable_autorepeat: bool,

	// Tracks which keys are currently held, indexed by X11 keycode. Used to tell an initial
	// KeyPress from an auto-repeated one.
	key_held: [256]bool,
}

X11_Cursor :: struct {
	handle: Custom_Cursor,
	cursor: X.Cursor,
}

s: ^X11_State

