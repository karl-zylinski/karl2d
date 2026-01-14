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
	window_handle: proc() -> Window_Handle,
	process_events: proc(),
	after_frame_present: proc(),
	get_events: proc() -> []Window_Event,
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

Window_Handle :: distinct uintptr

Window_Event :: union {
	Window_Event_Close_Wanted,
	Window_Event_Key_Went_Down,
	Window_Event_Key_Went_Up,
	Window_Event_Mouse_Move,
	Window_Event_Mouse_Wheel,
	Window_Event_Resize,
	Window_Event_Mouse_Button_Went_Down,
	Window_Event_Mouse_Button_Went_Up,
	Window_Event_Gamepad_Button_Went_Down,
	Window_Event_Gamepad_Button_Went_Up,
	Window_Event_Focused,
	Window_Event_Unfocused,
}

Window_Event_Key_Went_Down :: struct {
	key: Keyboard_Key,
}

Window_Event_Key_Went_Up :: struct {
	key: Keyboard_Key,
}

Window_Event_Mouse_Button_Went_Down :: struct {
	button: Mouse_Button,
}

Window_Event_Mouse_Button_Went_Up :: struct {
	button: Mouse_Button,
}

Window_Event_Gamepad_Button_Went_Down :: struct {
	gamepad: int,
	button: Gamepad_Button,
}

Window_Event_Gamepad_Button_Went_Up :: struct {
	gamepad: int,
	button: Gamepad_Button,
}

Window_Event_Close_Wanted :: struct {}

Window_Event_Mouse_Move :: struct {
	position: Vec2,
}

Window_Event_Mouse_Wheel :: struct {
	delta: f32,
}

Window_Event_Resize :: struct {
	width, height: int,
}

Window_Event_Focused :: struct {

}

Window_Event_Unfocused :: struct {
	
}
