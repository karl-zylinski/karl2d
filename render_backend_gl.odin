#+build windows, darwin, linux
#+private file

package karl2d

@(private="package")
RENDER_BACKEND_GL :: Render_Backend_Interface {
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
	texture_needs_vertical_flip = gl_texture_needs_vertical_flip,
	create_render_texture = gl_create_render_texture,
	destroy_render_target = gl_destroy_render_target,
	set_texture_filter = gl_set_texture_filter,
	load_shader = gl_load_shader,
	destroy_shader = gl_destroy_shader,

	default_shader_vertex_source = gl_default_shader_vertex_source,
	default_shader_fragment_source = gl_default_shader_fragment_source,
}

import "base:runtime"
import gl "vendor:OpenGL"
import hm "handle_map"
import "log"
import "core:strings"
import "core:slice"
import la "core:math/linalg"

_ :: la

GL_State :: struct {
	width: int,
	height: int,
	allocator: runtime.Allocator,
	shaders: hm.Handle_Map(GL_Shader, Shader_Handle, 1024*10),
	glue: Window_Render_Glue,
	vertex_buffer_gpu: u32,
	textures: hm.Handle_Map(GL_Texture, Texture_Handle, 1024*10),
	render_targets: hm.Handle_Map(GL_Render_Target, Render_Target_Handle, 128),
}

GL_Shader_Constant_Buffer :: struct {
	buffer: u32,
	size: int,
	block_index: u32,
}

GL_Shader_Constant_Type :: enum {
	Uniform,
	Block_Variable,
}

// OpenGL can have constants both in blocks (like constant buffers in D3D11), or as stand-alone
// uniforms. We support both.
GL_Shader_Constant :: struct {
	type: GL_Shader_Constant_Type,

	// if type is Uniform, then this is the uniform loc
	// if type is Block_Variable, then this is the block loc
	loc: u32, 

	// if this is a block variable, then this is the offset to it
	block_variable_offset: u32,

	// if type is Uniform, then this contains the GL type of the uniform
	uniform_type: u32,
}

GL_Texture :: struct {
	handle: Texture_Handle,
	id: u32,
	format: Pixel_Format,

	// Because render targets are up-side-down
	needs_vertical_flip: bool,
}

GL_Texture_Binding :: struct {
	loc: i32,
}

GL_Render_Target :: struct {
	handle: Render_Target_Handle,
	framebuffer: u32,
	width: int,
	height: int,
}

GL_Shader :: struct {
	handle: Shader_Handle,

	// This is like the "input layout"
	vao: u32,

	program: u32,

	constant_buffers: []GL_Shader_Constant_Buffer,
	constants: []GL_Shader_Constant,
	texture_bindings: []GL_Texture_Binding, 
}

s: ^GL_State

gl_state_size :: proc() -> int {
	return size_of(GL_State)
}

gl_init :: proc(state: rawptr, glue: Window_Render_Glue, swapchain_width, swapchain_height: int, allocator := context.allocator) {
	s = (^GL_State)(state)
	s.glue = glue
	s.width = swapchain_width
	s.height = swapchain_height
	s.allocator = allocator

	make_context_ok := s.glue->make_context()

	if !make_context_ok {
		log.panic("Could not create a valid gl context")
	}

	gl.GenBuffers(1, &s.vertex_buffer_gpu)
	gl.BindBuffer(gl.ARRAY_BUFFER, s.vertex_buffer_gpu)
	gl.BufferData(gl.ARRAY_BUFFER, VERTEX_BUFFER_MAX, nil, gl.DYNAMIC_DRAW)

	gl.Enable(gl.BLEND)
}

gl_shutdown :: proc() {
	gl.DeleteBuffers(1, &s.vertex_buffer_gpu)
	s.glue->destroy()
}

gl_clear :: proc(render_target: Render_Target_Handle, color: Color) {
	if rt := hm.get(&s.render_targets, render_target); rt != nil {
		gl.BindFramebuffer(gl.FRAMEBUFFER, rt.framebuffer)
		gl.Viewport(0, 0, i32(rt.width), i32(rt.height))
	} else {
		gl.BindFramebuffer(gl.FRAMEBUFFER, 0)
		gl.Viewport(0, 0, i32(s.width), i32(s.height))
	}

	c := f32_color_from_color(color)
	gl.ClearColor(c.r, c.g, c.b, c.a)
	gl.Clear(gl.COLOR_BUFFER_BIT)
}

