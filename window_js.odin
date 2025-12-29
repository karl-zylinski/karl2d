#+build js
#+private file

package karl2d

@(private="package")
WINDOW_INTERFACE_JS :: Window_Interface {
	state_size = js_state_size,
	init = js_init,
	shutdown = js_shutdown,
	window_handle = js_window_handle,
	process_events = js_process_events,
	get_events = js_get_events,
	get_width = js_get_width,
	get_height = js_get_height,
	clear_events = js_clear_events,
	set_position = js_set_position,
	set_size = js_set_size,
	get_window_scale = js_get_window_scale,
	set_flags = js_set_flags,
	is_gamepad_active = js_is_gamepad_active,
	get_gamepad_axis = js_get_gamepad_axis,
	set_gamepad_vibration = js_set_gamepad_vibration,

	set_internal_state = js_set_internal_state,
}

import "core:sys/wasm/js"
import "base:runtime"
import "core:log"
import "core:fmt"

js_state_size :: proc() -> int {
	return size_of(JS_State)
}

js_init :: proc(
	window_state: rawptr,
	window_width: int,
	window_height: int,
	window_title: string,
	flags: Window_Flags,
	allocator: runtime.Allocator,
) {
	s = (^JS_State)(window_state)
	s.allocator = allocator
	s.canvas_id = "webgl-canvas"
	s.flags = flags

	js.set_document_title(window_title)

	// The browser window probably has some other size than what was sent in.
	if .Resizable in flags {
		add_window_event_listener(.Resize, js_event_window_resize)
		update_canvas_size(s.canvas_id)
	} else {
		js_set_size(window_width, window_height)
	}

	add_canvas_event_listener(.Mouse_Move, js_event_mouse_move)
	add_canvas_event_listener(.Mouse_Down, js_event_mouse_down)
	add_canvas_event_listener(.Mouse_Up, js_event_mouse_up)

	add_window_event_listener(.Key_Down, js_event_key_down)
	add_window_event_listener(.Key_Up, js_event_key_up)
}

js_event_key_down :: proc(e: js.Event) {
	if e.key.repeat {
		return
	}

	key := key_from_js_event(e)
	append(&s.events, Window_Event_Key_Went_Down {
		key = key,
	})
}

js_event_key_up :: proc(e: js.Event) {
	key := key_from_js_event(e)
	append(&s.events, Window_Event_Key_Went_Up {
		key = key,
	})
}

js_event_window_resize :: proc(e: js.Event) {
	update_canvas_size(s.canvas_id)
}

js_event_mouse_move :: proc(e: js.Event) {
	append(&s.events, Window_Event_Mouse_Move {
		position = {f32(e.mouse.client.x), f32(e.mouse.client.y)},
	})
}

js_event_mouse_down :: proc(e: js.Event) {
	button := Mouse_Button.Left

	if e.mouse.button == 2 {
		button = .Right
	}

	if e.mouse.button == 1 {
		button = .Middle 
	}

	append(&s.events, Window_Event_Mouse_Button_Went_Down {
		button = button,
	})
}

js_event_mouse_up :: proc(e: js.Event) {
	button := Mouse_Button.Left

	if e.mouse.button == 2 {
		button = .Right
	}

	if e.mouse.button == 1 {
		button = .Middle 
	}

	append(&s.events, Window_Event_Mouse_Button_Went_Up {
		button = button,
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

	append(&s.events, Window_Event_Resize {
		width = int(width),
		height = int(height),
	})
}

js_shutdown :: proc() {
}

js_window_handle :: proc() -> Window_Handle {
	return Window_Handle(&s.canvas_id)
}

// This works for XBox controller -- does it work for PlayStation?
KARL2D_GAMEPAD_BUTTON_FROM_JS :: [Gamepad_Button]int {
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

js_process_events :: proc() {
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
				append(&s.events, Window_Event_Gamepad_Button_Went_Down {
					gamepad = gamepad_idx,
					button = button,
				})
			}

			if ps.buttons[js_idx].pressed && !ns.buttons[js_idx].pressed {
				append(&s.events, Window_Event_Gamepad_Button_Went_Up {
					gamepad = gamepad_idx,
					button = button,
				})
			}
		}

		s.gamepad_state[gamepad_idx] = ns
	}
}

js_get_events :: proc() -> []Window_Event {
	return s.events[:]
}

js_get_width :: proc() -> int {
	return s.width
}

js_get_height :: proc() -> int {
	return s.height
}

js_clear_events :: proc() {
	runtime.clear(&s.events)
}

js_set_position :: proc(x: int, y: int) {
	buf: [256]u8
	js.set_element_style(s.canvas_id, "margin-top", fmt.bprintf(buf[:], "%vpx", x))
	js.set_element_style(s.canvas_id, "margin-left", fmt.bprintf(buf[:], "%vpx", y))
}

js_set_size :: proc(w, h: int) {
	s.width = w
	s.height = h
	js.set_element_key_f64(s.canvas_id, "width", f64(w))
	js.set_element_key_f64(s.canvas_id, "height", f64(h))
}

js_get_window_scale :: proc() -> f32 {
	return f32(js.device_pixel_ratio())
}

