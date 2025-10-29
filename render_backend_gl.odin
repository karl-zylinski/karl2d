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

	default_shader_vertex_source = gl_default_shader_vertex_source,
	default_shader_fragment_source = gl_default_shader_fragment_source,
}

import "base:runtime"
import gl "vendor:OpenGL"
import hm "handle_map"
import "core:log"
import win32 "core:sys/windows"
import "core:strings"
import "core:slice"

GL_State :: struct {
	width: int,
	height: int,
	allocator: runtime.Allocator,
	shaders: hm.Handle_Map(GL_Shader, Shader_Handle, 1024*10),
	dc: win32.HDC,
	vertex_buffer_gpu: u32,
}

GL_Shader_Constant_Buffer :: struct {
	gpu_data: rawptr,
}

GL_Shader :: struct {
	handle: Shader_Handle,

	// This is like the "input layout"
	vao: u32,

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

	hdc := win32.GetWindowDC(win32.HWND(window_handle))
	s.dc = hdc

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
		0, 0, 0,
	}

	fmt := win32.ChoosePixelFormat(hdc, &pfd)
	win32.SetPixelFormat(hdc, fmt, &pfd)
	ctx := win32.wglCreateContext(hdc)
	win32.wglMakeCurrent(hdc, ctx)

	win32.gl_set_proc_address(&win32.wglChoosePixelFormatARB, "wglChoosePixelFormatARB")
	win32.gl_set_proc_address(&win32.wglCreateContextAttribsARB, "wglCreateContextAttribsARB")

	pixel_format_ilist := [?]i32 {
		win32.WGL_DRAW_TO_WINDOW_ARB, 1,
		win32.WGL_SUPPORT_OPENGL_ARB, 1,
		win32.WGL_DOUBLE_BUFFER_ARB, 1,
		win32.WGL_PIXEL_TYPE_ARB, win32.WGL_TYPE_RGBA_ARB,
		win32.WGL_COLOR_BITS_ARB, 32,
		win32.WGL_DEPTH_BITS_ARB, 24,
		win32.WGL_STENCIL_BITS_ARB, 8,
		0,
	}

	pixel_format: i32
	num_formats: u32

	valid_pixel_format := win32.wglChoosePixelFormatARB(hdc, raw_data(pixel_format_ilist[:]),
		nil, 1, &pixel_format, &num_formats)

	if !valid_pixel_format {
		log.panic("Could not find a valid pixel format for gl context")
	}

	win32.SetPixelFormat(hdc, pixel_format, nil)
	ctx = win32.wglCreateContextAttribsARB(hdc, nil, nil)
	win32.wglMakeCurrent(hdc, ctx)

	gl.load_up_to(3, 3, win32.gl_set_proc_address)

	gl.GenBuffers(1, &s.vertex_buffer_gpu)
	gl.BindBuffer(gl.ARRAY_BUFFER, s.vertex_buffer_gpu)
	gl.BufferData(gl.ARRAY_BUFFER, VERTEX_BUFFER_MAX, nil, gl.DYNAMIC_DRAW)
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
	shader := hm.get(&s.shaders, shd.handle)

	if shader == nil {
		return
	}

	gl.EnableVertexAttribArray(0)
	gl.EnableVertexAttribArray(1)
	gl.EnableVertexAttribArray(2)

	gl.UseProgram(shader.program)
	
	mvp_loc := gl.GetUniformLocation(shader.program, "mvp")
	mvp := view_proj
	gl.UniformMatrix4fv(mvp_loc, 1, gl.FALSE, (^f32)(&mvp))

	gl.BindBuffer(gl.ARRAY_BUFFER, s.vertex_buffer_gpu)

	vb_data := gl.MapBuffer(gl.ARRAY_BUFFER, gl.WRITE_ONLY)
	{
		gpu_map := slice.from_ptr((^u8)(vb_data), VERTEX_BUFFER_MAX)
		copy(
			gpu_map,
			vertex_buffer,
		)
	}
	gl.UnmapBuffer(gl.ARRAY_BUFFER)

	gl.DrawArrays(gl.TRIANGLES, 0, i32(len(vertex_buffer)/shd.vertex_size))
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
	gl.GetShaderiv(shader_id, gl.COMPILE_STATUS, &result)
		
	if result != 1 {
		info_len: i32
		gl.GetShaderInfoLog(shader_id, i32(len(err_buf)), &info_len, raw_data(err_buf))
		err_msg^ = string(err_buf[:info_len])
		gl.DeleteShader(shader_id)
		return 0, false
	}

	return shader_id, true
}