gl_present :: proc() {
	s.glue->present()
}

gl_draw :: proc(
	shd: Shader,
	render_target: Render_Target_Handle,
	bound_textures: []Texture_Handle,
	scissor: Maybe(Rect),
	blend_mode: Blend_Mode,
	vertex_buffer: []u8,
) {
	gl_shd := hm.get(&s.shaders, shd.handle)

	if gl_shd == nil {
		return
	}

	switch blend_mode {
	case .Alpha: gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)
	case .Premultiplied_Alpha: gl.BlendFunc(gl.ONE, gl.ONE_MINUS_SRC_ALPHA)
	}

	gl.BindVertexArray(gl_shd.vao)

	gl.UseProgram(gl_shd.program)
	assert(len(shd.constants) == len(gl_shd.constants))

	cpu_data := shd.constants_data
	for cidx in 0..<len(gl_shd.constants) {
		cpu_loc := shd.constants[cidx]

		if cpu_loc.size == 0 {
			continue
		}

		gpu_loc := gl_shd.constants[cidx]

		switch gpu_loc.type {
		case .Block_Variable:
			gpu_buffer_info := gl_shd.constant_buffers[gpu_loc.loc]
			gpu_data := gpu_buffer_info.buffer
			gl.BindBuffer(gl.UNIFORM_BUFFER, gpu_data)
			src := cpu_data[cpu_loc.offset:cpu_loc.offset+cpu_loc.size]
			gl.BufferData(gl.UNIFORM_BUFFER, len(src), raw_data(src), gl.DYNAMIC_DRAW)
			gl.BindBufferBase(gl.UNIFORM_BUFFER, gpu_loc.loc, gpu_data)	

		case .Uniform:
			loc := i32(gpu_loc.loc)
			ptr := (rawptr)(&cpu_data[cpu_loc.offset])
			uptr := (^u32)(ptr)
			iptr := (^i32)(ptr)
			fptr := (^f32)(ptr)
			dptr := (^f64)(ptr)
			switch gpu_loc.uniform_type {
			case gl.FLOAT:
				gl.Uniform1fv(loc, 1, fptr)

			case gl.FLOAT_VEC2:
				gl.Uniform2fv(loc, 1, fptr)
			case gl.FLOAT_MAT2:
				gl.UniformMatrix2fv(loc, 1, false, fptr)
			case gl.FLOAT_MAT2x3:
				gl.UniformMatrix2x3fv(loc, 1, false, fptr)
			case gl.FLOAT_MAT2x4:
				gl.UniformMatrix2x4fv(loc, 1, false, fptr)

			case gl.FLOAT_VEC3:
				gl.Uniform3fv(loc, 1, fptr)
			case gl.FLOAT_MAT3x2:
				gl.UniformMatrix3x2fv(loc, 1, false, fptr)
			case gl.FLOAT_MAT3:
				gl.UniformMatrix3fv(loc, 1, false, fptr)
			case gl.FLOAT_MAT3x4:
				gl.UniformMatrix3x4fv(loc, 1, false, fptr)

			case gl.FLOAT_VEC4:
				gl.Uniform4fv(loc, 1, fptr)
			case gl.FLOAT_MAT4x2:
				gl.UniformMatrix4x2fv(loc, 1, false, fptr)
			case gl.FLOAT_MAT4x3:
				gl.UniformMatrix4x3fv(loc, 1, false, fptr)
			case gl.FLOAT_MAT4:
				gl.UniformMatrix4fv(loc, 1, false, fptr)

			case gl.DOUBLE:
				gl.Uniform1dv(loc, 1, dptr)

			case gl.DOUBLE_VEC2:
				gl.Uniform2dv(loc, 1, dptr)
			case gl.DOUBLE_MAT2:
				gl.UniformMatrix2dv(loc, 1, false, dptr)
			case gl.DOUBLE_MAT2x3:
				gl.UniformMatrix2x3dv(loc, 1, false, dptr)
			case gl.DOUBLE_MAT2x4:
				gl.UniformMatrix2x4dv(loc, 1, false, dptr)

			case gl.DOUBLE_VEC3:
				gl.Uniform3dv(loc, 1, dptr)
			case gl.DOUBLE_MAT3x2:
				gl.UniformMatrix3x2dv(loc, 1, false, dptr)
			case gl.DOUBLE_MAT3:
				gl.UniformMatrix3dv(loc, 1, false, dptr)
			case gl.DOUBLE_MAT3x4:
				gl.UniformMatrix3x4dv(loc, 1, false, dptr)

			case gl.DOUBLE_VEC4:
				gl.Uniform4dv(loc, 1, dptr)
			case gl.DOUBLE_MAT4x2:
				gl.UniformMatrix4x2dv(loc, 1, false, dptr)
			case gl.DOUBLE_MAT4x3:
				gl.UniformMatrix4x3dv(loc, 1, false, dptr)
			case gl.DOUBLE_MAT4:
				gl.UniformMatrix4dv(loc, 1, false, dptr)

			case gl.BOOL, gl.INT:
				gl.Uniform1iv(loc, 1, iptr)
			case gl.BOOL_VEC2, gl.INT_VEC2:
				gl.Uniform2iv(loc, 1, iptr)
			case gl.BOOL_VEC3, gl.INT_VEC3:
				gl.Uniform3iv(loc, 1, iptr)
			case gl.BOOL_VEC4, gl.INT_VEC4:
				gl.Uniform4iv(loc, 1, iptr)

			case gl.UNSIGNED_INT:
				gl.Uniform1uiv(loc, 1, uptr)
			case gl.UNSIGNED_INT_VEC2:
				gl.Uniform2uiv(loc, 1, uptr)
			case gl.UNSIGNED_INT_VEC3:
				gl.Uniform3uiv(loc, 1, uptr)
			case gl.UNSIGNED_INT_VEC4:
				gl.Uniform4uiv(loc, 1, uptr)

			case: log.errorf("Unknown type: %x", gpu_loc.uniform_type)
			}
			
		}
	}
	
	gl.BindBuffer(gl.ARRAY_BUFFER, s.vertex_buffer_gpu)
	vb_data := gl.MapBuffer(gl.ARRAY_BUFFER, gl.WRITE_ONLY)
	{
		gpu_map := slice.from_ptr((^u8)(vb_data), VERTEX_BUFFER_MAX)
		copy(
			gpu_map,
			vertex_buffer,
		)
	}

	if len(bound_textures) == len(gl_shd.texture_bindings) {
		for t, t_idx in bound_textures {
			gl_t := gl_shd.texture_bindings[t_idx]

			if t := hm.get(&s.textures, t); t != nil {
				gl.ActiveTexture(gl.TEXTURE0 + u32(t_idx))
				gl.BindTexture(gl.TEXTURE_2D, t.id)
				gl.Uniform1i(gl_t.loc, i32(t_idx))
			} else {
				gl.ActiveTexture(gl.TEXTURE0 + u32(t_idx))
				gl.BindTexture(gl.TEXTURE_2D, 0)
				gl.Uniform1i(gl_t.loc, i32(t_idx))
			}
		}
	}

	gl.UnmapBuffer(gl.ARRAY_BUFFER)

	if rt := hm.get(&s.render_targets, render_target); rt != nil {
		gl.BindFramebuffer(gl.FRAMEBUFFER, rt.framebuffer)
		gl.Viewport(0, 0, i32(rt.width), i32(rt.height))
	} else {
		gl.BindFramebuffer(gl.FRAMEBUFFER, 0)
		gl.Viewport(0, 0, i32(s.width), i32(s.height))
	}
	 // Render on the whole framebuffer, complete from the lower left corner to the upper right

	gl.DrawArrays(gl.TRIANGLES, 0, i32(len(vertex_buffer)/shd.vertex_size))
}

