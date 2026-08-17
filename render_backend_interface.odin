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

// The things a draw call can need set up. Which ones it actually needs is worked out by karl2d.odin
Draw_Call_Change :: enum {
	Shader,
	Constants,
	Textures,
	Render_Target,
	Scissor,
	Blend_Mode,
}

// Everything, which is what the first draw call of a `draw` needs: nothing is known about the
// state the device was left in.
DRAW_CALL_CHANGE_ALL :: ~bit_set[Draw_Call_Change]{}

// One chunk of drawing work: a range of the vertex buffer plus the state to draw it with. These
// are created in karl2d.odin as you draw. When it is time to actually draw, the whole array of draw
// calls is handed to the rendering backend, so the backend can skip updating state that doesn't
// change between two draw calls.
Draw_Call :: struct {
	// Where this draw call's vertices are in the vertex buffer passed to `draw`. The offset is in
	// bytes, since each shader has its own vertex size. It is always a multiple of `vertex_size`,
	// so `vertex_offset/vertex_size` is the index of the first vertex.
	vertex_offset: int,
	vertex_count: int,

	// The shader to draw with, and the parts of it the backend needs.
	shader: Shader_Handle,
	vertex_size: int,
	constants: []Shader_Constant_Location,

	// The constant values and textures to draw with. These are the draw call's own copies, not the
	// shader's: a draw call runs long after it was recorded, and the program can change the
	// shader's in between. They also hold what Karl2D itself puts in, such as the view-projection
	// matrix and the texture being drawn.
	constants_data: []u8,
	textures: []Texture_Handle,

	render_target: Render_Target_Handle,
	scissor: Maybe(Rect),
	blend_mode: Blend_Mode,

	// What fields in this draw call changed from the previous one? The backend will look at this
	// and only change GPU state that actually needs changing.
	//
	// Note: If the backend "skips" a draw call for whatever reason, then add the `changed` bit_set
	// to the one in the next draw call. That way nothing is missed.
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

	create_texture: proc(width: int, height: int, format: Pixel_Format) -> Texture_Handle,
	load_texture: proc(data: []u8, width: int, height: int, format: Pixel_Format) -> Texture_Handle,
	update_texture: proc(handle: Texture_Handle, data: []u8, rect: Rect) -> bool,
	destroy_texture: proc(handle: Texture_Handle),
	texture_needs_vertical_flip: proc(handle: Texture_Handle) -> bool,

	create_render_texture: proc(width: int, height: int) -> (Texture_Handle, Render_Target_Handle),
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
