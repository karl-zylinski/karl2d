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

	// The browser window probably has some other size than what was sent in.
	if .Resizable in flags {
		add_window_event_listener(.Resize, js_window_event_resize)
		update_canvas_size(s.canvas_id)
	} else {
		js_set_size(window_width, window_height)
	}

	add_canvas_event_listener(.Mouse_Move, js_window_event_mouse_move)
	add_canvas_event_listener(.Mouse_Down, js_window_event_mouse_down)
	add_canvas_event_listener(.Mouse_Up, js_window_event_mouse_up)

	add_window_event_listener(.Key_Down, js_window_event_key_down)
	add_window_event_listener(.Key_Up, js_window_event_key_up)
}

add_window_event_listener :: proc(evt: js.Event_Kind, callback: proc(e: js.Event)) {
	js.add_window_event_listener(
		evt, 
		nil, 
		callback,
		true,
	)
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

js_window_event_key_down :: proc(e: js.Event) {
	if e.key.repeat {
		return
	}

	key := key_from_js_event(e)
	append(&s.events, Window_Event_Key_Went_Down {
		key = key,
	})
}

js_window_event_key_up :: proc(e: js.Event) {
	key := key_from_js_event(e)
	append(&s.events, Window_Event_Key_Went_Up {
		key = key,
	})
}

key_from_js_event :: proc(e: js.Event) -> Keyboard_Key {
	log.info(e)
	switch e.key.code {
	case "ArrowUp": return .Up
	case "ArrowDown": return .Down
	case "ArrowLeft": return .Left
	case "ArrowRight": return .Right
	case "Enter": return .Enter
	}
	return .None
}

js_window_event_resize :: proc(e: js.Event) {
	update_canvas_size(s.canvas_id)
}

js_window_event_mouse_move :: proc(e: js.Event) {
	dpi := js.device_pixel_ratio()
	append(&s.events, Window_Event_Mouse_Move {
		position = {f32(e.mouse.client.x) * f32(dpi), f32(e.mouse.client.y) * f32(dpi)},
	})
}

js_window_event_mouse_down :: proc(e: js.Event) {
	append(&s.events, Window_Event_Mouse_Button_Went_Down {
		button = .Left,
	})
}

js_window_event_mouse_up :: proc(e: js.Event) {
	append(&s.events, Window_Event_Mouse_Button_Went_Up {
		button = .Left,
	})
}

update_canvas_size :: proc(canvas_id: HTML_Canvas_ID) {
	rect := js.get_bounding_client_rect(canvas_id)
	dpi := js.device_pixel_ratio()

	width := f64(rect.width) * dpi
	height := f64(rect.height) * dpi

	js.set_element_key_f64(canvas_id, "width", width)
	js.set_element_key_f64(canvas_id, "height", height)

	s.width = int(width)
	s.height = int(height)

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

js_process_events :: proc() {
	//for gamepad_idx in 0..<4 {
		/*prev_state := s.gamepad_state[gamepad_idx]
		if js.get_gamepad_state(s.gamepad_state[gamepad_idx], &gs) && gs.connected {
			log.info(gs)
		}*/
//	}

	/*


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
		
		*/
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
	log.error("set_position not implemented in JS")
}

js_set_size :: proc(w, h: int) {
	dpi := js.device_pixel_ratio()

	width := f64(w) * dpi
	height := f64(h) * dpi

	s.width = int(width)
	s.height = int(height)

	js.set_element_key_f64(s.canvas_id, "width", width)
	js.set_element_key_f64(s.canvas_id, "height", height)
}

js_get_window_scale :: proc() -> f32 {
	return f32(js.device_pixel_ratio())
}

js_set_flags :: proc(flags: Window_Flags) {
}

js_is_gamepad_active :: proc(gamepad: int) -> bool {
	if gamepad < 0 || gamepad >= MAX_GAMEPADS {
		return false
	}

	gs: js.Gamepad_State	
	return js.get_gamepad_state(gamepad, &gs) && gs.connected 
}

js_get_gamepad_axis :: proc(gamepad: int, axis: Gamepad_Axis) -> f32 {
	if gamepad < 0 || gamepad >= MAX_GAMEPADS {
		return 0
	}

	return 0
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

JS_State :: struct {
	allocator: runtime.Allocator,
	canvas_id: HTML_Canvas_ID,
	width: int,
	height: int,
	events: [dynamic]Window_Event,
	gamepad_state: [MAX_GAMEPADS]js.Gamepad_State,
}

s: ^JS_State

@(private="package")
HTML_Canvas_ID :: string
