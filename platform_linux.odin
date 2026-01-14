#+build linux
#+private file
package karl2d

import "base:runtime"
import "core:mem"
import "log"
import "core:os"

@(private="package")
PLATFORM_LINUX :: Platform_Interface {
	state_size = linux_state_size,
	init = linux_init,
	shutdown = linux_shutdown,
	get_window_render_glue = linux_get_window_render_glue,
	process_events = linux_process_events,
	after_frame_present = linux_after_frame_present,
	get_events = linux_get_events,
	get_width = linux_get_width,
	get_height = linux_get_height,
	clear_events = linux_clear_events,
	set_position = linux_set_position,
	set_size = linux_set_size,
	get_window_scale = linux_get_window_scale,
	set_window_mode = linux_set_window_mode,
	is_gamepad_active = linux_is_gamepad_active,
	get_gamepad_axis = linux_get_gamepad_axis,
	set_gamepad_vibration = linux_set_gamepad_vibration,
	set_internal_state = linux_set_internal_state,
}

s: ^Linux_State

linux_state_size :: proc() -> int {
	return size_of(Linux_State)
}

linux_init :: proc(
	window_state: rawptr,
	screen_width: int,
	screen_height: int,
	window_title: string,
	options: Init_Options,
	allocator: runtime.Allocator,
) {
	assert(window_state != nil)
	s = (^Linux_State)(window_state)
	xdg_session_type := os.get_env("XDG_SESSION_TYPE", allocator)
	
	if xdg_session_type == "wayland" {
		s.win = LINUX_WINDOW_WAYLAND
	} else {
		s.win = LINUX_WINDOW_X11
	}

	win_state_alloc_error: runtime.Allocator_Error
	s.win_state, win_state_alloc_error = mem.alloc(
		s.win.state_size(),
		allocator = allocator,
	)

	log.assertf(win_state_alloc_error == nil,
		"Failed allocating memory for Linux windowing: %v",
		win_state_alloc_error,
	)

	s.win.init(
		s.win_state,
		screen_width,
		screen_height,
		window_title,
		options,
		allocator,
	)
}

linux_shutdown :: proc() {
	s.win.shutdown()
}

linux_get_window_render_glue :: proc() -> Window_Render_Glue {
	return s.win.get_window_render_glue()
}

linux_process_events :: proc() {
	s.win.process_events()
}

linux_after_frame_present :: proc () {
	s.win.after_frame_present()
}

linux_get_events :: proc() -> []Event {
	return s.win.get_events()
}

linux_get_width :: proc() -> int {
	return s.win.get_width()
}

linux_get_height :: proc() -> int {
	return s.win.get_height()
}

linux_clear_events :: proc() {
	s.win.clear_events()
}

linux_set_position :: proc(x: int, y: int) {
	s.win.set_position(x, y)
}

linux_set_size :: proc(w, h: int) {
	s.win.set_size(w, h)
}

linux_get_window_scale :: proc() -> f32 {
	return s.win.get_window_scale()
}

linux_is_gamepad_active :: proc(gamepad: int) -> bool {
	return false
}

linux_get_gamepad_axis :: proc(gamepad: int, axis: Gamepad_Axis) -> f32 {
	return 0
}

linux_set_gamepad_vibration :: proc(gamepad: int, left: f32, right: f32) {

}

linux_set_internal_state :: proc(state: rawptr) {
	assert(state != nil)
	s = (^Linux_State)(state)
	s.win.set_internal_state(s.win_state)
}

linux_set_window_mode :: proc(window_mode: Window_Mode) {
	s.win.set_window_mode(window_mode)
}

Linux_State :: struct {
	win: Linux_Window_Interface,
	win_state: rawptr,
}

@(private="package")
Linux_Window_Interface :: struct {
	state_size: proc() -> int,

	init: proc(
		window_state: rawptr,
		window_width: int,
		window_height: int,
		window_title: string,
		init_options: Init_Options,
		allocator: runtime.Allocator,
	),

	shutdown: proc(),
	get_window_render_glue: proc() -> Window_Render_Glue,
	process_events: proc(),
	after_frame_present: proc(),
	get_events: proc() -> []Event,
	clear_events: proc(),
	set_position: proc(x: int, y: int),
	set_size: proc(w, h: int),
	get_width: proc() -> int,
	get_height: proc() -> int,
	get_window_scale: proc() -> f32,
	set_window_mode: proc(window_mode: Window_Mode),

	set_internal_state: proc(state: rawptr),
}