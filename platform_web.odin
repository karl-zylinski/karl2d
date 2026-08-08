#+build js
#+vet explicit-allocators
#+feature dynamic-literals
#+private file

package karl2d

@(private="package")
PLATFORM_WEB :: Platform_Interface {
	state_size = web_state_size,
	init = web_init,
	shutdown = web_shutdown,
	get_window_render_glue = web_get_window_render_glue,
	get_events = web_get_events,
	set_window_title = web_set_window_title,
	set_screen_size = web_set_screen_size,
	get_screen_width = web_get_screen_width,
	get_screen_height = web_get_screen_height,
	set_window_position = web_set_position,
	get_window_scale = web_get_window_scale,
	set_window_mode = web_set_window_mode,
	
	set_cursor_hidden = web_set_cursor_hidden,
	is_cursor_hidden = web_is_cursor_hidden,
	set_cursor_locked = web_set_cursor_locked,
	is_cursor_locked = web_is_cursor_locked,	
	create_cursor = web_create_cursor,
	set_cursor = web_set_cursor,
	destroy_cursor = web_destroy_cursor,

	is_gamepad_active = web_is_gamepad_active,
	get_gamepad_axis = web_get_gamepad_axis,
	set_gamepad_vibration = web_set_gamepad_vibration,

	open_url = web_open_url,

	set_internal_state = web_set_internal_state,
}

import "core:sys/wasm/js"
import "core:math"
import "core:encoding/base64"
import "base:runtime"
import "log"
import "core:fmt"

web_state_size :: proc() -> int {
	return size_of(Web_State)
}

web_init :: proc(
	window_state: rawptr,
	window_width: int,
	window_height: int,
	window_title: string,
	init_options: Init_Options,
	allocator: runtime.Allocator,
) {
	s = (^Web_State)(window_state)
	s.allocator = allocator
	s.events = make([dynamic]Event, allocator)
	s.key_from_js_event_key_code = make(map[string]Keyboard_Key, allocator)
	s.canvas_id = "webgl-canvas"

	js.set_document_title(window_title)
	s.prev_scale = f32(js.device_pixel_ratio())
	// The browser window probably has some other size than what was sent in.
	switch init_options.window_mode {
	case .Windowed:
		web_set_screen_size(window_width, window_height)
	case .Windowed_Resizable:
		web_set_screen_size_to_window_size(s.canvas_id)
	case .Borderless_Fullscreen:
		log.error("Borderless_Fullscreen not implemented on web, but you can make it happen by using Window_Mode.Windowed_Resizable and putting the game in a fullscreen iframe.")
	}

	s.window_mode = init_options.window_mode

	add_window_event_listener(.Resize, web_event_window_resize)
	add_canvas_event_listener(.Mouse_Move, web_event_mouse_move)
	add_canvas_event_listener(.Mouse_Down, web_event_mouse_down)
	add_window_event_listener(.Mouse_Up, web_event_mouse_up)
	add_canvas_event_listener(.Wheel, web_event_mouse_wheel)

	add_window_event_listener(.Key_Down, web_event_key_down)
	add_window_event_listener(.Key_Up, web_event_key_up)
	add_window_event_listener(.Focus, web_event_focus)
	add_window_event_listener(.Blur, web_event_blur)

	add_window_event_listener(.Pointer_Lock_Change, _web_event_pointer_lock_change)

	if init_options.disable_auto_scale_hint {
		log.warn("disable_auto_scale_hint not supported on web")
	}
}

web_event_key_down :: proc(e: js.Event) {
	if e.key.repeat {
		return
	}

	key := key_from_js_event(e)
	append(&s.events, Event_Key_Went_Down {
		key = key,
	})
}

web_event_key_up :: proc(e: js.Event) {
	key := key_from_js_event(e)
	append(&s.events, Event_Key_Went_Up {
		key = key,
	})
}

web_event_focus :: proc(e: js.Event) {
	append(&s.events, Event_Window_Focused {})
}

web_event_blur :: proc(e: js.Event) {
	s.cursor_locked = false
	append(&s.events, Event_Window_Unfocused {})
}

