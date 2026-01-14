package karl2d

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