#+build js
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
	set_screen_size = web_set_screen_size,
	get_screen_width = web_get_screen_width,
	get_screen_height = web_get_screen_height,
	set_window_position = web_set_position,
	get_window_scale = web_get_window_scale,
	set_window_mode = web_set_window_mode,
	is_gamepad_active = web_is_gamepad_active,
	get_gamepad_axis = web_get_gamepad_axis,
	set_gamepad_vibration = web_set_gamepad_vibration,

	set_internal_state = web_set_internal_state,
}

import "core:sys/wasm/js"
import "base:runtime"
import "log"

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

	// The browser window probably has some other size than what was sent in.
	switch init_options.window_mode {
	case .Windowed:
		web_set_screen_size(window_width, window_height)
	case .Windowed_Resizable:
		add_window_event_listener(.Resize, web_event_window_resize)
		update_canvas_size(s.canvas_id)
	case .Borderless_Fullscreen:
		log.error("Borderless_Fullscreen not implemented on web, but you can make it happen by using Window_Mode.Windowed_Resizable and putting the game in a fullscreen iframe.")
	}

	s.window_mode = init_options.window_mode

	add_canvas_event_listener(.Mouse_Move, web_event_mouse_move)
	add_canvas_event_listener(.Mouse_Down, web_event_mouse_down)
	add_window_event_listener(.Mouse_Up, web_event_mouse_up)
	add_canvas_event_listener(.Wheel, web_event_mouse_wheel)

	add_window_event_listener(.Key_Down, web_event_key_down)
	add_window_event_listener(.Key_Up, web_event_key_up)
	add_window_event_listener(.Focus, web_event_focus)
	add_window_event_listener(.Blur, web_event_blur)
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
	append(&s.events, Event_Window_Focused {
	})
}

web_event_blur :: proc(e: js.Event) {
	append(&s.events, Event_Window_Unfocused {
	})
}

web_event_window_resize :: proc(e: js.Event) {
	update_canvas_size(s.canvas_id)
}

web_event_mouse_move :: proc(e: js.Event) {
	append(&s.events, Event_Mouse_Move {
		position = {f32(e.mouse.client.x), f32(e.mouse.client.y)},
	})
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

update_canvas_size :: proc(canvas_id: HTML_Canvas_ID) {
	rect := js.get_bounding_client_rect("body")

	width := f64(rect.width)
	height := f64(rect.height) 

	js.set_element_key_f64(canvas_id, "width", width)
	js.set_element_key_f64(canvas_id, "height", height)

	s.width = int(rect.width)
	s.height = int(rect.height)

	append(&s.events, Event_Resize {
		width = int(width),
		height = int(height),
	})
}

web_shutdown :: proc() {
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

	.Left_Shoulder = 5,
	.Left_Trigger = 7,

	.Right_Shoulder = 4,
	.Right_Trigger = 6,

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

web_set_position :: proc(x: int, y: int) {
	log.warn("set_window_position not implemented on web")
}

web_set_screen_size :: proc(w, h: int) {
	s.width = w
	s.height = h
	js.set_element_key_f64(s.canvas_id, "width", f64(w))
	js.set_element_key_f64(s.canvas_id, "height", f64(h))
}

web_get_window_scale :: proc() -> f32 {
	return f32(js.device_pixel_ratio())
}

web_set_window_mode :: proc(window_mode: Window_Mode) {
	if window_mode == .Windowed_Resizable && s.window_mode == .Windowed {
		add_window_event_listener(.Resize, web_event_window_resize)
		update_canvas_size(s.canvas_id)
	} else if window_mode == .Windowed && s.window_mode == .Windowed_Resizable {
		remove_window_event_listener(.Resize, web_event_window_resize)
		web_set_screen_size(s.width, s.height)
	}

	s.window_mode = window_mode
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

	return f32(s.gamepad_state[gamepad].axes[int(axis)])
}

web_set_gamepad_vibration :: proc(gamepad: int, left: f32, right: f32) {
	if gamepad < 0 || gamepad >= MAX_GAMEPADS {
		return
	}
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
	events: [dynamic]Event,
	gamepad_state: [MAX_GAMEPADS]js.Gamepad_State,
	window_mode: Window_Mode,
	key_from_js_event_key_code: map[string]Keyboard_Key,
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
