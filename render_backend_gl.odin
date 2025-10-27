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
import hm "handle_map"
import "core:log"
import win32 "core:sys/windows"

GL_State :: struct {
	width: int,
	height: int,
	allocator: runtime.Allocator,
	shaders: hm.Handle_Map(GL_Shader, Shader_Handle, 1024*10),
	dc: win32.HDC,
}

GL_Shader :: struct {
	handle: Shader_Handle,
	program: u32,
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

	pfd := win32.PIXELFORMATDESCRIPTOR {
		size_of(win32.PIXELFORMATDESCRIPTOR),
		1,
		win32.PFD_DRAW_TO_WINDOW | win32.PFD_SUPPORT_OPENGL | win32.PFD_DOUBLEBUFFER,    // Flags
		win32.PFD_TYPE_RGBA,        // The kind of framebuffer. RGBA or palette.
		32,                   // Colordepth of the framebuffer.
		0, 0, 0, 0, 0, 0,
		0,
		0,
		0,
		0, 0, 0, 0,
		24,                   // Number of bits for the depthbuffer
		8,                    // Number of bits for the stencilbuffer
		0,                    // Number of Aux buffers in the framebuffer.
		win32.PFD_MAIN_PLANE,
		0,
		0, 0, 0
	}


	hdc := win32.GetWindowDC(win32.HWND(window_handle))
	s.dc = hdc
	fmt := win32.ChoosePixelFormat(hdc, &pfd)
	win32.SetPixelFormat(hdc, fmt, &pfd)

	// https://wikis.khronos.org/opengl/Creating_an_OpenGL_Context_(WGL)
	ctx := win32.wglCreateContext(hdc)
	win32.wglMakeCurrent(hdc, ctx)
	gl.load_up_to(3, 3, win32.gl_set_proc_address)
}

gl_shutdown :: proc() {
}

gl_clear :: proc(color: Color) {
	c := f32_color_from_color(color)
	gl.ClearColor(c.r, c.g, c.b, c.a)
	gl.Clear(gl.COLOR_BUFFER_BIT)
}

gl_present :: proc() {
	win32.SwapBuffers(s.dc)
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

Shader_Compile_Result_OK :: struct {}

Shader_Compile_Result_Error :: string

Shader_Compile_Result :: union #no_nil {
	Shader_Compile_Result_OK,
	Shader_Compile_Result_Error,
}

compile_shader_from_source :: proc(shader_data: string, shader_type: gl.Shader_Type, err_buf: []u8, err_msg: ^string) -> (shader_id: u32, ok: bool) {
	shader_id = gl.CreateShader(u32(shader_type))
	length := i32(len(shader_data))
	shader_cstr := cstring(raw_data(shader_data))
	gl.ShaderSource(shader_id, 1, &shader_cstr, &length)
	gl.CompileShader(shader_id)

	result: i32
	if result == 0 {
		gl.GetShaderiv(shader_id, gl.COMPILE_STATUS, &result)
		info_len: i32
		gl.GetShaderInfoLog(shader_id, i32(len(err_buf)), &info_len, raw_data(err_buf))
		err_msg^ = string(err_buf[:info_len])
		return 0, false
	}

	return shader_id, true
}

gl_load_shader :: proc(vs_source: string, fs_source: string, desc_allocator := frame_allocator, layout_formats: []Pixel_Format = {}) -> (handle: Shader_Handle, desc: Shader_Desc) {
	@static err: [1024]u8
	err_msg: string
	vs_shader, vs_shader_ok := compile_shader_from_source(vs_source, gl.Shader_Type.VERTEX_SHADER, err[:], &err_msg)

	if vs_shader_ok  {
		log.info(err_msg)
	}
	
	fs_shader, fs_shader_ok := compile_shader_from_source(fs_source, gl.Shader_Type.FRAGMENT_SHADER, err[:], &err_msg)

	if !fs_shader_ok {
		log.info(err_msg)
	}

	program := gl.CreateProgram()
	gl.AttachShader(program, vs_shader)
	gl.AttachShader(program, fs_shader)
	gl.LinkProgram(program)

	shader := GL_Shader {
		program = program,
	}

	h := hm.add(&s.shaders, shader)

	return h, {}
}

gl_destroy_shader :: proc(h: Shader_Handle) {
	
}