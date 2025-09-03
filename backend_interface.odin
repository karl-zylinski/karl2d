package karl2d

Rendering_Backend_Interface :: struct {
	state_size: proc() -> int,
	init: proc(state: rawptr, window_handle: Window_Handle, swapchain_width, swapchain_height: int, allocator := context.allocator),
	shutdown: proc(),
	clear: proc(color: Color),
	present: proc(),
	draw: proc(shader: Shader, texture: Texture_Handle, view_proj: Mat4, vertex_buffer: []u8),
	set_internal_state: proc(state: rawptr),

	load_texture: proc(data: []u8, width: int, height: int) -> Texture_Handle,
	destroy_texture: proc(handle: Texture_Handle),

	load_shader: proc(shader: string, layout_formats: []Shader_Input_Format = {}) -> Shader,
	destroy_shader: proc(shader: Shader),

	get_swapchain_width: proc() -> int,
	get_swapchain_height: proc() -> int,

	batch_vertex: proc(v: Vec2, uv: Vec2, color: Color),
}
