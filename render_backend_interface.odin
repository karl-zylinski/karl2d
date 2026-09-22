package karl2d

import "base:runtime"

Shader_Constant_Desc :: struct {
	name: string,
	size: int,
}

Shader_Texture_Bindpoint_Desc :: struct {
	name: string,
}

Shader_Desc :: struct {
	constants: []Shader_Constant_Desc,
	texture_bindpoints: []Shader_Texture_Bindpoint_Desc,
	inputs: []Shader_Input,
}

// Used by draw calls to keep track of what things changed since the previous draw call. The render
// backend uses this to figure out what state it needs to set.
Draw_Call_Change :: enum {
	Shader,
	Constants,
	Textures,
	Render_Target,
	Scissor,
	Blend_Mode,
}

// The first draw call in a batch uses this. It means that all the state needs to be set up by the
// render backend.
DRAW_CALL_CHANGE_ALL :: ~bit_set[Draw_Call_Change]{}

// A chunk of drawing work that shares enough state to be able to draw together. Points out the
// range in the vertex buffer that the draw call will use.
//
// The rendering backend is handed an array of these. See the `draw` proc in
// `Render_Backend_Interface`. Within that array, each draw call will have the `changed` bit_set
// filled out so that it clearly states which rendering state that the draw call needs the backend
// to update.
Draw_Call :: struct {
	// Says which part of the vertex buffer handed to `Render_Backend_Interface.draw` that this draw
	// call uess.
	vertex_offset: int,
	vertex_count: int,

	shader: Shader_Handle,
	vertex_size: int,
	constants: []Shader_Constant_Location,

	// A clone of the constants data of the shader, snapshotted at the time when the draw call was
	// created. Additionally, things like the Karl2D view-project-matrix will be filled in here.
	constants_data: []u8,
	textures: []Texture_Handle,

	render_target: Render_Target_Handle,
	scissor: Maybe(Rect),
	blend_mode: Blend_Mode,

	// What fields in this draw call changed from the previous one? The backend will look at this
	// and only change GPU state that actually needs changing.
	//
	// Note: If the backend "skips" a draw call for whatever reason, then add the `changed` bit_set
	// to the one in the next draw call. That way no state setup is missed.
	changed: bit_set[Draw_Call_Change],
}

Render_Backend_Interface :: struct #all_or_none {
	state_size: proc() -> int,
	
	init: proc(
		state: rawptr,
		glue: Window_Render_Glue,
		swapchain_width: int,
		swapchain_height: int,
		options: Init_Options,
		allocator: runtime.Allocator,
	),

	shutdown: proc(),
	clear: proc(render_target: Render_Target_Handle, color: Color),
	present: proc(),
	
	draw: proc(vertex_buffer: []u8, draw_calls: []Draw_Call),

	set_internal_state: proc(state: rawptr),

	create_texture: proc(width: int, height: int, format: Pixel_Format) -> (Texture_Handle, bool),
	load_texture: proc(
		data: []u8,
		width: int,
		height: int,
		format: Pixel_Format,
	) -> (Texture_Handle, bool),
	update_texture: proc(handle: Texture_Handle, data: []u8, rect: Rect, pitch: int) -> bool,
	destroy_texture: proc(handle: Texture_Handle),
	texture_needs_vertical_flip: proc(handle: Texture_Handle) -> bool,

	create_render_texture: proc(
		width: int,
		height: int,
	) -> (Texture_Handle, Render_Target_Handle, bool),
	destroy_render_target: proc(render_texture: Render_Target_Handle),
	
	set_texture_filter: proc(
		handle: Texture_Handle,
		scale_down_filter: Texture_Filter,
		scale_up_filter: Texture_Filter,
		mip_filter: Texture_Filter,
	),

	load_shader: proc(
		vertex_shader_data: []byte,
		pixel_shader_data: []byte,
		desc_allocator: runtime.Allocator,
		layout_formats: []Pixel_Format = {},
	) -> (
		handle: Shader_Handle,
		desc: Shader_Desc,
		ok: bool,
	),

	destroy_shader: proc(shader: Shader_Handle),

	resize_swapchain: proc(width, height: int),
	get_swapchain_width: proc() -> int,
	get_swapchain_height: proc() -> int,

	default_shader_vertex_source: proc() -> []byte,
	default_shader_fragment_source: proc() -> []byte,

	// The z range the backend's clip space uses, so the projection matrix can map the user's
	// `depth_range_min`/`depth_range_max` onto it. Called before `init`, so this must return a
	// constant and not touch any backend state.
	get_depth_clip_range: proc() -> (min: f32, max: f32),
}