js_set_flags :: proc(flags: Window_Flags) {
	if .Resizable in (flags ~ s.flags) {
		if .Resizable in flags {
			add_window_event_listener(.Resize, js_event_window_resize)
			update_canvas_size(s.canvas_id)
		} else {
			remove_window_event_listener(.Resize, js_event_window_resize)
			js_set_size(s.width, s.height)
		}
	}

	s.flags = flags
}

js_is_gamepad_active :: proc(gamepad: int) -> bool {
	if gamepad < 0 || gamepad >= MAX_GAMEPADS {
		return false
	}

	return s.gamepad_state[gamepad].connected
}

js_get_gamepad_axis :: proc(gamepad: int, axis: Gamepad_Axis) -> f32 {
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

js_set_gamepad_vibration :: proc(gamepad: int, left: f32, right: f32) {
	if gamepad < 0 || gamepad >= MAX_GAMEPADS {
		return
	}
}

js_set_internal_state :: proc(state: rawptr) {
	assert(state != nil)
	s = (^JS_State)(state)
}

@(private="package")
HTML_Canvas_ID :: string

JS_State :: struct {
	allocator: runtime.Allocator,
	canvas_id: HTML_Canvas_ID,
	width: int,
	height: int,
	events: [dynamic]Window_Event,
	gamepad_state: [MAX_GAMEPADS]js.Gamepad_State,
	flags: Window_Flags,
}

s: ^JS_State

key_from_js_event :: proc(e: js.Event) -> Keyboard_Key {
	switch e.key.code {
	case "Digit1": return .N1
	case "Digit2": return .N2
	case "Digit3": return .N3
	case "Digit4": return .N4
	case "Digit5": return .N5
	case "Digit6": return .N6
	case "Digit7": return .N7
	case "Digit8": return .N8
	case "Digit9": return .N9
	case "Digit0": return .N0

	case "KeyA": return .A
	case "KeyB": return .B
	case "KeyC": return .C
	case "KeyD": return .D
	case "KeyE": return .E
	case "KeyF": return .F
	case "KeyG": return .G
	case "KeyH": return .H
	case "KeyI": return .I
	case "KeyJ": return .J
	case "KeyK": return .K
	case "KeyL": return .L
	case "KeyM": return .M
	case "KeyN": return .N
	case "KeyO": return .O
	case "KeyP": return .P
	case "KeyQ": return .Q
	case "KeyR": return .R
	case "KeyS": return .S
	case "KeyT": return .T
	case "KeyU": return .U
	case "KeyV": return .V
	case "KeyW": return .W
	case "KeyX": return .X
	case "KeyY": return .Y
	case "KeyZ": return .Z

	case "Quote":         return .Apostrophe
	case "Comma":         return .Comma
	case "Minus":         return .Minus
	case "Period":        return .Period
	case "Slash":         return .Slash
	case "Semicolon":     return .Semicolon
	case "Equal":         return .Equal
	case "BracketLeft":   return .Left_Bracket
	case "Backslash":     return .Backslash
	case "IntlBackslash": return .Backslash
	case "BracketRight":  return .Right_Bracket
	case "Backquote":     return .Backtick

	case "Space":       return .Space
	case "Escape":      return .Escape
	case "Enter":       return .Enter
	case "Tab":         return .Tab
	case "Backspace":   return .Backspace
	case "Insert":      return .Insert
	case "Delete":      return .Delete
	case "ArrowRight":  return .Right
	case "ArrowLeft":   return .Left
	case "ArrowDown":   return .Down
	case "ArrowUp":     return .Up
	case "PageUp":      return .Page_Up
	case "PageDown":    return .Page_Down
	case "Home":        return .Home
	case "End":         return .End
	case "CapsLock":    return .Caps_Lock
	case "ScrollLock":  return .Scroll_Lock
	case "NumLock":     return .Num_Lock
	case "PrintScreen": return .Print_Screen
	case "Pause":       return .Pause

	case "F1":  return .F1
	case "F2":  return .F2
	case "F3":  return .F3
	case "F4":  return .F4
	case "F5":  return .F5
	case "F6":  return .F6
	case "F7":  return .F7
	case "F8":  return .F8
	case "F9":  return .F9
	case "F10": return .F10
	case "F11": return .F11
	case "F12": return .F12

	case "ShiftLeft":    return .Left_Shift
	case "ControlLeft":  return .Left_Control
	case "AltLeft":      return .Left_Alt
	case "MetaLeft":     return .Left_Super
	case "ShiftRight":   return .Right_Shift
	case "ControlRight": return .Right_Control
	case "AltRight":     return .Right_Alt
	case "MetaRight":    return .Right_Super
	case "ContextMenu":  return .Menu

	case "Numpad0": return .NP_0
	case "Numpad1": return .NP_1
	case "Numpad2": return .NP_2
	case "Numpad3": return .NP_3
	case "Numpad4": return .NP_4
	case "Numpad5": return .NP_5
	case "Numpad6": return .NP_6
	case "Numpad7": return .NP_7
	case "Numpad8": return .NP_8
	case "Numpad9": return .NP_9

	case "NumpadDecimal":  return .NP_Decimal
	case "NumpadDivide":   return .NP_Divide
	case "NumpadMultiply": return .NP_Multiply
	case "NumpadSubtract": return .NP_Subtract
	case "NumpadAdd":      return .NP_Add
	case "NumpadEnter":    return .NP_Enter
	}

	log.errorf("Unhandled key code: %v", e.key.code)
	return .None
}
