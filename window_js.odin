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
	return size_of(Js_State)
}

js_init :: proc(window_state: rawptr, window_width: int, window_height: int, window_title: string,
	               flags: Window_Flags, allocator: runtime.Allocator) {
}

js_shutdown :: proc() {
}

js_window_handle :: proc() -> Window_Handle {
	return {}
}

js_process_events :: proc() {
	
}

js_get_events :: proc() -> []Window_Event {
	return {}
}

js_get_width :: proc() -> int {
	return 0
}

js_get_height :: proc() -> int {
	return 0
}

js_clear_events :: proc() {
}

js_set_position :: proc(x: int, y: int) {
	log.error("set_position not implemented in JS")
}

js_set_size :: proc(w, h: int) {
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

	return false
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
	s = (^Js_State)(state)
}

Js_State :: struct {
	allocator: runtime.Allocator,
}

s: ^Js_State

@(private="package")
HTML_Canvas_ID :: string
