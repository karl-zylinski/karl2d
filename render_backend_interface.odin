package karl2d

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

Render_Backend_Interface :: struct #all_or_none {
	state_size: proc() -> int,
	init: proc(state: rawptr, window_handle: Window_Handle, swapchain_width, swapchain_height: int, allocator := context.allocator),
	shutdown: proc(),
	clear: proc(render_target: Render_Target_Handle, color: Color),
	present: proc(),
	
	draw: proc(
		shader: Shader,
		render_target: Render_Target_Handle,
		bound_textures: []Texture_Handle,
		scissor: Maybe(Rect),
		vertex_buffer: []u8,
	),

	set_internal_state: proc(state: rawptr),

	create_texture: proc(width: int, height: int, format: Pixel_Format) -> Texture_Handle,
	load_texture: proc(data: []u8, width: int, height: int, format: Pixel_Format) -> Texture_Handle,
	update_texture: proc(handle: Texture_Handle, data: []u8, rect: Rect) -> bool,
	destroy_texture: proc(handle: Texture_Handle),

	create_render_texture: proc(width: int, height: int) -> (Texture_Handle, Render_Target_Handle),
	
	set_texture_filter: proc(
		handle: Texture_Handle,
		scale_down_filter: Texture_Filter,
		scale_up_filter: Texture_Filter,
		mip_filter: Texture_Filter,
	),

	load_shader: proc(vertex_shader_source: string, pixel_shader_source: string, desc_allocator := context.temp_allocator, layout_formats: []Pixel_Format = {}) -> (handle: Shader_Handle, desc: Shader_Desc),
	destroy_shader: proc(shader: Shader_Handle),

	resize_swapchain: proc(width, height: int),
	get_swapchain_width: proc() -> int,
	get_swapchain_height: proc() -> int,
	flip_z: proc() -> bool,

	default_shader_vertex_source: proc() -> string,
	default_shader_fragment_source: proc() -> string,
}
