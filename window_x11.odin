// WIP! Does not function yet.
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
	set_flags = x11_set_flags,
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
	flags: Window_Flags,
	allocator: runtime.Allocator,
) {
	s = (^X11_State)(window_state)
	s.allocator = allocator
	s.flags = flags
	s.width = window_width
	s.height = window_height

	display := X.OpenDisplay(nil)

	window := X.CreateSimpleWindow(
		display,
		X.DefaultRootWindow(display),
		0, 0,
		u32(window_width), u32(window_height),
		0,
		0x00000000,
		0x00000000,
	)

	X.StoreName(display, window, frame_cstring(window_title))
	X.SelectInput(display, window, {.KeyPress, .KeyRelease})
	X.MapWindow(display, window)
}

x11_shutdown :: proc() {
}

x11_window_handle :: proc() -> Window_Handle {
	return {}
}

x11_process_events :: proc() {
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
}

x11_set_size :: proc(w, h: int) {
}

x11_get_window_scale :: proc() -> f32 {
	return 1
}

x11_set_flags :: proc(flags: Window_Flags) {
	s.flags = flags
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
	events: [dynamic]Window_Event,
	flags: Window_Flags,
}

s: ^X11_State
