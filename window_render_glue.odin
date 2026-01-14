package karl2d

Window_Render_Glue_State :: struct {}

// Sometimes referred to as the "render context". This is the stuff that glues together a certain
// windowing API with a certain rendering API.
Window_Render_Glue :: struct {
	using state: ^Window_Render_Glue_State,
	get_window_handle: proc(state: ^Window_Render_Glue_State) -> Window_Handle,
	make_context: proc(state: ^Window_Render_Glue_State) -> bool,
	present: proc(state: ^Window_Render_Glue_State),
	destroy: proc(state: ^Window_Render_Glue_State),
	viewport_resized: proc(state: ^Window_Render_Glue_State),
}