web_event_window_resize :: proc(e: js.Event) {
	new_scale := f32(js.device_pixel_ratio())

	// We get a window resize event on DPI scale change. Therefore we can piggyback on this to do
	// send the event about the DPI changing.
	if new_scale != s.prev_scale {
		s.prev_scale = new_scale
		web_set_screen_size(s.width, s.height)
		append(&s.events, Event_Window_Scale_Changed {
			scale = new_scale,
			screen_width = s.width,
			screen_height = s.height,
		})
	}

	if s.window_mode == .Windowed_Resizable {
		web_set_screen_size_to_window_size(s.canvas_id)
	}
}

web_event_mouse_move :: proc(e: js.Event) {
	if s.cursor_locked {
		cx := f32(s.width / 2)
		cy := f32(s.height / 2)
		dx := f32(e.mouse.movement.x) * f32(js.device_pixel_ratio())
		dy := f32(e.mouse.movement.y) * f32(js.device_pixel_ratio())
		append(&s.events, Event_Mouse_Move { position = {cx + dx, cy + dy} })
		append(&s.events, Event_Mouse_Teleported { position = {cx, cy} })
	} else {
		append(&s.events, Event_Mouse_Move {
			position = {
				math.floor(f32(e.mouse.client.x) * f32(js.device_pixel_ratio())),
				math.floor(f32(e.mouse.client.y) * f32(js.device_pixel_ratio())),
			},
		})
	}
}

web_event_mouse_down :: proc(e: js.Event) {
	button := Mouse_Button.Left

	if e.mouse.button == 2 {
		button = .Right
	}

	if e.mouse.button == 1 {
		button = .Middle 
	}

	append(&s.events, Event_Mouse_Button_Went_Down {
		button = button,
	})
}

web_event_mouse_up :: proc(e: js.Event) {
	button := Mouse_Button.Left

	if e.mouse.button == 2 {
		button = .Right
	}

	if e.mouse.button == 1 {
		button = .Middle 
	}

	append(&s.events, Event_Mouse_Button_Went_Up {
		button = button,
	})
}

web_event_mouse_wheel :: proc(e: js.Event) {
	append(&s.events, Event_Mouse_Wheel {
		// Not the best way, but how would we know what the wheel deltaMode really represents? If it
		// is in pixels, how much "scroll" does that equal to?
		delta = f32(e.wheel.delta.y > 0 ? -1 : 1),
	})
}

add_canvas_event_listener :: proc(evt: js.Event_Kind, callback: proc(e: js.Event)) {
	js.add_event_listener(
		s.canvas_id, 
		evt, 
		nil, 
		callback,
		true,
	)
}

add_window_event_listener :: proc(evt: js.Event_Kind, callback: proc(e: js.Event)) {
	js.add_window_event_listener(evt, nil, callback, true)
}

remove_window_event_listener :: proc(evt: js.Event_Kind, callback: proc(e: js.Event)) {
	js.remove_window_event_listener(evt, nil, callback, true)
}

web_set_screen_size_to_window_size :: proc(canvas_id: HTML_Canvas_ID) {
	rect := js.get_bounding_client_rect("body")
	
	scale := web_get_window_scale()
	s.width = int(f32(rect.width) * scale)
	s.height = int(f32(rect.height) * scale)

	js.set_element_key_f64(canvas_id, "width", f64(s.width))
	js.set_element_key_f64(canvas_id, "height", f64(s.height))

	js.set_element_style(canvas_id, "width", fmt.tprintf("%fpx", f64(rect.width)))
	js.set_element_style(canvas_id, "height", fmt.tprintf("%fpx", f64(rect.height)))

	append(&s.events, Event_Screen_Resize {
		width = s.width,
		height = s.height,
	})
}

web_shutdown :: proc() {
	delete(s.events)
	delete(s.key_from_js_event_key_code)
}

web_get_window_render_glue :: proc() -> Window_Render_Glue {
	// We can only use WebGL backend right now, so this is very simple: Just pass canvas ID as
	// state, the WebGL backend knows to convert it properly.
	return {
		state = (^Window_Render_Glue_State)(&s.canvas_id),
	}
}

