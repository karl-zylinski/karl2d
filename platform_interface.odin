package karl2d

import "base:runtime"

Platform_Interface :: struct #all_or_none {
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

	is_gamepad_active: proc(gamepad: int) -> bool,
	get_gamepad_axis: proc(gamepad: int, axis: Gamepad_Axis) -> f32,
	set_gamepad_vibration: proc(gamepad: int, left: f32, right: f32),

	set_internal_state: proc(state: rawptr),
}

Event :: union {
	Event_Close_Wanted,
	Event_Key_Went_Down,
	Event_Key_Went_Up,
	Event_Mouse_Move,
	Event_Mouse_Wheel,
	Event_Resize,
	Event_Mouse_Button_Went_Down,
	Event_Mouse_Button_Went_Up,
	Event_Gamepad_Button_Went_Down,
	Event_Gamepad_Button_Went_Up,
	Event_Focused,
	Event_Unfocused,
}

Event_Key_Went_Down :: struct {
	key: Keyboard_Key,
}

Event_Key_Went_Up :: struct {
	key: Keyboard_Key,
}

Event_Mouse_Button_Went_Down :: struct {
	button: Mouse_Button,
}

Event_Mouse_Button_Went_Up :: struct {
	button: Mouse_Button,
}

Event_Gamepad_Button_Went_Down :: struct {
	gamepad: Gamepad_Index,
	button: Gamepad_Button,
}

Event_Gamepad_Button_Went_Up :: struct {
	gamepad: Gamepad_Index,
	button: Gamepad_Button,
}

Event_Close_Wanted :: struct {}

Event_Mouse_Move :: struct {
	position: Vec2,
}

Event_Mouse_Wheel :: struct {
	delta: f32,
}

Event_Resize :: struct {
	width, height: int,
}

Event_Focused :: struct {}

Event_Unfocused :: struct {}
