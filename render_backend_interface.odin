package karl2d

Shader_Constant_Buffer_Desc :: struct {
	name: string,
	size: int,
	variables: []Shader_Constant_Buffer_Variable_Desc,
}

Shader_Constant_Buffer_Variable_Desc :: struct {
	name: string,
	loc: Shader_Constant_Location,
}

Shader_Desc :: struct {
	constant_buffers: []Shader_Constant_Buffer_Desc,
	inputs: []Shader_Input,
}

Render_Backend_Interface :: struct {
	state_size: proc() -> int,
	init: proc(state: rawptr, window_handle: Window_Handle, swapchain_width, swapchain_height: int, allocator := context.allocator),
	shutdown: proc(),
	clear: proc(color: Color),
	present: proc(),
	draw: proc(shader: Shader, texture: Texture_Handle, view_proj: Mat4, scissor: Maybe(Rect), vertex_buffer: []u8),
	set_internal_state: proc(state: rawptr),

	load_texture: proc(data: []u8, width: int, height: int) -> Texture_Handle,
	destroy_texture: proc(handle: Texture_Handle),

	load_shader: proc(shader_source: string, desc_allocator := context.temp_allocator, layout_formats: []Pixel_Format = {}) -> (handle: Shader_Handle, desc: Shader_Desc),
	destroy_shader: proc(shader: Shader_Handle),

	resize_swapchain: proc(width, height: int),
	get_swapchain_width: proc() -> int,
	get_swapchain_height: proc() -> int,

	batch_vertex: proc(v: Vec2, uv: Vec2, color: Color),
}
