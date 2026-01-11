#+build js
#+private file

package karl2d

@(private="package")
RENDER_BACKEND_WEBGL :: Render_Backend_Interface {
	state_size = webgl_state_size,
	init = webgl_init,
	shutdown = webgl_shutdown,
	clear = webgl_clear,
	present = webgl_present,
	draw = webgl_draw,
	resize_swapchain = webgl_resize_swapchain,
	get_swapchain_width = webgl_get_swapchain_width,
	get_swapchain_height = webgl_get_swapchain_height,
	set_internal_state = webgl_set_internal_state,
	create_texture = webgl_create_texture,
	load_texture = webgl_load_texture,
	update_texture = webgl_update_texture,
	destroy_texture = webgl_destroy_texture,
	texture_needs_vertical_flip = webgl_texture_needs_vertical_flip,
	create_render_texture = webgl_create_render_texture,
	destroy_render_target = webgl_destroy_render_target,
	set_texture_filter = webgl_set_texture_filter,
	load_shader = webgl_load_shader,
	destroy_shader = webgl_destroy_shader,

	default_shader_vertex_source = webgl_default_shader_vertex_source,
	default_shader_fragment_source = webgl_default_shader_fragment_source,
}

import "base:runtime"
import gl "vendor:wasm/WebGL"
import hm "handle_map"
import "log"
import "core:strings"
import la "core:math/linalg"

_ :: la

WebGL_State :: struct {
	canvas_id: string,
	width: int,
	height: int,
	allocator: runtime.Allocator,
	shaders: hm.Handle_Map(WebGL_Shader, Shader_Handle, 1024*10),
	vertex_buffer_gpu: gl.Buffer,
	textures: hm.Handle_Map(WebGL_Texture, Texture_Handle, 1024*10),
	render_targets: hm.Handle_Map(WebGL_Render_Target, Render_Target_Handle, 128),
}

WebGL_Shader_Constant_Buffer :: struct {
	buffer: gl.Buffer,
	size: int,
	block_index: i32,
}

WebGL_Shader_Constant_Type :: enum {
	Uniform,
	Block_Variable,
}

// OpenGL can have constants both in blocks (like constant buffers in D3D11), or as stand-alone
// uniforms. We support both.
WebGL_Shader_Constant :: struct {
	type: WebGL_Shader_Constant_Type,

	// if type is Uniform, then this is the uniform loc
	// if type is Block_Variable, then this is the block loc
	loc: i32, 

	// if this is a block variable, then this is the offset to it
	block_variable_offset: u32,

	// if type is Uniform, then this contains the GL type of the uniform
	uniform_type: gl.Enum,
}

WebGL_Texture :: struct {
	handle: Texture_Handle,
	id: gl.Texture,
	format: Pixel_Format,
	needs_vertical_flip: bool,
}

WebGL_Texture_Binding :: struct {
	loc: i32,
}

WebGL_Render_Target :: struct {
	handle: Render_Target_Handle,
	framebuffer: gl.Framebuffer,
	width: int,
	height: int,
}

WebGL_Shader :: struct {
	handle: Shader_Handle,

	// This is like the "input layout"
	vao: gl.VertexArrayObject,

	program: gl.Program,

	constant_buffers: []WebGL_Shader_Constant_Buffer,
	constants: []WebGL_Shader_Constant,
	texture_bindings: []WebGL_Texture_Binding, 
}

s: ^WebGL_State

webgl_state_size :: proc() -> int {
	return size_of(WebGL_State)
}

webgl_init :: proc(state: rawptr, window_handle: Window_Handle, swapchain_width, swapchain_height: int, allocator := context.allocator) {
	s = (^WebGL_State)(state)
	canvas_id := (^HTML_Canvas_ID)(window_handle)^
	s.canvas_id = strings.clone(canvas_id, allocator)
	s.width = swapchain_width
	s.height = swapchain_height
	s.allocator = allocator

	context_ok := gl.CreateCurrentContextById(s.canvas_id, gl.DEFAULT_CONTEXT_ATTRIBUTES)
	log.ensuref(context_ok, "Could not create context for canvas ID %s", s.canvas_id)
	set_context_ok := gl.SetCurrentContextById(s.canvas_id)
	log.ensuref(set_context_ok, "Failed setting context with canvas ID %s", s.canvas_id)

	s.vertex_buffer_gpu = gl.CreateBuffer()

	gl.BindBuffer(gl.ARRAY_BUFFER, s.vertex_buffer_gpu)
	gl.BufferData(gl.ARRAY_BUFFER, VERTEX_BUFFER_MAX, nil, gl.STREAM_DRAW)

	gl.Enable(gl.BLEND)

	gl.Viewport(0, 0, i32(s.width), i32(s.height))
}

