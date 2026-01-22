package karl2d

import "base:runtime"

Platform_Interface :: struct #all_or_none {
	state_size: proc() -> int,

	init: proc(
		platform_state: rawptr,
		window_width: int,
		window_height: int,
		window_title: string,
		init_options: Init_Options,
		allocator: runtime.Allocator,
	),

	shutdown: proc(),
	get_window_render_glue: proc() -> Window_Render_Glue,
	get_events: proc(events: ^[dynamic]Event),
	set_window_position: proc(x: int, y: int),
	set_screen_size: proc(w, h: int),
	get_screen_width: proc() -> int,
	get_screen_height: proc() -> int,
	get_window_scale: proc() -> f32,
	set_window_mode: proc(window_mode: Window_Mode),

	is_gamepad_active: proc(gamepad: int) -> bool,
	get_gamepad_axis: proc(gamepad: int, axis: Gamepad_Axis) -> f32,
	set_gamepad_vibration: proc(gamepad: int, left: f32, right: f32),

	set_internal_state: proc(state: rawptr),
}

Window_Render_Glue_State :: struct {}

// Sometimes referred to as the "render context". This is the stuff that glues together a certain
// windowing API with a certain rendering API.
//
// Some Windowing + Render Backend combos don't need all these procs. Some of them simply pass a
// window handle in the state pointer and don't implement any of the procs. See Windows + D3D11 for
// such an example. See Windows + GL or Linux + GL for an example of more complicated setups.
Window_Render_Glue :: struct {
	using state: ^Window_Render_Glue_State,
	make_context: proc(state: ^Window_Render_Glue_State) -> bool,
	present: proc(state: ^Window_Render_Glue_State),
	destroy: proc(state: ^Window_Render_Glue_State),
	viewport_resized: proc(state: ^Window_Render_Glue_State),
}