gl_resize_swapchain :: proc(w, h: int) {
	s.width = w
	s.height = h
	gl.Viewport(0, 0, i32(w), i32(h))
	s.glue->viewport_resized()
}

gl_get_swapchain_width :: proc() -> int {
	return s.width
}

gl_get_swapchain_height :: proc() -> int {
	return s.height
}

gl_set_internal_state :: proc(state: rawptr) {
	s = (^GL_State)(state)
}

create_texture :: proc(width: int, height: int, format: Pixel_Format, data: rawptr) -> GL_Texture {
	id: u32
	gl.GenTextures(1, &id)
	gl.BindTexture(gl.TEXTURE_2D, id)

	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.REPEAT)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.REPEAT)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST)

	pf := gl_translate_pixel_format(format)
	gl.TexImage2D(gl.TEXTURE_2D, 0, pf, i32(width), i32(height), 0, gl.RGBA, gl.UNSIGNED_BYTE, data)

	return {
		id = id,
		format = format,
	}
}

gl_create_texture :: proc(width: int, height: int, format: Pixel_Format) -> Texture_Handle {
	return hm.add(&s.textures, create_texture(width, height, format, nil))
}

gl_load_texture :: proc(data: []u8, width: int, height: int, format: Pixel_Format) -> Texture_Handle {
	return hm.add(&s.textures, create_texture(width, height, format, raw_data(data)))
}