webgl_shutdown :: proc() {
	gl.DeleteBuffer(s.vertex_buffer_gpu)
}

webgl_clear :: proc(render_target: Render_Target_Handle, color: Color) {
	if rt := hm.get(&s.render_targets, render_target); rt != nil {
		gl.BindFramebuffer(gl.FRAMEBUFFER, rt.framebuffer)
		gl.Viewport(0, 0, i32(rt.width), i32(rt.height))
	} else {
		gl.BindFramebuffer(gl.FRAMEBUFFER, 0)
		gl.Viewport(0, 0, i32(s.width), i32(s.height))
	}

	c := f32_color_from_color(color)
	gl.ClearColor(c.r, c.g, c.b, c.a)
	gl.Clear(u32(gl.COLOR_BUFFER_BIT))
}

webgl_present :: proc() {
	// The browser flips the backbuffer for you when 'step' ends
}

webgl_draw :: proc(
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
			uptr: [^]u32 = (^u32)(ptr)
			iptr: [^]i32 = (^i32)(ptr)
			fptr: [^]f32 = (^f32)(ptr)

			switch gpu_loc.uniform_type {
			case gl.FLOAT:
				gl.Uniform1f(loc, fptr[0])

			case gl.FLOAT_VEC2:
				gl.Uniform2f(loc, fptr[0], fptr[1])
			case gl.FLOAT_MAT2:
				gl.UniformMatrix2fv(loc, (^matrix[2,2]f32)(ptr)^)
			case gl.FLOAT_MAT2x3:
				gl.UniformMatrix2x3fv(loc, (^matrix[3,2]f32)(ptr)^)
			case gl.FLOAT_MAT2x4:
				gl.UniformMatrix2x4fv(loc, (^matrix[4,2]f32)(ptr)^)

			case gl.FLOAT_VEC3:
				gl.Uniform3f(loc, fptr[0], fptr[1], fptr[2])
			case gl.FLOAT_MAT3x2:
				gl.UniformMatrix3x2fv(loc, (^matrix[2,3]f32)(ptr)^)
			case gl.FLOAT_MAT3:
				gl.UniformMatrix3fv(loc, (^matrix[3,3]f32)(ptr)^)
			case gl.FLOAT_MAT3x4:
				gl.UniformMatrix3x4fv(loc, (^matrix[4,3]f32)(ptr)^)

			case gl.FLOAT_VEC4:
				gl.Uniform4f(loc, fptr[0], fptr[1], fptr[2], fptr[3])
			case gl.FLOAT_MAT4x2:
				gl.UniformMatrix4x2fv(loc, (^matrix[2,4]f32)(ptr)^)
			case gl.FLOAT_MAT4x3:
				gl.UniformMatrix4x3fv(loc, (^matrix[3,4]f32)(ptr)^)
			case gl.FLOAT_MAT4:
				gl.UniformMatrix4fv(loc, (^matrix[4,4]f32)(ptr)^)

			case gl.INT:
				gl.Uniform1i(loc, iptr[0])
			case gl.INT_VEC2:
				gl.Uniform2i(loc, iptr[0], iptr[1])
			case gl.INT_VEC3:
				gl.Uniform3i(loc, iptr[0], iptr[1], iptr[2])
			case gl.INT_VEC4:
				gl.Uniform4i(loc, iptr[0], iptr[1], iptr[2], iptr[3])

			case gl.UNSIGNED_INT:
				gl.Uniform1ui(loc, uptr[0])
			case gl.UNSIGNED_INT_VEC2:
				gl.Uniform2ui(loc, uptr[0], uptr[1])
			case gl.UNSIGNED_INT_VEC3:
				gl.Uniform3ui(loc, uptr[0], uptr[1], uptr[2])
			case gl.UNSIGNED_INT_VEC4:
				gl.Uniform4ui(loc, uptr[0], uptr[1], uptr[2], uptr[3])

			case: log.errorf("Unknown type: %x", gpu_loc.uniform_type)
			}
			
		}
	}

	gl.BindBuffer(gl.ARRAY_BUFFER, s.vertex_buffer_gpu)
	gl.BufferDataSlice(gl.ARRAY_BUFFER, vertex_buffer, gl.STREAM_DRAW)

	if len(bound_textures) == len(gl_shd.texture_bindings) {
		for t, t_idx in bound_textures {
			gl_t := gl_shd.texture_bindings[t_idx]

			if t := hm.get(&s.textures, t); t != nil {
				gl.ActiveTexture(gl.TEXTURE0 + gl.Enum(t_idx))
				gl.BindTexture(gl.TEXTURE_2D, t.id)
				gl.Uniform1i(gl_t.loc, i32(t_idx))
			} else {
				gl.ActiveTexture(gl.TEXTURE0 + gl.Enum(t_idx))
				gl.BindTexture(gl.TEXTURE_2D, 0)
				gl.Uniform1i(gl_t.loc, i32(t_idx))
			}
		}
	}

	if rt := hm.get(&s.render_targets, render_target); rt != nil {
		gl.BindFramebuffer(gl.FRAMEBUFFER, rt.framebuffer)
		gl.Viewport(0, 0, i32(rt.width), i32(rt.height))
	} else {
		gl.BindFramebuffer(gl.FRAMEBUFFER, 0)
		gl.Viewport(0, 0, i32(s.width), i32(s.height))
	}

	gl.DrawArrays(gl.TRIANGLES, 0, int(len(vertex_buffer)/shd.vertex_size))
}

