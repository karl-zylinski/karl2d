package karl2d

import "base:runtime"

Platform_State :: struct {}

Platform_Interface :: struct #all_or_none {
	init: proc(
		s: ^Platform_State,
		window_width: int,
		window_height: int,
		window_title: string,
		init_options: Init_Options,
		allocator: runtime.Allocator,
	),

	shutdown: proc(s: ^Platform_State),
	get_window_render_glue: proc(s: ^Platform_State) -> ^Window_Render_Glue,
	get_events: proc(s: ^Platform_State, events: ^[dynamic]Event),
	before_present: proc(s: ^Platform_State),
	set_window_title: proc(s: ^Platform_State, title: string),
	set_window_position: proc(s: ^Platform_State, x: int, y: int),
	get_window_position: proc(s: ^Platform_State) -> Vec2,
	set_screen_size: proc(s: ^Platform_State, w, h: int),
	get_screen_width: proc(s: ^Platform_State) -> int,
	get_screen_height: proc(s: ^Platform_State) -> int,
	get_window_scale: proc(s: ^Platform_State) -> f32,
	set_window_mode: proc(s: ^Platform_State, window_mode: Window_Mode),
	set_window_icon: proc(s: ^Platform_State, image: Image) -> bool,

	set_cursor_hidden: proc(s: ^Platform_State, hidden: bool),
	is_cursor_hidden: proc(s: ^Platform_State) -> bool,
	set_mouse_locked: proc(s: ^Platform_State, locked: bool),
	is_mouse_locked: proc(s: ^Platform_State) -> bool,
	create_custom_cursor: proc(
		s: ^Platform_State,
		image: Image,
		hotspot: [2]int,
	) -> (
		Custom_Cursor,
		bool,
	),
	set_cursor: proc(s: ^Platform_State, cursor: Cursor),
	destroy_custom_cursor: proc(s: ^Platform_State, custom_cursor: Custom_Cursor),

	is_gamepad_active: proc(s: ^Platform_State, gamepad: int) -> bool,
	get_gamepad_axis: proc(s: ^Platform_State, gamepad: int, axis: Gamepad_Axis) -> f32,
	set_gamepad_vibration: proc(s: ^Platform_State, gamepad: int, left: f32, right: f32),

	open_url: proc(s: ^Platform_State, url: string) -> bool,
}

// Sometimes referred to as the "render context". This is the stuff that glues together a certain
// windowing API with a certain rendering API.
//
// Some Windowing + Render Backend combos don't need all these procs. Some of them simply pass a
// window handle as the `Window_Render_Glue` pointer. See Windows + D3D11 for such an example. See
// Windows + GL or Linux + GL for an example of more complicated setups.
Window_Render_Glue :: struct {
	make_context: proc(s: ^Window_Render_Glue, init_options: Init_Options) -> bool,
	present: proc(s: ^Window_Render_Glue),
	destroy: proc(s: ^Window_Render_Glue),
	viewport_resized: proc(s: ^Window_Render_Glue),
}