gl_update_texture :: proc(th: Texture_Handle, data: []u8, rect: Rect) -> bool {
	tex := hm.get(&s.textures, th)

	if tex == nil {
		return false
	}

    gl.BindTexture(gl.TEXTURE_2D, tex.id)
	gl.TexSubImage2D(gl.TEXTURE_2D, 0, i32(rect.x), i32(rect.y), i32(rect.w), i32(rect.h), gl.RGBA, gl.UNSIGNED_BYTE, raw_data(data))
	return true
}

gl_destroy_texture :: proc(th: Texture_Handle) {
	tex := hm.get(&s.textures, th)

	if tex == nil {
		return
	}

	gl.DeleteTextures(1, &tex.id)
	hm.remove(&s.textures, th)
}

gl_texture_needs_vertical_flip :: proc(th: Texture_Handle) -> bool {
	tex := hm.get(&s.textures, th)

	if tex == nil {
		return false
	}

	return tex.needs_vertical_flip
}

gl_create_render_texture :: proc(width: int, height: int) -> (Texture_Handle, Render_Target_Handle) {
	texture := create_texture(width, height, .RGBA_32_Float, nil)
	texture.needs_vertical_flip = true
	
	framebuffer: u32
	gl.GenFramebuffers(1, &framebuffer)
	gl.BindFramebuffer(gl.FRAMEBUFFER, framebuffer)

	gl.FramebufferTexture(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, texture.id, 0)
	draw_buffers := u32(gl.COLOR_ATTACHMENT0)
	gl.DrawBuffers(1, &draw_buffers)

	if gl.CheckFramebufferStatus(gl.FRAMEBUFFER) != gl.FRAMEBUFFER_COMPLETE {
		log.errorf("Failed creating frame buffer of size %v x %v", width, height)
		return {}, {}
	}

	gl.BindFramebuffer(gl.FRAMEBUFFER, 0)
	gl.BindRenderbuffer(gl.RENDERBUFFER, 0)

	rt := GL_Render_Target {
		framebuffer = framebuffer,
		width = width,
		height = height,
	}

	return hm.add(&s.textures, texture), hm.add(&s.render_targets, rt)
}

gl_destroy_render_target :: proc(render_target: Render_Target_Handle) {
	if rt := hm.get(&s.render_targets, render_target); rt != nil {
		gl.DeleteFramebuffers(1, &rt.framebuffer)
	}
}

gl_set_texture_filter :: proc(
	th: Texture_Handle,
	scale_down_filter: Texture_Filter,
	scale_up_filter: Texture_Filter,
	mip_filter: Texture_Filter,
) {
	t := hm.get(&s.textures, th)

	if t == nil {
		log.error("Trying to set texture filter for invalid texture %v", th)
		return
	}

	gl.BindTexture(gl.TEXTURE_2D, t.id)

	min_filter: i32 = scale_down_filter == .Point ? gl.NEAREST : gl.LINEAR
	mag_filter: i32 = scale_up_filter == .Point ? gl.NEAREST : gl.LINEAR

	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, min_filter)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, mag_filter)
}

