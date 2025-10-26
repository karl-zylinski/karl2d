#+build windows, darwin, linux
#+private file

package karl2d

@(private="package")
RENDER_BACKEND_INTERFACE_GL :: Render_Backend_Interface {
	state_size = gl_state_size,
	init = gl_init,
	shutdown = gl_shutdown,
	clear = gl_clear,
	present = gl_present,
	draw = gl_draw,
	resize_swapchain = gl_resize_swapchain,
	get_swapchain_width = gl_get_swapchain_width,
	get_swapchain_height = gl_get_swapchain_height,
	set_internal_state = gl_set_internal_state,
	create_texture = gl_create_texture,
	load_texture = gl_load_texture,
	update_texture = gl_update_texture,
	destroy_texture = gl_destroy_texture,
	load_shader = gl_load_shader,
	destroy_shader = gl_destroy_shader,
}

import "base:runtime"
import gl "vendor:OpenGL"
import glfw "vendor:glfw"

GL_State :: struct {
	width: int,
	height: int,
	allocator: runtime.Allocator,
}

s: ^GL_State

gl_state_size :: proc() -> int {
	return size_of(GL_State)
}

gl_init :: proc(state: rawptr, window_handle: Window_Handle, swapchain_width, swapchain_height: int, allocator := context.allocator) {
	s = (^GL_State)(state)
	s.width = swapchain_width
	s.height = swapchain_height
	s.allocator = allocator

	gl.load_up_to(3, 3, glfw.gl_set_proc_address)

}

gl_shutdown :: proc() {
}

gl_clear :: proc(color: Color) {
}

gl_present :: proc() {
}

gl_draw :: proc(shd: Shader, texture: Texture_Handle, view_proj: Mat4, scissor: Maybe(Rect), vertex_buffer: []u8) {
}

gl_resize_swapchain :: proc(w, h: int) {
}

gl_get_swapchain_width :: proc() -> int {
	return s.width
}

gl_get_swapchain_height :: proc() -> int {
	return s.height
}

gl_set_internal_state :: proc(state: rawptr) {
}

gl_create_texture :: proc(width: int, height: int, format: Pixel_Format) -> Texture_Handle {
	return {}
}

gl_load_texture :: proc(data: []u8, width: int, height: int, format: Pixel_Format) -> Texture_Handle {
	return {}
}

gl_update_texture :: proc(th: Texture_Handle, data: []u8, rect: Rect) -> bool {
	return false
}

gl_destroy_texture :: proc(th: Texture_Handle) {

}

gl_load_shader :: proc(vs_source: string, fs_source: string, desc_allocator := frame_allocator, layout_formats: []Pixel_Format = {}) -> (handle: Shader_Handle, desc: Shader_Desc) {
	vs_id := gl.CreateShader(u32(gl.Shader_Type.VERTEX_SHADER))
	vs_len := i32(len(vs_source))
	vs_cstr := cstring(raw_data(vs_source))
	gl.ShaderSource(vs_id, 1, &vs_cstr, &vs_len)
	gl.CompileShader(vs_id)

	fs_id := gl.CreateShader(u32(gl.Shader_Type.FRAGMENT_SHADER))
	fs_len := i32(len(fs_source))
	fs_cstr := cstring(raw_data(fs_source))
	gl.ShaderSource(fs_id, 1, &fs_cstr, &fs_len)
	gl.CompileShader(fs_id)

	return {}, {}
}

gl_destroy_shader :: proc(h: Shader_Handle) {
	
}