webgl_resize_swapchain :: proc(w, h: int) {
	s.width = w
	s.height = h
	gl.Viewport(0, 0, i32(w), i32(h))
}

webgl_get_swapchain_width :: proc() -> int {
	return s.width
}

webgl_get_swapchain_height :: proc() -> int {
	return s.height
}

webgl_set_internal_state :: proc(state: rawptr) {
	s = (^WebGL_State)(state)
}

create_texture :: proc(width: int, height: int, format: Pixel_Format, data: rawptr) -> WebGL_Texture {
	id := gl.CreateTexture()
	gl.BindTexture(gl.TEXTURE_2D, id)

	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, i32(gl.REPEAT))
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, i32(gl.REPEAT))
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, i32(gl.NEAREST))
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, i32(gl.NEAREST))

	pf := gl_translate_pixel_format(format)

	data_size := width*height*pixel_format_size(format)
	gl.TexImage2D(gl.TEXTURE_2D, 0, pf, i32(width), i32(height), 0, gl.RGBA, gl.UNSIGNED_BYTE, data_size, data)

	return {
		id = id,
		format = format,
	}
}

webgl_create_texture :: proc(width: int, height: int, format: Pixel_Format) -> Texture_Handle {
	return hm.add(&s.textures, create_texture(width, height, format, nil))
}

webgl_load_texture :: proc(data: []u8, width: int, height: int, format: Pixel_Format) -> Texture_Handle {
	return hm.add(&s.textures, create_texture(width, height, format, raw_data(data)))
}

webgl_update_texture :: proc(th: Texture_Handle, data: []u8, rect: Rect) -> bool {
	tex := hm.get(&s.textures, th)

	if tex == nil {
		return false
	}

    gl.BindTexture(gl.TEXTURE_2D, tex.id)
	gl.TexSubImage2D(gl.TEXTURE_2D, 0, i32(rect.x), i32(rect.y), i32(rect.w), i32(rect.h), gl.RGBA, gl.UNSIGNED_BYTE, len(data), raw_data(data))
	return true
}

webgl_destroy_texture :: proc(th: Texture_Handle) {
	tex := hm.get(&s.textures, th)

	if tex == nil {
		return
	}

	gl.DeleteTexture(tex.id)
	hm.remove(&s.textures, th)
}

webgl_texture_needs_vertical_flip :: proc(th: Texture_Handle) -> bool {
	tex := hm.get(&s.textures, th)

	if tex == nil {
		return false
	}

	return tex.needs_vertical_flip
}

webgl_create_render_texture :: proc(width: int, height: int) -> (Texture_Handle, Render_Target_Handle) {
	texture := create_texture(width, height, .RGBA_32_Float, nil)
	texture.needs_vertical_flip = true
	
	framebuffer := gl.CreateFramebuffer()
	gl.BindFramebuffer(gl.FRAMEBUFFER, framebuffer)

	gl.FramebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, texture.id, 0)
	gl.DrawBuffers({gl.COLOR_ATTACHMENT0})

	if gl.CheckFramebufferStatus(gl.FRAMEBUFFER) != gl.FRAMEBUFFER_COMPLETE {
		log.errorf("Failed creating frame buffer of size %v x %v", width, height)
		return {}, {}
	}

	gl.BindFramebuffer(gl.FRAMEBUFFER, 0)
	gl.BindRenderbuffer(gl.RENDERBUFFER, 0)

	rt := WebGL_Render_Target {
		framebuffer = framebuffer,
		width = width,
		height = height,
	}

	return hm.add(&s.textures, texture), hm.add(&s.render_targets, rt)
}