Shader_Compile_Result_OK :: struct {}

Shader_Compile_Result_Error :: string

Shader_Compile_Result :: union #no_nil {
	Shader_Compile_Result_OK,
	Shader_Compile_Result_Error,
}

compile_shader_from_source :: proc(shader_data: []byte, shader_type: gl.Shader_Type, err_buf: []u8, err_msg: ^string) -> (shader_id: u32, ok: bool) {
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

gl_load_shader :: proc(vs_source: []byte, fs_source: []byte, desc_allocator := frame_allocator, layout_formats: []Pixel_Format = {}) -> (handle: Shader_Handle, desc: Shader_Desc) {
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

			name_cstr := cstring(raw_data(attrib_name_buf[:attrib_name_len]))
			
			loc := gl.GetAttribLocation(program, name_cstr)

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

			case: log.errorf("Unknown type: %v", attrib_type)
			}

			name := strings.clone(string(attrib_name_buf[:attrib_name_len]), desc_allocator)
			
			format := len(layout_formats) > 0 ? layout_formats[loc] : get_shader_input_format(name, type)
			desc.inputs[i] = {
				name = name,
				register = int(loc),
				format = format,
				type = type,
			}

			input_format := get_shader_input_format(name, type)
			format_size := pixel_format_size(input_format)

			stride += format_size
		}
	}

	gl_shd := GL_Shader {
		program = program,
	}

	gl.GenVertexArrays(1, &gl_shd.vao)
	gl.BindVertexArray(gl_shd.vao)

	offset: int
	for idx in 0..<len(desc.inputs) {
		input := desc.inputs[idx]
		format_size := pixel_format_size(input.format)
		gl.EnableVertexAttribArray(u32(input.register))	
		format, num_components, norm := gl_describe_pixel_format(input.format)
		gl.VertexAttribPointer(u32(input.register), num_components, format, norm ? gl.TRUE : gl.FALSE, i32(stride), uintptr(offset))
		offset += format_size
	}

	constant_descs := make([dynamic]Shader_Constant_Desc, desc_allocator)
	gl_constants := make([dynamic]GL_Shader_Constant, s.allocator)
	texture_bindpoint_descs := make([dynamic]Shader_Texture_Bindpoint_Desc, desc_allocator)
	gl_texture_bindings := make([dynamic]GL_Texture_Binding, s.allocator)

	{
		num_active_uniforms: i32
		gl.GetProgramiv(program, gl.ACTIVE_UNIFORMS, &num_active_uniforms)
		uniform_name_buf: [256]u8

		for cidx in 0..<num_active_uniforms {
			name_len: i32
			array_len: i32
			type: u32
			
			gl.GetActiveUniform(
				program,
				u32(cidx),
				len(uniform_name_buf),
				&name_len,
				&array_len,
				&type,
				raw_data(&uniform_name_buf),
			)

			name := strings.string_from_ptr(raw_data(uniform_name_buf[:]), int(name_len))
			loc := gl.GetUniformLocation(program, cstring(raw_data(name)))

			if type == gl.SAMPLER_2D {
				append(&texture_bindpoint_descs, Shader_Texture_Bindpoint_Desc {
					name = strings.clone(name, desc_allocator),
				})

				append(&gl_texture_bindings, GL_Texture_Binding {
					loc = loc,
				})
			} else {
				append(&constant_descs, Shader_Constant_Desc {
					name = strings.clone(name, desc_allocator),
					size = uniform_size(type),
				})

				append(&gl_constants, GL_Shader_Constant {
					type = .Uniform,
					loc = u32(loc),
					uniform_type = type,
				})
			}
		}
	}

	// Blocks are like constant buffers in D3D, it's like a struct with multiple uniforms inside
	{
		num_active_uniform_blocks: i32
		gl.GetProgramiv(program, gl.ACTIVE_UNIFORM_BLOCKS, &num_active_uniform_blocks)
		gl_shd.constant_buffers = make([]GL_Shader_Constant_Buffer, num_active_uniform_blocks, s.allocator)

		uniform_block_name_buf: [256]u8
		uniform_name_buf: [256]u8

		for cb_idx in 0..<num_active_uniform_blocks {
			name_len: i32
			gl.GetActiveUniformBlockName(program, u32(cb_idx), len(uniform_block_name_buf), &name_len, raw_data(&uniform_block_name_buf))
			name_cstr := cstring(raw_data(uniform_block_name_buf[:name_len]))
			idx := gl.GetUniformBlockIndex(program, name_cstr)

			if i32(idx) >= num_active_uniform_blocks {
				continue
			}

			size: i32

			// TODO investigate if we need std140 layout in the shader or what is fine?
			gl.GetActiveUniformBlockiv(program, idx, gl.UNIFORM_BLOCK_DATA_SIZE, &size)

			if size == 0 {
				log.errorf("Uniform block %v has size 0", name_cstr)
				continue
			}

			buf: u32

			gl.GenBuffers(1, &buf)
			gl.BindBuffer(gl.UNIFORM_BUFFER, buf)
			gl.BufferData(gl.UNIFORM_BUFFER, int(size), nil, gl.DYNAMIC_DRAW)
			gl.BindBufferBase(gl.UNIFORM_BUFFER, idx, buf)

			gl_shd.constant_buffers[cb_idx] = {
				block_index = idx,
				buffer = buf,
				size = int(size),
			}

			num_uniforms: i32
			gl.GetActiveUniformBlockiv(program, idx, gl.UNIFORM_BLOCK_ACTIVE_UNIFORMS, &num_uniforms)

			uniform_indices := make([]i32, num_uniforms, frame_allocator)
			gl.GetActiveUniformBlockiv(program, idx, gl.UNIFORM_BLOCK_ACTIVE_UNIFORM_INDICES, raw_data(uniform_indices))

			for var_idx in 0..<num_uniforms {
				uniform_idx := u32(uniform_indices[var_idx])

				offset: i32
				gl.GetActiveUniformsiv(program, 1, &uniform_idx, gl.UNIFORM_OFFSET, &offset)

				uniform_type: u32
				gl.GetActiveUniformsiv(program, 1, &uniform_idx, gl.UNIFORM_TYPE, (^i32)(&uniform_type))

				variable_name_len: i32
				gl.GetActiveUniformName(program, uniform_idx, len(uniform_name_buf), &variable_name_len, raw_data(&uniform_name_buf))

				append(&constant_descs, Shader_Constant_Desc {
					name = strings.clone(string(uniform_name_buf[:variable_name_len]), desc_allocator),
					size = uniform_size(uniform_type),
				})

				append(&gl_constants, GL_Shader_Constant {
					type = .Block_Variable,
					loc = idx,
					block_variable_offset = u32(offset),
				})
			}
		}
	}

	assert(len(constant_descs) == len(gl_constants))
	desc.constants = constant_descs[:]
	desc.texture_bindpoints = texture_bindpoint_descs[:]
	gl_shd.constants = gl_constants[:]
	gl_shd.texture_bindings = gl_texture_bindings[:]

	h := hm.add(&s.shaders, gl_shd)

	return h, desc
}

