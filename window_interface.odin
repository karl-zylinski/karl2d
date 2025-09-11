package karl2d

import "base:runtime"

Window_Interface :: struct {
	state_size: proc() -> int,
	init: proc(window_state: rawptr, window_width: int, window_height: int, window_title: string, 
	           flags: Window_Flags, allocator: runtime.Allocator),
	shutdown: proc(),
	window_handle: proc() -> Window_Handle,
	process_events: proc(),
	get_events: proc() -> []Window_Event,
	clear_events: proc(),
	set_position: proc(x: int, y: int),
	set_size: proc(w, h: int),
	set_flags: proc(flags: Window_Flags),

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