webgl_destroy_render_target :: proc(render_target: Render_Target_Handle) {
	if rt := hm.get(&s.render_targets, render_target); rt != nil {
		gl.DeleteFramebuffer(rt.framebuffer)
	}
}

webgl_set_texture_filter :: proc(
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

	min_filter := scale_down_filter == .Point ? gl.NEAREST : gl.LINEAR
	mag_filter := scale_up_filter == .Point ? gl.NEAREST : gl.LINEAR

	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, i32(min_filter))
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, i32(mag_filter))
}

Shader_Compile_Result_OK :: struct {}

Shader_Compile_Result_Error :: string

Shader_Compile_Result :: union #no_nil {
	Shader_Compile_Result_OK,
	Shader_Compile_Result_Error,
}

compile_shader_from_source :: proc(shader_data: []byte, shader_type: gl.Enum, err_buf: []u8, err_msg: ^string) -> (shader_id: gl.Shader, ok: bool) {
	shader_id = gl.CreateShader(shader_type)
	gl.ShaderSource(shader_id, { string(shader_data) })
	gl.CompileShader(shader_id)

	result := gl.GetShaderiv(shader_id, gl.COMPILE_STATUS)
		
	if result != 1 {
		err_msg^ = gl.GetShaderInfoLog(shader_id, err_buf)
		gl.DeleteShader(shader_id)
		return 0, false
	}

	return shader_id, true
}

link_shader :: proc(vs_shader: gl.Shader, fs_shader: gl.Shader, err_buf: []u8, err_msg: ^string) -> (program_id: gl.Program, ok: bool) {
	program_id = gl.CreateProgram()
	gl.AttachShader(program_id, vs_shader)
	gl.AttachShader(program_id, fs_shader)
	gl.LinkProgram(program_id)

	status := gl.GetProgramParameter(program_id, gl.LINK_STATUS)

	if status != 1 {
		err_msg^ = gl.GetProgramInfoLog(program_id, err_buf)
		gl.DeleteProgram(program_id)
		return 0, false
	}

	return program_id, true
}