// I might have missed something. But it doesn't seem like GL gives you this information.
uniform_size :: proc(t: u32) -> int {
	sz: int
	switch t {
	case gl.FLOAT:        sz = 4*1

	case gl.FLOAT_VEC2:   sz = 4*2*1
	case gl.FLOAT_MAT2:   sz = 4*2*2
	case gl.FLOAT_MAT2x3: sz = 4*2*3
	case gl.FLOAT_MAT2x4: sz = 4*2*4

	case gl.FLOAT_VEC3:   sz = 4*3*1
	case gl.FLOAT_MAT3x2: sz = 4*3*2
	case gl.FLOAT_MAT3:   sz = 4*3*3
	case gl.FLOAT_MAT3x4: sz = 4*3*4

	case gl.FLOAT_VEC4:   sz = 4*4*1
	case gl.FLOAT_MAT4x2: sz = 4*4*2
	case gl.FLOAT_MAT4x3: sz = 4*4*3
	case gl.FLOAT_MAT4:   sz = 4*4*4

	case gl.DOUBLE:        sz = 8*1

	case gl.DOUBLE_VEC2:   sz = 8*2*1
	case gl.DOUBLE_MAT2:   sz = 8*2*2
	case gl.DOUBLE_MAT2x3: sz = 8*2*3
	case gl.DOUBLE_MAT2x4: sz = 8*2*4

	case gl.DOUBLE_VEC3:   sz = 8*3*1
	case gl.DOUBLE_MAT3x2: sz = 8*3*2
	case gl.DOUBLE_MAT3:   sz = 8*3*3
	case gl.DOUBLE_MAT3x4: sz = 8*3*4

	case gl.DOUBLE_VEC4:   sz = 8*4*1
	case gl.DOUBLE_MAT4x2: sz = 8*4*2
	case gl.DOUBLE_MAT4x3: sz = 8*4*3
	case gl.DOUBLE_MAT4:   sz = 8*4*4

	case gl.BOOL:      sz = 4*1
	case gl.BOOL_VEC2: sz = 4*2
	case gl.BOOL_VEC3: sz = 4*3
	case gl.BOOL_VEC4: sz = 4*4

	case gl.INT:      sz = 4*1
	case gl.INT_VEC2: sz = 4*2
	case gl.INT_VEC3: sz = 4*3
	case gl.INT_VEC4: sz = 4*4

	case gl.UNSIGNED_INT:      sz = 4*1
	case gl.UNSIGNED_INT_VEC2: sz = 4*2
	case gl.UNSIGNED_INT_VEC3: sz = 4*3
	case gl.UNSIGNED_INT_VEC4: sz = 4*4
	case: log.errorf("Unhandled uniform type: %x", t)
	}

	return sz
}

