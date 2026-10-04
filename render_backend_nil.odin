#+private package
#+vet explicit-allocators
package karl2d

import "log"

RENDER_BACKEND_NIL :: Render_Backend_Interface {
	state_type = RBNil_State,
	init = rbnil_init,
	shutdown = rbnil_shutdown,
	clear = rbnil_clear,
	present = rbnil_present,
	draw = rbnil_draw,
	resize_swapchain = rbnil_resize_swapchain,
	get_swapchain_width = rbnil_get_swapchain_width,
	get_swapchain_height = rbnil_get_swapchain_height,
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
) -> (Texture_Handle, bool) {
	return Texture_Handle(rbnil_handle(s)), true
}

rbnil_load_texture :: proc(
	s: ^RBNil_State,
	data: []u8,
	width: int,
	height: int,
	format: Pixel_Format,
) -> (Texture_Handle, bool) {
	return Texture_Handle(rbnil_handle(s)), true
}

rbnil_update_texture :: proc(
	s: ^RBNil_State,
	th: Texture_Handle,
	data: []u8,
	rect: Rect,
	pitch: int,
) -> bool {
	return true
}

rbnil_destroy_texture :: proc(s: ^RBNil_State, th: Texture_Handle) {
}

rbnil_texture_needs_vertical_flip :: proc(s: ^RBNil_State, th: Texture_Handle) -> bool {
	return false
}

rbnil_create_render_texture :: proc(
	s: ^RBNil_State,
	width: int,
	height: int,
) -> (Texture_Handle, Render_Target_Handle, bool) {
	return Texture_Handle(rbnil_handle(s)), Render_Target_Handle(rbnil_handle(s)), true
}

rbnil_destroy_render_target :: proc(s: ^RBNil_State, render_target: Render_Target_Handle) {
	
}

rbnil_set_texture_filter :: proc(
	s: ^RBNil_State,
	th: Texture_Handle,
	scale_down_filter: Texture_Filter,
	scale_up_filter: Texture_Filter,
	mip_filter: Texture_Filter,
) {
}

// The nil backend does not parse shader source. It reports the same layout the built-in default
// shader uses, which is what the batching code in karl2d.odin needs in order to lay out vertices.
// That's enough to run the library headless (tests, benchmarks, dedicated servers). Custom shaders
// with a different vertex layout will be reported as if they had the default one.
rbnil_load_shader :: proc(
	s: ^RBNil_State,
	vs_source: []byte,
	fs_source: []byte,
	desc_allocator := frame_allocator,
	layout_formats: []Pixel_Format = {},
) -> (
	handle: Shader_Handle,
	desc: Shader_Desc,
	ok: bool,
) {
	inputs := make([]Shader_Input, 3, desc_allocator)
	inputs[0] = { name = "position", register = 0, type = .Vec2, format = .RG_32_Float }
	inputs[1] = { name = "texcoord", register = 1, type = .Vec2, format = .RG_32_Float }
	inputs[2] = { name = "color",    register = 2, type = .Vec4, format = .RGBA_8_Norm }

	for &input, input_idx in inputs {
		if input_idx < len(layout_formats) && layout_formats[input_idx] != .Unknown {
			input.format = layout_formats[input_idx]
		}
	}

	constants := make([]Shader_Constant_Desc, 1, desc_allocator)
	constants[0] = { name = "view_projection", size = size_of(matrix[4,4]f32) }

	texture_bindpoints := make([]Shader_Texture_Bindpoint_Desc, 1, desc_allocator)
	texture_bindpoints[0] = { name = "tex" }

	return Shader_Handle(rbnil_handle(s)), {
		constants = constants,
		texture_bindpoints = texture_bindpoints,
		inputs = inputs,
	}, true
}

rbnil_destroy_shader :: proc(s: ^RBNil_State, h: Shader_Handle) {
}

rbnil_default_shader_vertex_source :: proc() -> []byte {
	return {}
}

rbnil_default_shader_fragment_source :: proc() -> []byte {
	return {}
}

rbnil_get_depth_clip_range :: proc() -> (min: f32, max: f32) {
	return 0, 1
}

