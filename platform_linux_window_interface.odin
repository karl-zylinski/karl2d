#+build linux
#+private package
package karl2d

Linux_Window_State :: struct {}

Linux_Window_Interface :: struct #all_or_none {
	state_type: typeid,

	// Reports whether this windowing system can be used, by loading its shared libraries and
	// connecting to its server. The connection is thrown away again. But the libraries stay loaded
	// so that `init` can use them.
	is_available: proc() -> (failure_reason: string, ok: bool),

	init: proc(
		s: ^Linux_Window_State,
		screen_width: int,
		screen_height: int,
		window_title: string,
		init_options: Init_Options,
		allocator: Allocator,
	),

	shutdown: proc(s: ^Linux_Window_State),
	get_window_render_glue: proc(s: ^Linux_Window_State) -> ^Window_Render_Glue,
	get_events: proc(s: ^Linux_Window_State, events: ^[dynamic]Event),
	before_present: proc(s: ^Linux_Window_State),
	set_title: proc(s: ^Linux_Window_State, title: string),
	set_position: proc(s: ^Linux_Window_State, x: int, y: int),
	get_position: proc(s: ^Linux_Window_State) -> Vec2,
	set_screen_size: proc(s: ^Linux_Window_State, w, h: int),
	get_screen_width: proc(s: ^Linux_Window_State) -> int,
	get_screen_height: proc(s: ^Linux_Window_State) -> int,
	get_window_scale: proc(s: ^Linux_Window_State) -> f32,
	set_window_mode: proc(s: ^Linux_Window_State, window_mode: Window_Mode),
	set_window_icon: proc(s: ^Linux_Window_State, image: Image) -> bool,
	set_cursor_hidden: proc(s: ^Linux_Window_State, hidden: bool),
	is_cursor_hidden: proc(s: ^Linux_Window_State) -> bool,
	set_mouse_locked: proc(s: ^Linux_Window_State, locked: bool),
	is_mouse_locked: proc(s: ^Linux_Window_State) -> bool,

	create_custom_cursor: proc(
		s: ^Linux_Window_State,
		image: Image,
		hotspot: [2]int,
	) -> (
		Custom_Cursor,
		bool,
	),
	
	set_cursor: proc(s: ^Linux_Window_State, cursor: Cursor),
	destroy_custom_cursor: proc(s: ^Linux_Window_State, custom_cursor: Custom_Cursor),
}