// This works for XBox controller -- does it work for PlayStation?
//
// The magic numbers are from https://gamepad-tester.net/
KARL2D_GAMEPAD_BUTTON_FROM_JS :: [Gamepad_Button]int {
	.None = 0,
	
	.Left_Face_Up = 12,
	.Left_Face_Down = 13,
	.Left_Face_Left = 14,
	.Left_Face_Right = 15,

	.Right_Face_Up = 3, 
	.Right_Face_Down = 0, 
	.Right_Face_Left = 2, 
	.Right_Face_Right = 1, 

	.Left_Shoulder = 4,
	.Left_Trigger = 6,

	.Right_Shoulder = 5,
	.Right_Trigger = 7,

	.Left_Stick_Press = 10, 
	.Right_Stick_Press = 11, 

	.Middle_Face_Left = 8, 
	.Middle_Face_Middle = -1, 
	.Middle_Face_Right = 9, 
}

web_get_events :: proc(events: ^[dynamic]Event) {
	append(events, ..s.events[:])
	runtime.clear(&s.events)

	for gamepad_idx in 0..<MAX_GAMEPADS {
		// new_state
		ns: js.Gamepad_State

		if !js.get_gamepad_state(gamepad_idx, &ns) || !ns.connected {
			if s.gamepad_state[gamepad_idx].connected {
				s.gamepad_state[gamepad_idx] = {}
			}
			continue
		}

		// prev_state
		ps := s.gamepad_state[gamepad_idx]

		// We check if any button changed from pressed to not pressed and the other way around.
		for js_idx, button in KARL2D_GAMEPAD_BUTTON_FROM_JS {
			if js_idx == -1 {
				continue
			}

			if !ps.buttons[js_idx].pressed && ns.buttons[js_idx].pressed {
				append(events, Event_Gamepad_Button_Went_Down {
					gamepad = gamepad_idx,
					button = button,
				})
			}

			if ps.buttons[js_idx].pressed && !ns.buttons[js_idx].pressed {
				append(events, Event_Gamepad_Button_Went_Up {
					gamepad = gamepad_idx,
					button = button,
				})
			}
		}

		s.gamepad_state[gamepad_idx] = ns
	}
}

web_get_screen_width :: proc() -> int {
	return s.width
}

web_get_screen_height :: proc() -> int {
	return s.height
}

web_clear_events :: proc() {
	runtime.clear(&s.events)
}

web_set_window_title :: proc(title: string) {
	js.set_document_title(title)
}

web_set_position :: proc(x: int, y: int) {
	log.warn("set_window_position not implemented on web")
}

web_set_screen_size :: proc(w, h: int) {
	scale := web_get_window_scale()
	s.width = int(f32(w) * scale)
	s.height = int(f32(h) * scale)

	js.set_element_key_f64(s.canvas_id, "width", f64(s.width))
	js.set_element_key_f64(s.canvas_id, "height", f64(s.height))

	js.set_element_style(s.canvas_id, "width",  fmt.tprintf("%fpx", f64(w)))
	js.set_element_style(s.canvas_id, "height", fmt.tprintf("%fpx", f64(h)))
}

web_get_window_scale :: proc() -> f32 {
	return f32(js.device_pixel_ratio())
}

web_set_window_mode :: proc(new_mode: Window_Mode) {
	if new_mode == .Borderless_Fullscreen {
		log.error("Borderless_Fullscreen not implemented on web, but you can make it happen by using Window_Mode.Windowed_Resizable and putting the game in a fullscreen iframe.")
		return
	}

	old_mode := s.window_mode
	s.window_mode = new_mode

	if new_mode == .Windowed_Resizable && old_mode == .Windowed {
		web_set_screen_size_to_window_size(s.canvas_id)
	} else if new_mode == .Windowed && old_mode == .Windowed_Resizable {
		web_set_screen_size(s.width, s.height)
	}
}

web_set_cursor_hidden :: proc(hidden: bool) {
	s.cursor_hidden = hidden
	web_apply_cursor()
}

web_is_cursor_hidden :: proc() -> bool {
	return s.cursor_hidden
}

_web_event_pointer_lock_change :: proc(e: js.Event) {
	js.evaluate("document.getElementById('webgl-canvas')._pointerLocked = document.pointerLockElement !== null ? 1 : 0")
	s.cursor_locked = js.get_element_key_f64("webgl-canvas", "_pointerLocked") != 0
}