link_shader :: proc(vs_shader: u32, fs_shader: u32, err_buf: []u8, err_msg: ^string) -> (program_id: u32, ok: bool) {
	program_id = gl.CreateProgram()
	gl.AttachShader(program_id, vs_shader)
	gl.AttachShader(program_id, fs_shader)
	gl.LinkProgram(program_id)

	result: i32
	gl.GetProgramiv(program_id, gl.LINK_STATUS, &result)

	if result != 1 {
		info_len: i32
		gl.GetProgramInfoLog(program_id, i32(len(err_buf)), &info_len, raw_data(err_buf))
		err_msg^ = string(err_buf[:info_len])
		gl.DeleteProgram(program_id)
		return 0, false
	}

	return program_id, true
}

gl_load_shader :: proc(vs_source: string, fs_source: string, desc_allocator := frame_allocator, layout_formats: []Pixel_Format = {}) -> (handle: Shader_Handle, desc: Shader_Desc) {
	@static err: [1024]u8
	err_msg: string
	vs_shader, vs_shader_ok := compile_shader_from_source(vs_source, gl.Shader_Type.VERTEX_SHADER, err[:], &err_msg)

	if !vs_shader_ok  {
		log.error(err_msg)
		return {}, {}
	}
	
	fs_shader, fs_shader_ok := compile_shader_from_source(fs_source, gl.Shader_Type.FRAGMENT_SHADER, err[:], &err_msg)

	if !fs_shader_ok {
		log.error(err_msg)
		return {}, {}
	}

	program, program_ok := link_shader(vs_shader, fs_shader, err[:], &err_msg)

	if !program_ok {
		log.error(err_msg)
		return {}, {}
	}

	stride: int

	{
		num_attribs: i32
		gl.GetProgramiv(program, gl.ACTIVE_ATTRIBUTES, &num_attribs)
		desc.inputs = make([]Shader_Input, num_attribs, desc_allocator)

		attrib_name_buf: [256]u8

		for i in 0..<num_attribs {
			attrib_name_len: i32
			attrib_size: i32
			attrib_type: u32
			gl.GetActiveAttrib(program, u32(i), i32(len(attrib_name_buf)), &attrib_name_len, &attrib_size, &attrib_type, raw_data(attrib_name_buf[:]))

			name_cstr := strings.clone_to_cstring(string(attrib_name_buf[:attrib_name_len]), desc_allocator)
			
			loc := gl.GetAttribLocation(program, name_cstr)
			log.info(loc)
			type: Shader_Input_Type

			switch attrib_type {
			case gl.FLOAT: type = .F32
			case gl.FLOAT_VEC2: type = .Vec2
			case gl.FLOAT_VEC3: type = .Vec3
			case gl.FLOAT_VEC4: type = .Vec4
			
			/* Possible (gl.) types:

			   FLOAT, FLOAT_VEC2, FLOAT_VEC3, FLOAT_VEC4, FLOAT_MAT2,
			   FLOAT_MAT3, FLOAT_MAT4, FLOAT_MAT2x3, FLOAT_MAT2x4,
			   FLOAT_MAT3x2, FLOAT_MAT3x4, FLOAT_MAT4x2, FLOAT_MAT4x3,
			   INT, INT_VEC2, INT_VEC3, INT_VEC4, UNSIGNED_INT, 
			   UNSIGNED_INT_VEC2, UNSIGNED_INT_VEC3, UNSIGNED_INT_VEC4,
			   DOUBLE, DOUBLE_VEC2, DOUBLE_VEC3, DOUBLE_VEC4, DOUBLE_MAT2,
			   DOUBLE_MAT3, DOUBLE_MAT4, DOUBLE_MAT2x3, DOUBLE_MAT2x4,
			   DOUBLE_MAT3x2, DOUBLE_MAT3x4, DOUBLE_MAT4x2, or DOUBLE_MAT4x3 */

			case: log.errorf("Unknwon type: %v", attrib_type)
			}

			name := strings.clone(string(attrib_name_buf[:attrib_name_len]), desc_allocator)
			
			log.info(name)
			format := len(layout_formats) > 0 ? layout_formats[loc] : get_shader_input_format(name, type)
			desc.inputs[loc] = {
				name = name,
				register = int(loc),
				format = format,
				type = type,
			}


			input_format := get_shader_input_format(name, type)
			format_size := pixel_format_size(input_format)

			stride += format_size


			// 
			//log.info(i, attrib_name_len, attrib_size, attrib_type, string(attrib_name_buf[:attrib_name_len]))
		}
	}


	shader := GL_Shader {
		program = program,
	}

	gl.GenVertexArrays(1, &shader.vao)
	gl.BindVertexArray(shader.vao)
	gl.BindBuffer(gl.ARRAY_BUFFER, s.vertex_buffer_gpu)

	offset: int
	for idx in 0..<len(desc.inputs) {
		input := desc.inputs[idx]
		input_format := get_shader_input_format(input.name, input.type)
		format_size := pixel_format_size(input_format)
		num_components := get_shader_format_num_components(input_format)
		gl.EnableVertexAttribArray(u32(idx))	
		gl.VertexAttribPointer(u32(idx), i32(num_components), gl.FLOAT, gl.FALSE, i32(stride), uintptr(offset))
		offset += format_size
		log.info(input.name)
	}


	{
		/*num_constant_buffers: i32
		gl.GetProgramiv(program, gl.ACTIVE_UNIFORM_BLOCKS, &num_attribs)
		desc.constant_buffers = make([]Shader_Constant_Buffer_Desc, num_constant_buffers, desc_allocator)
		shader.constant_buffers = make([]GL_Shader_Constant_Buffer, num_constant_buffers, s.allocator)
	
		for cb_idx in 0..<num_constant_buffers {
			buf: u32
			gl.GenBuffers(1, &buf)*/



	
		/*
		GetUniformIndices         :: proc "c" (program: u32, uniformCount: i32, uniformNames: [^]cstring, uniformIndices: [^]u32)         {        impl_GetUniformIndices(program, uniformCount, uniformNames, uniformIndices)                               }
	GetActiveUniformsiv       :: proc "c" (program: u32, uniformCount: i32, uniformIndices: [^]u32, pname: u32, params: [^]i32)       {        impl_GetActiveUniformsiv(program, uniformCount, uniformIndices, pname, params)                            }
	GetActiveUniformName      :: proc "c" (program: u32, uniformIndex: u32, bufSize: i32, length: ^i32, uniformName: [^]u8)           {        impl_GetActiveUniformName(program, uniformIndex, bufSize, length, uniformName)                            }
	GetUniformBlockIndex      :: proc "c" (program: u32, uniformBlockName: cstring) -> u32                                            { ret := impl_GetUniformBlockIndex(program, uniformBlockName);                                          return ret }
	GetActiveUniformBlockiv   :: proc "c" (program: u32, uniformBlockIndex: u32, pname: u32, params: [^]i32)                          {        impl_GetActiveUniformBlockiv(program, uniformBlockIndex, pname, params)                                   }

*/		
	}

	h := hm.add(&s.shaders, shader)

	return h, desc
}

gl_destroy_shader :: proc(h: Shader_Handle) {
	
}

gl_default_shader_vertex_source :: proc() -> string {
	return #load("default_shader_vertex.glsl")
}


gl_default_shader_fragment_source :: proc() -> string {
	return #load("default_shader_fragment.glsl")
}

