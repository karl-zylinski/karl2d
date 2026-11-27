#+private package
#+vet explicit-allocators
package karl2d

import "log"
import sc "shader_compiler"

RENDER_BACKEND_NIL :: Render_Backend_Interface {
	state_type = RBNil_State,
	init = rbnil_init,
	shutdown = rbnil_shutdown,
	clear = rbnil_clear,
	present = rbnil_present,
	set_vsync = rbnil_set_vsync,
	draw = rbnil_draw,
	resize_swapchain = rbnil_resize_swapchain,
	get_swapchain_width = rbnil_get_swapchain_width,
	get_swapchain_height = rbnil_get_swapchain_height,
	create_texture = rbnil_create_texture,
	load_texture = rbnil_load_texture,
	update_texture = rbnil_update_texture,
	generate_mipmap = rbnil_generate_mipmap,
	destroy_texture = rbnil_destroy_texture,
	flip_render_textures = false,
	create_render_texture = rbnil_create_render_texture,
	destroy_render_target = rbnil_destroy_render_target,
	shader_target = .GLSL_330,
	load_shader = rbnil_load_shader,
	destroy_shader = rbnil_destroy_shader,
	read_backbuffer = rbnil_read_backbuffer,

	get_depth_clip_range = rbnil_get_depth_clip_range,
}

// The nil backend hands out handles from a monotonic counter. Nothing ever looks the handles up, we
// just need them to be non-zero: a zero handle means TEXTURE_NONE/SHADER_NONE and makes the drawing
// procedures in karl2d.odin bail out early.
rbnil_handle :: proc(s: ^RBNil_State) -> Handle {
	h := Handle { idx = s.next_handle_idx, gen = 1 }
	s.next_handle_idx += 1
	return h
}

RBNil_State :: struct {
	using _: Render_Backend_State,
	next_handle_idx: u32,
	swapchain_width: int,
	swapchain_height: int,
}

rbnil_init :: proc(
	s: ^RBNil_State,
	glue: ^Window_Render_Glue,
	swapchain_width,
	swapchain_height: int, 
	options: Init_Options,
	allocator := context.allocator,
) {
	log.info("Render Backend nil init")
	s.next_handle_idx = 1
	s.swapchain_width = swapchain_width
	s.swapchain_height = swapchain_height
}

rbnil_shutdown :: proc(s: ^RBNil_State) {
	log.info("Render Backend nil shutdown")
}

rbnil_clear :: proc(s: ^RBNil_State, render_texture: Render_Target_Handle, color: Color) {
}

rbnil_present :: proc(s: ^RBNil_State) {
}

rbnil_set_vsync :: proc(s: ^RBNil_State, enabled: bool) {
}

rbnil_draw :: proc(s: ^RBNil_State, vertex_buffer: []u8, draw_calls: []Draw_Call) {
}

rbnil_resize_swapchain :: proc(s: ^RBNil_State, w, h: int) {
	s.swapchain_width = w
	s.swapchain_height = h
}

rbnil_get_swapchain_width :: proc(s: ^RBNil_State) -> int {
	return s.swapchain_width
}

rbnil_get_swapchain_height :: proc(s: ^RBNil_State) -> int {
	return s.swapchain_height
}

rbnil_create_texture :: proc(
	s: ^RBNil_State,
	width: int,
	height: int,
	format: Pixel_Format,
	mip_levels: int,
) -> (Render_Backend_Texture, bool) {
	return Render_Backend_Texture(rbnil_handle(s)), true
}

rbnil_load_texture :: proc(
	s: ^RBNil_State,
	data: [][]u8,
	width: int,
	height: int,
	format: Pixel_Format,
) -> (Render_Backend_Texture, bool) {
	return Render_Backend_Texture(rbnil_handle(s)), true
}

rbnil_update_texture :: proc(
	s: ^RBNil_State,
	th: Render_Backend_Texture,
	data: []u8,
	rect: Rect,
	pitch: int,
	mip_level: int,
) -> bool {
	return true
}

rbnil_generate_mipmap :: proc(s: ^RBNil_State, th: Render_Backend_Texture) -> bool {
	return true
}

rbnil_destroy_texture :: proc(s: ^RBNil_State, th: Render_Backend_Texture) {
}

rbnil_create_render_texture :: proc(
	s: ^RBNil_State,
	width: int,
	height: int,
	mip_levels: int,
) -> (Render_Backend_Texture, Render_Target_Handle, bool) {
	return Render_Backend_Texture(rbnil_handle(s)), Render_Target_Handle(rbnil_handle(s)), true
}

rbnil_destroy_render_target :: proc(s: ^RBNil_State, render_target: Render_Target_Handle) {
	
}

// TODO-UPDATE-COMMENT: The vertex layout now comes from the shader compiler, so the nil backend only hands out a handle.
//---
// The nil backend does not parse shader source. It reports the same layout the built-in default
// shader uses, which is what the batching code in karl2d.odin needs in order to lay out vertices.
// That's enough to run the library headless (tests, benchmarks, dedicated servers). Custom shaders
// with a different vertex layout will be reported as if they had the default one.
rbnil_load_shader :: proc(
	s: ^RBNil_State,
	compiled: sc.Compiled_Shader,
	inputs: []Shader_Input,
) -> (
	handle: Shader_Handle,
	ok: bool,
) {
	return Shader_Handle(rbnil_handle(s)), true
}

rbnil_destroy_shader :: proc(s: ^RBNil_State, h: Shader_Handle) {
}

rbnil_read_backbuffer :: proc(s: ^RBNil_State, pixels: []u8) -> bool {
	return false
}

rbnil_get_depth_clip_range :: proc() -> (min: f32, max: f32) {
	return 0, 1
}

