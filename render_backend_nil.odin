#+private file

package karl2d

@(private="package")
RENDER_BACKEND_NIL :: Render_Backend_Interface {
	state_size = rbnil_state_size,
	init = rbnil_init,
	shutdown = rbnil_shutdown,
	clear = rbnil_clear,
	present = rbnil_present,
	draw = rbnil_draw,
	resize_swapchain = rbnil_resize_swapchain,
	get_swapchain_width = rbnil_get_swapchain_width,
	get_swapchain_height = rbnil_get_swapchain_height,
	set_internal_state = rbnil_set_internal_state,
	create_texture = rbnil_create_texture,
	load_texture = rbnil_load_texture,
	update_texture = rbnil_update_texture,
	destroy_texture = rbnil_destroy_texture,
	texture_needs_vertical_flip = rbnil_texture_needs_vertical_flip,
	create_render_texture = rbnil_create_render_texture,
	destroy_render_target = rbnil_destroy_render_target,
	set_texture_filter = rbnil_set_texture_filter,
	load_shader = rbnil_load_shader,
	destroy_shader = rbnil_destroy_shader,

	default_shader_vertex_source = rbnil_default_shader_vertex_source,
	default_shader_fragment_source = rbnil_default_shader_fragment_source,
}

import "log"

rbnil_state_size :: proc() -> int {
	return 0
}

rbnil_init :: proc(state: rawptr, window_handle: Window_Handle, swapchain_width, swapchain_height: int, allocator := context.allocator) {
	log.info("Render Backend nil init")
}

rbnil_shutdown :: proc() {
	log.info("Render Backend nil shutdown")
}

rbnil_clear :: proc(render_texture: Render_Target_Handle, color: Color) {
}

rbnil_present :: proc() {
}

rbnil_draw :: proc(
	shd: Shader,
	render_texture: Render_Target_Handle,
	bound_textures: []Texture_Handle,
	scissor: Maybe(Rect),
	blend_mode: Blend_Mode,
	vertex_buffer: []u8,
) {
}

rbnil_resize_swapchain :: proc(w, h: int) {
}

rbnil_get_swapchain_width :: proc() -> int {
	return 0
}

rbnil_get_swapchain_height :: proc() -> int {
	return 0
}

rbnil_set_internal_state :: proc(state: rawptr) {
}

rbnil_create_texture :: proc(width: int, height: int, format: Pixel_Format) -> Texture_Handle {
	return {}
}

rbnil_load_texture :: proc(data: []u8, width: int, height: int, format: Pixel_Format) -> Texture_Handle {
	return {}
}

rbnil_update_texture :: proc(th: Texture_Handle, data: []u8, rect: Rect) -> bool {
	return true
}

rbnil_destroy_texture :: proc(th: Texture_Handle) {
}

rbnil_texture_needs_vertical_flip :: proc(th: Texture_Handle) -> bool {
	return false
}

rbnil_create_render_texture :: proc(width: int, height: int) -> (Texture_Handle, Render_Target_Handle) {
	return {}, {}
}

rbnil_destroy_render_target :: proc(render_target: Render_Target_Handle) {
	
}

rbnil_set_texture_filter :: proc(
	th: Texture_Handle,
	scale_down_filter: Texture_Filter,
	scale_up_filter: Texture_Filter,
	mip_filter: Texture_Filter,
) {
}

rbnil_load_shader :: proc(
	vs_source: []byte,
	fs_source: []byte,
	desc_allocator := frame_allocator,
	layout_formats: []Pixel_Format = {},
) -> (
	handle: Shader_Handle,
	desc: Shader_Desc,
) {
	return {}, {}
}

rbnil_destroy_shader :: proc(h: Shader_Handle) {
}

rbnil_default_shader_vertex_source :: proc() -> []byte {
	return {}
}

rbnil_default_shader_fragment_source :: proc() -> []byte {
	return {}
}