web_set_cursor_locked :: proc(locked: bool) {
	if locked {
		js.evaluate("document.getElementById('webgl-canvas').requestPointerLock()")
		cx := f32(s.width / 2)
		cy := f32(s.height / 2)
		append(&s.events, Event_Mouse_Teleported { position = {cx, cy} })
	} else {
		js.evaluate("document.exitPointerLock()")
	}

	// s.cursor_locked set by _web_event_pointer_lock_change
}

web_is_cursor_locked :: proc() -> bool {
	return s.cursor_locked
}

web_create_cursor :: proc(image: Image, hotspot: [2]int) -> Cursor_Data {
	// There is no hardware cursor API on the web, so we hand the browser a PNG as a data URI and
	// let CSS do the work. core:image/png can only decode, not encode, so we encode it ourselves;
	// see encode_png's own comment for why that is fine here.
	png_bytes, encode_ok := encode_png(image, s.allocator)
	if !encode_ok {
		log.error("Failed to encode cursor image as PNG")
		return {}
	}
	defer delete(png_bytes, s.allocator)

	// Browsers cap `cursor` images at 128 CSS pixels; anything bigger is either clamped or, in
	// Firefox, ignored entirely and silently replaced with the default cursor.
	scale := web_get_window_scale()
	if f32(image.width)/scale > 128 || f32(image.height)/scale > 128 {
		log.warnf(
			"Cursor image is %vx%v physical pixels, which is %.0fx%.0f CSS pixels at the current " +
			"%vx display scale. Browsers cap cursors at 128 CSS pixels and some ignore anything " +
			"bigger entirely, so consider using a smaller image.",
			image.width, image.height,
			f32(image.width)/scale, f32(image.height)/scale,
			scale,
		)
	}

	// The base64 is copied into the data URI below, so it is not needed after that.
	pixels_b64 := base64.encode(png_bytes, allocator = s.allocator)
	defer delete(pixels_b64, s.allocator)

	cursor := new(Web_Cursor, s.allocator)
	cursor.data_uri = fmt.aprintf(
		"data:image/png;base64,%v",
		pixels_b64,
		allocator = s.allocator,
	)
	cursor.hotspot = hotspot
	web_build_cursor_style(cursor)

	return {
		os_handle = cursor,
	}
}

// The `cursor` property sizes its image in CSS pixels, but the rest of Karl2D works in device
// pixels: the canvas is `scale` times bigger than its CSS box. A cursor made from a 128x128 image
// would therefore be drawn twice as big as a 128x128 sprite drawn by the game on a 2x display.
//
// `image-set` fixes that by telling the browser the image has `scale` device pixels per CSS pixel,
// which both scales it down and keeps it crisp. The hotspot is in CSS pixels too, so it is scaled
// to match. We keep the plain `url` value around as a fallback, see `web_set_cursor`.
web_build_cursor_style :: proc(cursor: ^Web_Cursor) {
	delete(cursor.style_value, s.allocator)
	delete(cursor.style_value_scaled, s.allocator)

	scale := web_get_window_scale()

	cursor.style_value = fmt.aprintf(
		"url(%v) %v %v, auto",
		cursor.data_uri,
		cursor.hotspot.x, cursor.hotspot.y,
		allocator = s.allocator,
	)

	cursor.style_value_scaled = fmt.aprintf(
		"image-set(url(%v) %vx) %.2f %.2f, auto",
		cursor.data_uri, scale,
		f32(cursor.hotspot.x) / scale, f32(cursor.hotspot.y) / scale,
		allocator = s.allocator,
	)

	cursor.built_for_scale = scale
}

web_set_cursor :: proc(cursor: Cursor_Data) {
	s.current_cursor = (^Web_Cursor)(cursor.os_handle)
	web_apply_cursor()
}