gl_translate_pixel_format :: proc(f: Pixel_Format) -> i32 {
	switch f {
	case .RGBA_32_Float: return gl.RGBA
	case .RGB_32_Float: return gl.RGB
	case .RG_32_Float: return gl.RG
	case .R_32_Float: return gl.R

	// THIS SEEMS WRONG -- Am I putting the 8 bit info in the wrong place?
	case .RGBA_8_Norm: return gl.RGBA
	case .RG_8_Norm: return gl.RG
	case .R_8_Norm: return gl.R
	case .R_8_UInt: return gl.R

	case .Unknown: fallthrough
	case: log.error("Unhandled pixel format %v", f) 
	}
	
	return 0
}


gl_describe_pixel_format :: proc(f: Pixel_Format) -> (format: u32, num_components: i32, normalized: bool) {
	switch f {
	case .RGBA_32_Float: return gl.FLOAT, 4, false
	case .RGB_32_Float: return gl.FLOAT, 3, false
	case .RG_32_Float: return gl.FLOAT, 2, false
	case .R_32_Float: return gl.FLOAT, 1, false

	case .RGBA_8_Norm: return gl.UNSIGNED_BYTE, 4, true
	case .RG_8_Norm: return gl.UNSIGNED_BYTE, 2, true
	case .R_8_Norm: return gl.UNSIGNED_BYTE, 1, true
	case .R_8_UInt: return gl.BYTE, 1, false
	
	case .Unknown: 
	}

	log.errorf("Unknown format %x", format)
	return 0, 0, false
}

gl_destroy_shader :: proc(h: Shader_Handle) {
	shd := hm.get(&s.shaders, h)

	if shd == nil {
		log.errorf("Invalid shader: %v", h)
		return
	}

	delete(shd.constant_buffers, s.allocator)
	delete(shd.constants, s.allocator)
	delete(shd.texture_bindings, s.allocator)
}

gl_default_shader_vertex_source :: proc() -> []byte {
	vertex_source := #load("render_backend_gl_default_vertex_shader.glsl")
	return vertex_source
}

gl_default_shader_fragment_source :: proc() -> []byte {
	fragment_source := #load("render_backend_gl_default_fragment_shader.glsl")
	return fragment_source
}