webgl_load_shader :: proc(vs_source: []byte, fs_source: []byte, desc_allocator := frame_allocator, layout_formats: []Pixel_Format = {}) -> (handle: Shader_Handle, desc: Shader_Desc) {
	@static err: [1024]u8
	err_msg: string
	vs_shader, vs_shader_ok := compile_shader_from_source(vs_source, gl.VERTEX_SHADER, err[:], &err_msg)

	if !vs_shader_ok  {
		log.error(err_msg)
		return {}, {}
	}
	
	fs_shader, fs_shader_ok := compile_shader_from_source(fs_source, gl.FRAGMENT_SHADER, err[:], &err_msg)

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
		num_attribs := gl.GetProgramParameter(program, gl.ACTIVE_ATTRIBUTES)
		desc.inputs = make([]Shader_Input, num_attribs, desc_allocator)

		for i in 0..<num_attribs {
			attrib_info := gl.GetActiveAttrib(program, u32(i), frame_allocator)
			loc := gl.GetAttribLocation(program, attrib_info.name)

			type: Shader_Input_Type

			switch attrib_info.type {
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

			case: log.errorf("Unknown type: %v", attrib_info.type)
			}

			name := strings.clone(attrib_info.name, desc_allocator)
			
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

	gl_shd := WebGL_Shader {
		program = program,
		vao = gl.CreateVertexArray(),
	}

	gl.BindVertexArray(gl_shd.vao)

	offset: int
	for idx in 0..<len(desc.inputs) {
		input := desc.inputs[idx]
		format_size := pixel_format_size(input.format)
		gl.EnableVertexAttribArray(i32(input.register))	
		format, num_components, norm := gl_describe_pixel_format(input.format)
		gl.VertexAttribPointer(i32(input.register), num_components, format, norm, stride, uintptr(offset))
		offset += format_size
	}

	constant_descs := make([dynamic]Shader_Constant_Desc, desc_allocator)
	gl_constants := make([dynamic]WebGL_Shader_Constant, s.allocator)
	texture_bindpoint_descs := make([dynamic]Shader_Texture_Bindpoint_Desc, desc_allocator)
	gl_texture_bindings := make([dynamic]WebGL_Texture_Binding, s.allocator)

	{
		num_active_uniforms := gl.GetProgramParameter(program, gl.ACTIVE_UNIFORMS)

		for cidx in 0..<num_active_uniforms {
			uniform_info := gl.GetActiveUniform(program, u32(cidx), frame_allocator)
			loc := gl.GetUniformLocation(program, uniform_info.name)

			if uniform_info.type == gl.SAMPLER_2D {
				append(&texture_bindpoint_descs, Shader_Texture_Bindpoint_Desc {
					name = strings.clone(uniform_info.name, desc_allocator),
				})

				append(&gl_texture_bindings, WebGL_Texture_Binding {
					loc = loc,
				})
			} else {
				append(&constant_descs, Shader_Constant_Desc {
					name = strings.clone(uniform_info.name, desc_allocator),
					size = uniform_size(uniform_info.type),
				})

				append(&gl_constants, WebGL_Shader_Constant {
					type = .Uniform,
					loc = loc,
					uniform_type = uniform_info.type,
				})
			}
		}
	}

	// Blocks are like constant buffers in D3D, it's like a struct with multiple uniforms inside
	{
		num_active_uniform_blocks := gl.GetProgramParameter(program, gl.ACTIVE_UNIFORM_BLOCKS)
		gl_shd.constant_buffers = make([]WebGL_Shader_Constant_Buffer, num_active_uniform_blocks, s.allocator)

		for cb_idx in 0..<num_active_uniform_blocks {
			name := gl.GetActiveUniformBlockName(program, i32(cb_idx), frame_allocator)
			idx := gl.GetUniformBlockIndex(program, name)

			if i32(idx) >= num_active_uniform_blocks {
				continue
			}

			size: i32

			// TODO investigate if we need std140 layout in the shader or what is fine?
			gl.GetActiveUniformBlockParameter(program, idx, gl.UNIFORM_BLOCK_DATA_SIZE, &size)

			if size == 0 {
				log.errorf("Uniform block %v has size 0", name)
				continue
			}

			buf := gl.CreateBuffer()
			gl.BindBuffer(gl.UNIFORM_BUFFER, buf)
			gl.BufferData(gl.UNIFORM_BUFFER, int(size), nil, gl.DYNAMIC_DRAW)
			gl.BindBufferBase(gl.UNIFORM_BUFFER, idx, buf)

			gl_shd.constant_buffers[cb_idx] = {
				block_index = idx,
				buffer = buf,
				size = int(size),
			}

			num_uniforms: i32
			gl.GetActiveUniformBlockParameter(program, idx, gl.UNIFORM_BLOCK_ACTIVE_UNIFORMS, &num_uniforms)

			uniform_indices := make([]i32, num_uniforms, frame_allocator)
			gl.GetActiveUniformBlockParameter(program, idx, gl.UNIFORM_BLOCK_ACTIVE_UNIFORM_INDICES, raw_data(uniform_indices))

			for var_idx in 0..<num_uniforms {
				uniform_idx := u32(uniform_indices[var_idx])

				offset: i32
				gl.GetActiveUniforms(program, { uniform_idx }, gl.UNIFORM_OFFSET, &offset)

				uniform_info := gl.GetActiveUniform(program, uniform_idx, desc_allocator)

				append(&constant_descs, Shader_Constant_Desc {
					name = uniform_info.name,
					size = uniform_size(uniform_info.type),
				})

				append(&gl_constants, WebGL_Shader_Constant {
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
uniform_size :: proc(t: gl.Enum) -> int {
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

gl_translate_pixel_format :: proc(f: Pixel_Format) -> gl.Enum {
	switch f {
	case .RGBA_32_Float: return gl.RGBA
	case .RGB_32_Float: return gl.RGB
	case .RG_32_Float: return gl.RG
	case .R_32_Float: return gl.RED

	// IS THIS STUFF CORRECT? Compare to GL backend
	// Do we need float textures? What is happening...
	case .RGBA_8_Norm: return gl.RGBA
	case .RG_8_Norm: return gl.RG
	case .R_8_Norm: return gl.RED
	case .R_8_UInt: return gl.RED

	case .Unknown: fallthrough
	case: log.error("Unhandled pixel format %v", f) 
	}
	
	return 0
}


gl_describe_pixel_format :: proc(f: Pixel_Format) -> (format: gl.Enum, num_components: int, normalized: bool) {
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

webgl_destroy_shader :: proc(h: Shader_Handle) {
	shd := hm.get(&s.shaders, h)

	if shd == nil {
		log.errorf("Invalid shader: %v", h)
		return
	}

	delete(shd.constant_buffers, s.allocator)
	delete(shd.constants, s.allocator)
	delete(shd.texture_bindings, s.allocator)
}

webgl_default_shader_vertex_source :: proc() -> []byte {
	vertex_source := #load("render_backend_gl_default_vertex_shader_webgl.glsl")
	return vertex_source
}

webgl_default_shader_fragment_source :: proc() -> []byte {
	fragment_source := #load("render_backend_gl_default_fragment_shader_webgl.glsl")
	return fragment_source
}