// Applies s.cursor_hidden and s.current_cursor to the canvas. The two share the same underlying
// CSS `cursor` property, so both set_cursor_hidden and set_cursor go through this instead of
// touching it independently and clobbering each other.
web_apply_cursor :: proc() {
	if s.cursor_hidden {
		js.set_element_style(s.canvas_id, "cursor", "none")
		s.applied_cursor = nil
		return
	}

	if s.current_cursor == nil {
		js.set_element_style(s.canvas_id, "cursor", "default")
		s.applied_cursor = nil
		return
	}

	cursor := s.current_cursor
	scale := web_get_window_scale()

	if cursor.built_for_scale != scale {
		web_build_cursor_style(cursor)
	}

	// The data URI is tens of kilobytes and games tend to set the cursor every frame, so don't make
	// the browser re-parse it when nothing has changed.
	if s.applied_cursor == cursor && s.applied_scale == scale {
		return
	}

	// Assign the plain value first. Browsers that can't parse `image-set` ignore the second
	// assignment and keep this one, which is the right thing to fall back to.
	js.set_element_style(s.canvas_id, "cursor", cursor.style_value)
	js.set_element_style(s.canvas_id, "cursor", cursor.style_value_scaled)

	s.applied_cursor = cursor
	s.applied_scale = scale
}

web_destroy_cursor :: proc(cursor: Cursor_Data) {
	if cursor.os_handle == nil {
		return
	}

	cursor := (^Web_Cursor)(cursor.os_handle)

	// Only fall back to the default cursor if the one being destroyed is the one on screen.
	if s.current_cursor == cursor {
		s.current_cursor = nil
		web_apply_cursor()
	}

	delete(cursor.data_uri, s.allocator)
	delete(cursor.style_value, s.allocator)
	delete(cursor.style_value_scaled, s.allocator)
	free(cursor, s.allocator)
}

web_is_gamepad_active :: proc(gamepad: int) -> bool {
	if gamepad < 0 || gamepad >= MAX_GAMEPADS {
		return false
	}

	return s.gamepad_state[gamepad].connected
}

web_get_gamepad_axis :: proc(gamepad: int, axis: Gamepad_Axis) -> f32 {
	if gamepad < 0 || gamepad >= MAX_GAMEPADS {
		return 0
	}

	if axis == .Left_Trigger {
		return f32(s.gamepad_state[gamepad].buttons[KARL2D_GAMEPAD_BUTTON_FROM_JS[.Left_Trigger]].value)
	}

	if axis == .Right_Trigger {
		return f32(s.gamepad_state[gamepad].buttons[KARL2D_GAMEPAD_BUTTON_FROM_JS[.Right_Trigger]].value)
	}

	js_axis: int

	switch axis {
	case .None: return 0
	case .Left_Stick_X: js_axis = 0
	case .Left_Stick_Y: js_axis = 1
	case .Right_Stick_X: js_axis = 2
	case .Right_Stick_Y: js_axis = 3
	case .Left_Trigger: return 0 // virtually unreachable
	case .Right_Trigger: return 0 // virtually unreachable
	}

	return f32(s.gamepad_state[gamepad].axes[js_axis])
}

web_set_gamepad_vibration :: proc(gamepad: int, left: f32, right: f32) {
	if gamepad < 0 || gamepad >= MAX_GAMEPADS {
		return
	}
}

web_open_url :: proc(url: string) -> bool {
	js.open(url)
	return true
}

web_set_internal_state :: proc(state: rawptr) {
	assert(state != nil)
	s = (^Web_State)(state)
}

@(private="package")
HTML_Canvas_ID :: string

Web_State :: struct {
	allocator: runtime.Allocator,
	canvas_id: HTML_Canvas_ID,
	width: int,
	height: int,
	prev_scale: f32,
	events: [dynamic]Event,
	cursor_locked: bool,
	cursor_hidden: bool,

	// The cursor most recently passed to web_set_cursor, or nil if the default OS cursor is
	// active. Also see web_apply_cursor.
	current_cursor: ^Web_Cursor,

	// What web_apply_cursor last wrote to the canvas, so it can skip redundant work.
	applied_cursor: ^Web_Cursor,
	applied_scale: f32,
	gamepad_state: [MAX_GAMEPADS]js.Gamepad_State,
	window_mode: Window_Mode,
	key_from_js_event_key_code: map[string]Keyboard_Key,
}

Web_Cursor :: struct {
	data_uri: string,
	hotspot: [2]int,

	// Both CSS values for `data_uri`, rebuilt whenever the DPI scale changes. See
	// `web_build_cursor_style`.
	style_value: string,
	style_value_scaled: string,
	built_for_scale: f32,
}

