package karl2d

import "base:runtime"

Platform_Interface :: struct #all_or_none {
	state_size: proc() -> int,

	// Process-level setup that has to happen before any window exists: making the process DPI
	// aware, registering a window class, creating the application object and so on. Called by
	// `init_platform`, which is what makes the monitor queries below work before `open_window`.
	//
	// This is also where the platform state pointer is handed over, so everything after this can
	// use it.
	init: proc(
		platform_state: rawptr,
		allocator: runtime.Allocator,
	),

	shutdown: proc(),

	open_window: proc(
		window_width: int,
		window_height: int,
		window_title: string,
		init_options: Window_Options,
	),

	close_window: proc(),
	get_window_render_glue: proc() -> Window_Render_Glue,
	get_events: proc(events: ^[dynamic]Event),
	set_window_title: proc(title: string),
	set_window_position: proc(x: int, y: int),
	get_window_position: proc() -> Vec2,
	set_screen_size: proc(w, h: int),
	get_screen_width: proc() -> int,
	get_screen_height: proc() -> int,
	get_window_scale: proc() -> f32,
	set_window_mode: proc(window_mode: Window_Mode),

	get_monitor_count: proc() -> int,
	get_monitor_size: proc(monitor: int) -> [2]int,
	get_monitor_position: proc(monitor: int) -> [2]int,
	get_monitor_scale: proc(monitor: int) -> f32,

	set_cursor_hidden: proc(hidden: bool),
	is_cursor_hidden: proc() -> bool,
	set_mouse_locked: proc(locked: bool),
	is_mouse_locked: proc() -> bool,
	create_custom_cursor: proc(image: Image, hotspot: [2]int) -> (Custom_Cursor, bool),
	set_cursor: proc(cursor: Cursor),
	destroy_custom_cursor: proc(custom_cursor: Custom_Cursor),

	is_gamepad_active: proc(gamepad: int) -> bool,
	get_gamepad_axis: proc(gamepad: int, axis: Gamepad_Axis) -> f32,
	set_gamepad_vibration: proc(gamepad: int, left: f32, right: f32),

	open_url: proc(url: string) -> bool,

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
	make_context: proc(
		state: ^Window_Render_Glue_State,
		init_options: Rendering_Options,
	) -> bool,
	present: proc(state: ^Window_Render_Glue_State),
	destroy: proc(state: ^Window_Render_Glue_State),
	viewport_resized: proc(state: ^Window_Render_Glue_State),
}