s: ^Web_State

key_from_js_event :: proc(e: js.Event) -> Keyboard_Key {
	if len(s.key_from_js_event_key_code) == 0 {
		context.allocator = s.allocator
		s.key_from_js_event_key_code = {
			"Digit1" = .N1,
			"Digit2" = .N2,
			"Digit3" = .N3,
			"Digit4" = .N4,
			"Digit5" = .N5,
			"Digit6" = .N6,
			"Digit7" = .N7,
			"Digit8" = .N8,
			"Digit9" = .N9,
			"Digit0" = .N0,

			"KeyA" = .A,
			"KeyB" = .B,
			"KeyC" = .C,
			"KeyD" = .D,
			"KeyE" = .E,
			"KeyF" = .F,
			"KeyG" = .G,
			"KeyH" = .H,
			"KeyI" = .I,
			"KeyJ" = .J,
			"KeyK" = .K,
			"KeyL" = .L,
			"KeyM" = .M,
			"KeyN" = .N,
			"KeyO" = .O,
			"KeyP" = .P,
			"KeyQ" = .Q,
			"KeyR" = .R,
			"KeyS" = .S,
			"KeyT" = .T,
			"KeyU" = .U,
			"KeyV" = .V,
			"KeyW" = .W,
			"KeyX" = .X,
			"KeyY" = .Y,
			"KeyZ" = .Z,

			"Quote" = .Apostrophe,
			"Comma" = .Comma,
			"Minus" = .Minus,
			"Period" = .Period,
			"Slash" = .Slash,
			"Semicolon" = .Semicolon,
			"Equal" = .Equal,
			"BracketLeft" = .Left_Bracket,
			"Backslash" = .Backslash,
			"IntlBackslash" = .Backslash,
			"BracketRight" = .Right_Bracket,
			"Backquote" = .Backtick,

			"Space" = .Space,
			"Escape" = .Escape,
			"Enter" = .Enter,
			"Tab" = .Tab,
			"Backspace" = .Backspace,
			"Insert" = .Insert,
			"Delete" = .Delete,
			"ArrowRight" = .Right,
			"ArrowLeft" = .Left,
			"ArrowDown" = .Down,
			"ArrowUp" = .Up,
			"PageUp" = .Page_Up,
			"PageDown" = .Page_Down,
			"Home" = .Home,
			"End" = .End,
			"CapsLock" = .Caps_Lock,
			"ScrollLock" = .Scroll_Lock,
			"NumLock" = .Num_Lock,
			"PrintScreen" = .Print_Screen,
			"Pause" = .Pause,

			"F1" = .F1,
			"F2" = .F2,
			"F3" = .F3,
			"F4" = .F4,
			"F5" = .F5,
			"F6" = .F6,
			"F7" = .F7,
			"F8" = .F8,
			"F9" = .F9,
			"F10" = .F10,
			"F11" = .F11,
			"F12" = .F12,

			"ShiftLeft" = .Left_Shift,
			"ControlLeft" = .Left_Control,
			"AltLeft" = .Left_Alt,
			"MetaLeft" = .Left_Super,
			"ShiftRight" = .Right_Shift,
			"ControlRight" = .Right_Control,
			"AltRight" = .Right_Alt,
			"MetaRight" = .Right_Super,
			"ContextMenu" = .Menu,

			"Numpad0" = .NP_0,
			"Numpad1" = .NP_1,
			"Numpad2" = .NP_2,
			"Numpad3" = .NP_3,
			"Numpad4" = .NP_4,
			"Numpad5" = .NP_5,
			"Numpad6" = .NP_6,
			"Numpad7" = .NP_7,
			"Numpad8" = .NP_8,
			"Numpad9" = .NP_9,

			"NumpadDecimal" = .NP_Decimal,
			"NumpadDivide" = .NP_Divide,
			"NumpadMultiply" = .NP_Multiply,
			"NumpadSubtract" = .NP_Subtract,
			"NumpadAdd" = .NP_Add,
			"NumpadEnter" = .NP_Enter,
		}
	}

	res := s.key_from_js_event_key_code[e.key.code]

	if res == .None {
		log.errorf("Unhandled key code: %v", e.key.code)
	}

	return res
}
