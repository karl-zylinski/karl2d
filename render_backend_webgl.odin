#+build js
#+vet explicit-allocators
#+private package
package karl2d

import "base:runtime"
import gl "vendor:wasm/WebGL"
import hm "core:container/handle_map"
import "log"
import "core:strings"
import sc "shader_compiler"

RENDER_BACKEND_WEBGL :: Render_Backend_Interface {
	state_type = WebGL_State,
	init = webgl_init,
	shutdown = webgl_shutdown,
	clear = webgl_clear,
	present = webgl_present,
	set_vsync = webgl_set_vsync,
	draw = webgl_draw,
	resize_swapchain = webgl_resize_swapchain,
	get_swapchain_width = webgl_get_swapchain_width,
	get_swapchain_height = webgl_get_swapchain_height,
	create_texture = webgl_create_texture,
	load_texture = webgl_load_texture,
	update_texture = webgl_update_texture,
	generate_mipmap = webgl_generate_mipmap,
	destroy_texture = webgl_destroy_texture,
	flip_render_textures = true,
	create_render_texture = webgl_create_render_texture,
	destroy_render_target = webgl_destroy_render_target,
	shader_target = .GLSL_ES_300,
	load_shader = webgl_load_shader,
	destroy_shader = webgl_destroy_shader,
	read_backbuffer = webgl_read_backbuffer,

	get_depth_clip_range = webgl_get_depth_clip_range,
}

WebGL_State :: struct {
	using _: Render_Backend_State,
	canvas_id: string,
	width: int,
	height: int,
	allocator: runtime.Allocator,
	shaders: hm.Dynamic_Handle_Map(WebGL_Shader, Shader_Handle),
	vertex_buffer_gpu: gl.Buffer,
	textures: hm.Dynamic_Handle_Map(WebGL_Texture, Render_Backend_Texture),
	render_targets: hm.Dynamic_Handle_Map(WebGL_Render_Target, Render_Target_Handle),
	depth_test: bool,
	border_wrap_warning_shown: bool,
	texture_samplers: map[Texture_Sampler]gl.Sampler,
}

WebGL_Texture :: struct {
	handle: Render_Backend_Texture,
	id: gl.Texture,
	format: Pixel_Format,
}

WebGL_Texture_Binding :: struct {
	loc: i32,
}

WebGL_Render_Target :: struct {
	handle: Render_Target_Handle,
	framebuffer: gl.Framebuffer,
	width: int,
	height: int,

	// Only set up when depth testing is enabled, see WebGL_State.depth_test.
	depth_renderbuffer: gl.Renderbuffer,
}

WebGL_Shader :: struct {
	handle: Shader_Handle,

	// This is like the "input layout"
	vao: gl.VertexArrayObject,

	program: gl.Program,

	constant_buffer: gl.Buffer,
	has_constant_buffer: bool,
	texture_bindings: []WebGL_Texture_Binding, 
}

webgl_init :: proc(
	s: ^WebGL_State,
	glue: ^Window_Render_Glue,
	swapchain_width: int,
	swapchain_height: int,
	options: Init_Options,
	allocator := context.allocator,
) {
	// see web_get_window_render_glue
	canvas_id := (^Web_HTML_Canvas_ID)(glue)^
	
	s.canvas_id = strings.clone(canvas_id, allocator)
	s.width = swapchain_width
	s.height = swapchain_height
	s.allocator = allocator
	s.texture_samplers = make(map[Texture_Sampler]gl.Sampler, allocator)
	s.depth_test = options.depth_test

	hm.dynamic_init(&s.shaders, allocator)
	hm.dynamic_init(&s.textures, allocator)
	hm.dynamic_init(&s.render_targets, allocator)

	context_attribs := gl.DEFAULT_CONTEXT_ATTRIBUTES

	if options.anti_alias {
		context_attribs -= { .disableAntialias }
	} else {
		context_attribs += { .disableAntialias }
	}

	// The canvas has a depth buffer by default, so only ask the browser to skip creating one when
	// depth testing is off.
	if s.depth_test {
		context_attribs -= { .disableDepth }
	} else {
		context_attribs += { .disableDepth }
	}

	context_ok := gl.CreateCurrentContextById(s.canvas_id, context_attribs)
	log.ensuref(context_ok, "Could not create context for canvas ID %s", s.canvas_id)
	set_context_ok := gl.SetCurrentContextById(s.canvas_id)
	log.ensuref(set_context_ok, "Failed setting context with canvas ID %s", s.canvas_id)

	s.vertex_buffer_gpu = gl.CreateBuffer()

	gl.BindBuffer(gl.ARRAY_BUFFER, s.vertex_buffer_gpu)
	gl.BufferData(gl.ARRAY_BUFFER, VERTEX_BUFFER_MAX, nil, gl.STREAM_DRAW)
	gl.BindBuffer(gl.ARRAY_BUFFER, 0)

	gl.Disable(gl.CULL_FACE)
	gl.Enable(gl.BLEND)
	gl.PixelStorei(gl.UNPACK_ALIGNMENT, 1)
	gl.GetExtension("EXT_color_buffer_float")
	gl.GetExtension("OES_texture_float_linear")

	if s.depth_test {
		gl.Enable(gl.DEPTH_TEST)

		// Higher z ends up in front. GEQUAL instead of GREATER so that things drawn at the same z
		// fall back to drawing order, like when depth testing is off.
		gl.DepthFunc(gl.GEQUAL)
		gl.ClearDepth(0)
	}

	gl.Viewport(0, 0, i32(s.width), i32(s.height))

	if options.disable_vsync {
		log.warn("Disabling vsync on the web is not supported.")
	}
}

webgl_shutdown :: proc(s: ^WebGL_State) {
	gl.DeleteBuffer(s.vertex_buffer_gpu)
	for _, smp in s.texture_samplers {
		gl.DeleteSampler(smp)
	}

	delete(s.texture_samplers)
	hm.dynamic_destroy(&s.shaders)
	hm.dynamic_destroy(&s.textures)
	hm.dynamic_destroy(&s.render_targets)
	delete_string(s.canvas_id, s.allocator)
}

webgl_clear :: proc(s: ^WebGL_State, render_target: Render_Target_Handle, color: Color) {
	if rt := hm.get(&s.render_targets, render_target); rt != nil {
		gl.BindFramebuffer(gl.FRAMEBUFFER, rt.framebuffer)
		gl.Viewport(0, 0, i32(rt.width), i32(rt.height))
	} else {
		gl.BindFramebuffer(gl.FRAMEBUFFER, 0)
		gl.Viewport(0, 0, i32(s.width), i32(s.height))
	}

	c := f32_color_from_color(color)
	gl.ClearColor(c.r, c.g, c.b, c.a)

	clear_mask := u32(gl.COLOR_BUFFER_BIT)

	if s.depth_test {
		// glClear of the depth buffer is gated by the depth mask, so it must be on for this to
		// have any effect. draw() doesn't touch the mask, so this only needs setting once here.
		gl.DepthMask(true)
		clear_mask |= u32(gl.DEPTH_BUFFER_BIT)
	}

	gl.Clear(clear_mask)
}

webgl_present :: proc(s: ^WebGL_State) {
	// The browser flips the backbuffer for you when 'step' ends
}

webgl_set_vsync :: proc(s: ^WebGL_State, enabled: bool) {
	if enabled == false {
		log.warn("Disabling vsync on the web is not supported.")
	}
}

webgl_draw :: proc(s: ^WebGL_State, vertex_buffer: []u8, draw_calls: []Draw_Call) {
	if len(vertex_buffer) == 0 || len(draw_calls) == 0 {
		return
	}

	// All the draw calls read from this one buffer. It only needs uploading once. That matters more
	// here than in the other backends. Every GL call crosses into JavaScript.
	gl.BindBuffer(gl.ARRAY_BUFFER, s.vertex_buffer_gpu)
	gl.BufferDataSlice(gl.ARRAY_BUFFER, vertex_buffer, gl.STREAM_DRAW)
	gl.BindBuffer(gl.ARRAY_BUFFER, 0)

	// Changes that belong to draw calls we could not draw. They never reached GL. The next draw
	// call we do run has to make them.
	missed: bit_set[Draw_Call_Change]

	for &call in draw_calls {
		changed := call.changed + missed
		gl_shd := hm.get(&s.shaders, call.shader)

		if gl_shd == nil {
			log.errorf("Trying to draw with invalid shader %v", call.shader)
			missed = changed
			continue
		}

		missed = {}

		if .Shader in changed {
			gl.BindVertexArray(gl_shd.vao)
			gl.UseProgram(gl_shd.program)
		}

		if .Constants in changed {
			webgl_set_constants(call.constants_data, gl_shd^)
		}

		if .Textures in changed {
			webgl_bind_textures(s, call.textures, gl_shd^)
		}

		// Only the render target and scissor setup need the render target. Skipping the lookup
		// otherwise keeps it out of the common case, where only the texture changed.
		rt: ^WebGL_Render_Target

		if .Render_Target in changed || .Scissor in changed {
			rt = hm.get(&s.render_targets, call.render_target)
		}

		if .Render_Target in changed {
			if rt != nil {
				gl.BindFramebuffer(gl.FRAMEBUFFER, rt.framebuffer)
				gl.Viewport(0, 0, i32(rt.width), i32(rt.height))
			} else {
				gl.BindFramebuffer(gl.FRAMEBUFFER, 0)
				gl.Viewport(0, 0, i32(s.width), i32(s.height))
			}
		}

		if .Blend_Mode in changed {
			switch call.blend_mode {
			case .Alpha: gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)
			case .Premultiplied_Alpha: gl.BlendFunc(gl.ONE, gl.ONE_MINUS_SRC_ALPHA)
			case .Additive: gl.BlendFunc(gl.SRC_ALPHA, gl.ONE)
			}
		}

		// Karl2D measures the scissor rect from the top. GL measures it from the bottom. It
		// therefore depends on the height of the render target as well.
		if .Scissor in changed {
			if scissor, has_scissor := call.scissor.(Rect); has_scissor {
				height := rt != nil ? rt.height : s.height
				flipped_y := f32(height) - scissor.h - scissor.y

				gl.Enable(gl.SCISSOR_TEST)
				gl.Scissor(i32(scissor.x), i32(flipped_y), i32(scissor.w), i32(scissor.h))
			} else {
				gl.Disable(gl.SCISSOR_TEST)
			}
		}

		gl.DrawArrays(gl.TRIANGLES, call.vertex_offset/call.vertex_size, call.vertex_count)
	}

	gl.Disable(gl.SCISSOR_TEST)
}

webgl_set_constants :: proc(
	constants_data: []u8,
	gl_shd: WebGL_Shader,
) {
	if !gl_shd.has_constant_buffer {
		return
	}

	gl.BindBuffer(gl.UNIFORM_BUFFER, gl_shd.constant_buffer)
	gl.BufferData(gl.UNIFORM_BUFFER, len(constants_data), raw_data(constants_data), gl.DYNAMIC_DRAW)
	gl.BindBufferBase(gl.UNIFORM_BUFFER, 0, gl_shd.constant_buffer)
}

webgl_bind_textures :: proc(s: ^WebGL_State, textures: []Draw_Call_Texture, gl_shd: WebGL_Shader) {
	if len(textures) != len(gl_shd.texture_bindings) {
		return
	}

	for t, t_idx in textures {
		gl_t := gl_shd.texture_bindings[t_idx]
		gl.ActiveTexture(gl.TEXTURE0 + gl.Enum(t_idx))

		gl.BindSampler(gl.Enum(t_idx), webgl_get_texture_sampler(s, t.sampler))

		if tex := hm.get(&s.textures, t.handle); tex != nil {
			gl.BindTexture(gl.TEXTURE_2D, tex.id)
		} else {
			gl.BindTexture(gl.TEXTURE_2D, 0)
		}

		gl.Uniform1i(gl_t.loc, i32(t_idx))
	}
}

webgl_resize_swapchain :: proc(s: ^WebGL_State, w, h: int) {
	s.width = w
	s.height = h
	gl.Viewport(0, 0, i32(w), i32(h))
}

webgl_get_swapchain_width :: proc(s: ^WebGL_State) -> int {
	return s.width
}

webgl_get_swapchain_height :: proc(s: ^WebGL_State) -> int {
	return s.height
}

// WebGL hands out errors through a queue instead of return values, and nothing else in this backend
// reads it, so it can hold something an earlier call left behind. Empty it, so that a check right
// after a call only sees what that call did. The bound stops a lost context spinning here forever.
WEBGL_ERROR_QUEUE_DRAIN_LIMIT :: 32

webgl_drain_errors :: proc() {
	for _ in 0..<WEBGL_ERROR_QUEUE_DRAIN_LIMIT {
		if gl.GetError() == gl.NO_ERROR {
			return
		}
	}
}

_webgl_create_texture :: proc(
	width: int,
	height: int,
	format: Pixel_Format,
	data: [][]u8,
) -> (WebGL_Texture, bool) {
	id := gl.CreateTexture()
	gl.BindTexture(gl.TEXTURE_2D, id)

	internal_format, pixel_format, pixel_type := webgl_translate_pixel_format(format)

	webgl_drain_errors()

	level_width := width
	level_height := height

	for level_data, level in data {
		gl.TexImage2D(gl.TEXTURE_2D, i32(level), internal_format, i32(level_width), i32(level_height), 0, pixel_format, pixel_type, len(level_data), raw_data(level_data))
		level_width = max(level_width / 2, 1)
		level_height = max(level_height / 2, 1)
	}

	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAX_LEVEL, i32(len(data) - 1))

	// This is where a texture that is too big for the GPU, or one the GPU has no memory left for,
	// gets caught. Without the check it would become a texture that silently draws nothing.
	if err := gl.GetError(); err != gl.NO_ERROR {
		log.errorf("Failed creating %v x %v texture. GL error: %v", width, height, err)
		gl.DeleteTexture(id)
		return {}, false
	}

	return {
		id = id,
		format = format,
	}, true
}

webgl_create_texture :: proc(
	s: ^WebGL_State,
	width: int,
	height: int,
	format: Pixel_Format,
	mip_levels: int,
) -> (Render_Backend_Texture, bool) {
	@(static, rodata) empty_data: [MAX_MIP_LEVELS][]u8
	texture, texture_ok := _webgl_create_texture(width, height, format, empty_data[:mip_levels])

	if !texture_ok {
		return RENDER_BACKEND_TEXTURE_NONE, false
	}

	texture_handle, texture_handle_err := hm.add(&s.textures, texture)

	if texture_handle_err != nil {
		log.errorf("Failed adding texture to handle map: %v", texture_handle_err)
		gl.DeleteTexture(texture.id)
		return RENDER_BACKEND_TEXTURE_NONE, false
	}

	return texture_handle, true
}

webgl_load_texture :: proc(
	s: ^WebGL_State,
	data: [][]u8,
	width: int,
	height: int,
	format: Pixel_Format,
) -> (Render_Backend_Texture, bool) {
	texture, texture_ok := _webgl_create_texture(width, height, format, data)

	if !texture_ok {
		return RENDER_BACKEND_TEXTURE_NONE, false
	}

	texture_handle, texture_handle_err := hm.add(&s.textures, texture)

	if texture_handle_err != nil {
		log.errorf("Failed adding texture to handle map: %v", texture_handle_err)
		gl.DeleteTexture(texture.id)
		return RENDER_BACKEND_TEXTURE_NONE, false
	}

	return texture_handle, true
}

webgl_update_texture :: proc(
	s: ^WebGL_State,
	th: Render_Backend_Texture,
	data: []u8,
	rect: Rect,
	pitch: int,
	mip_level: int,
) -> bool {
	tex := hm.get(&s.textures, th)

	if tex == nil {
		return false
	}

	_, pixel_format, pixel_type := webgl_translate_pixel_format(tex.format)
	gl.BindTexture(gl.TEXTURE_2D, tex.id)
	gl.PixelStorei(gl.UNPACK_ROW_LENGTH, i32(pitch / pixel_format_size(tex.format)))
	gl.TexSubImage2D(gl.TEXTURE_2D, i32(mip_level), i32(rect.x), i32(rect.y), i32(rect.w), i32(rect.h), pixel_format, pixel_type, len(data), raw_data(data))
	gl.PixelStorei(gl.UNPACK_ROW_LENGTH, 0)
	return true
}

webgl_generate_mipmap :: proc(s: ^WebGL_State, th: Render_Backend_Texture) -> bool {
	tex := hm.get(&s.textures, th)

	if tex == nil {
		log.errorf("Trying to generate mipmap for texture %v, but it is invalid.", th)
		return false
	}

	gl.BindTexture(gl.TEXTURE_2D, tex.id)
	webgl_drain_errors()
	gl.GenerateMipmap(gl.TEXTURE_2D)

	if err := gl.GetError(); err != gl.NO_ERROR {
		log.errorf("Failed generating mipmap. GL error: %v", err)
		return false
	}

	return true
}

webgl_destroy_texture :: proc(s: ^WebGL_State, th: Render_Backend_Texture) {
	tex := hm.get(&s.textures, th)

	if tex == nil {
		return
	}

	gl.DeleteTexture(tex.id)
	hm.remove(&s.textures, th)
}

webgl_create_render_texture :: proc(
	s: ^WebGL_State,
	width: int,
	height: int,
	mip_levels: int,
) -> (Render_Backend_Texture, Render_Target_Handle, bool) {
	@(static, rodata) empty_data: [MAX_MIP_LEVELS][]u8
	texture, texture_ok := _webgl_create_texture(width, height, .RGBA_32_Float, empty_data[:mip_levels])

	if !texture_ok {
		return RENDER_BACKEND_TEXTURE_NONE, RENDER_TARGET_NONE, false
	}

	framebuffer := gl.CreateFramebuffer()
	gl.BindFramebuffer(gl.FRAMEBUFFER, framebuffer)

	gl.FramebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, texture.id, 0)
	gl.DrawBuffers({gl.COLOR_ATTACHMENT0})

	depth_renderbuffer: gl.Renderbuffer

	if s.depth_test {
		depth_renderbuffer = gl.CreateRenderbuffer()
		gl.BindRenderbuffer(gl.RENDERBUFFER, depth_renderbuffer)
		gl.RenderbufferStorage(gl.RENDERBUFFER, gl.DEPTH_COMPONENT24, i32(width), i32(height))

		gl.FramebufferRenderbuffer(
			gl.FRAMEBUFFER, gl.DEPTH_ATTACHMENT, gl.RENDERBUFFER, depth_renderbuffer,
		)
	}

	if gl.CheckFramebufferStatus(gl.FRAMEBUFFER) != gl.FRAMEBUFFER_COMPLETE {
		log.errorf("Failed creating frame buffer of size %v x %v", width, height)
		gl.BindFramebuffer(gl.FRAMEBUFFER, 0)
		gl.BindRenderbuffer(gl.RENDERBUFFER, 0)
		gl.DeleteTexture(texture.id)
		gl.DeleteFramebuffer(framebuffer)

		if s.depth_test {
			gl.DeleteRenderbuffer(depth_renderbuffer)
		}

		return RENDER_BACKEND_TEXTURE_NONE, RENDER_TARGET_NONE, false
	}

	gl.BindFramebuffer(gl.FRAMEBUFFER, 0)
	gl.BindRenderbuffer(gl.RENDERBUFFER, 0)

	rt := WebGL_Render_Target {
		framebuffer = framebuffer,
		width = width,
		height = height,
		depth_renderbuffer = depth_renderbuffer,
	}

	texture_handle, texture_handle_err := hm.add(&s.textures, texture)

	if texture_handle_err != nil {
		log.errorf("Failed adding texture to handle map: %v", texture_handle_err)
		gl.DeleteTexture(texture.id)
		gl.DeleteFramebuffer(framebuffer)

		if s.depth_test {
			gl.DeleteRenderbuffer(depth_renderbuffer)
		}

		return RENDER_BACKEND_TEXTURE_NONE, RENDER_TARGET_NONE, false
	}

	render_target_handle, render_target_handle_err := hm.add(&s.render_targets, rt)

	if render_target_handle_err != nil {
		log.errorf("Failed adding render target to handle map: %v", render_target_handle_err)
		hm.remove(&s.textures, texture_handle)
		gl.DeleteTexture(texture.id)
		gl.DeleteFramebuffer(framebuffer)

		if s.depth_test {
			gl.DeleteRenderbuffer(depth_renderbuffer)
		}

		return RENDER_BACKEND_TEXTURE_NONE, RENDER_TARGET_NONE, false
	}

	return texture_handle, render_target_handle, true
}

webgl_destroy_render_target :: proc(s: ^WebGL_State, render_target: Render_Target_Handle) {
	if rt := hm.get(&s.render_targets, render_target); rt != nil {
		gl.DeleteFramebuffer(rt.framebuffer)

		if rt.depth_renderbuffer != 0 {
			gl.DeleteRenderbuffer(rt.depth_renderbuffer)
		}
	}
}

webgl_get_texture_sampler :: proc(s: ^WebGL_State, sampler: Texture_Sampler) -> gl.Sampler {
	if smp, has_smp := s.texture_samplers[sampler]; has_smp {
		return smp
	}

	if (sampler.wrap_x == .Border || sampler.wrap_y == .Border) && !s.border_wrap_warning_shown {
		log.warn("WebGL does not support the Border texture wrap mode. Using Clamp instead.")
		s.border_wrap_warning_shown = true
	}

	smp := gl.CreateSampler()

	min_filter: gl.Enum

	switch sampler.scale_down_filter {
	case .Point: min_filter = sampler.mip_filter == .Point ? gl.NEAREST_MIPMAP_NEAREST : gl.NEAREST_MIPMAP_LINEAR
	case .Linear: min_filter = sampler.mip_filter == .Point ? gl.LINEAR_MIPMAP_NEAREST : gl.LINEAR_MIPMAP_LINEAR
	}

	mag_filter := sampler.scale_up_filter == .Point ? gl.NEAREST : gl.LINEAR

	gl.SamplerParameteri(smp, gl.TEXTURE_MIN_FILTER, i32(min_filter))
	gl.SamplerParameteri(smp, gl.TEXTURE_MAG_FILTER, i32(mag_filter))

	webgl_translate_texture_wrap :: proc(wrap: Texture_Wrap) -> i32 {
		switch wrap {
		case .Clamp: return i32(gl.CLAMP_TO_EDGE)
		case .Repeat: return i32(gl.REPEAT)
		case .Mirrored_Repeat: return i32(gl.MIRRORED_REPEAT)
		case .Border: return i32(gl.CLAMP_TO_EDGE)
		}

		return i32(gl.CLAMP_TO_EDGE)
	}

	gl.SamplerParameteri(smp, gl.TEXTURE_WRAP_S, webgl_translate_texture_wrap(sampler.wrap_x))
	gl.SamplerParameteri(smp, gl.TEXTURE_WRAP_T, webgl_translate_texture_wrap(sampler.wrap_y))

	s.texture_samplers[sampler] = smp
	return smp
}

webgl_compile_shader_from_source :: proc(shader_data: []byte, shader_type: gl.Enum, err_buf: []u8, err_msg: ^string) -> (shader_id: gl.Shader, ok: bool) {
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

webgl_link_shader :: proc(vs_shader: gl.Shader, fs_shader: gl.Shader, err_buf: []u8, err_msg: ^string) -> (program_id: gl.Program, ok: bool) {
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

webgl_load_shader :: proc(
	s: ^WebGL_State,
	compiled: sc.Compiled_Shader,
	inputs: []Shader_Input,
) -> (
	_handle: Shader_Handle,
	_ok: bool,
) {
	code := compiled.code[.GLSL_ES_300]

	@static err: [1024]u8
	err_msg: string
	vs_shader, vs_shader_ok := webgl_compile_shader_from_source(code.vertex, gl.VERTEX_SHADER, err[:], &err_msg)

	if !vs_shader_ok  {
		log.error(err_msg)
		return
	}
	
	fs_shader, fs_shader_ok := webgl_compile_shader_from_source(code.fragment, gl.FRAGMENT_SHADER, err[:], &err_msg)

	if !fs_shader_ok {
		log.error(err_msg)
		gl.DeleteShader(vs_shader)
		return
	}

	program, program_ok := webgl_link_shader(vs_shader, fs_shader, err[:], &err_msg)
	gl.DeleteShader(vs_shader)
	gl.DeleteShader(fs_shader)

	if !program_ok {
		log.error(err_msg)
		return
	}

	stride: int

	for input in inputs {
		stride += pixel_format_size(input.format)
	}

	gl_shd := WebGL_Shader {
		program = program,
		vao = gl.CreateVertexArray(),
	}

	gl.BindBuffer(gl.ARRAY_BUFFER, s.vertex_buffer_gpu)
	gl.BindVertexArray(gl_shd.vao)

	offset: int
	for input in inputs {
		format_size := pixel_format_size(input.format)
		gl.EnableVertexAttribArray(i32(input.register))	
		format, num_components, norm := webgl_describe_pixel_format(input.format)
		gl.VertexAttribPointer(i32(input.register), num_components, format, norm, stride, uintptr(offset))
		offset += format_size
	}

	gl.BindBuffer(gl.ARRAY_BUFFER, 0)

	if compiled.constants_size > 0 {
		block_index := gl.GetUniformBlockIndex(program, sc.CONSTANTS_BLOCK_NAME)

		if block_index >= 0 {
			gl.UniformBlockBinding(program, block_index, 0)
			gl_shd.constant_buffer = gl.CreateBuffer()
			gl_shd.has_constant_buffer = true
			gl.BindBuffer(gl.UNIFORM_BUFFER, gl_shd.constant_buffer)
			gl.BufferData(gl.UNIFORM_BUFFER, compiled.constants_size, nil, gl.DYNAMIC_DRAW)
			gl.BindBuffer(gl.UNIFORM_BUFFER, 0)
		}
	}

	gl_shd.texture_bindings = make([]WebGL_Texture_Binding, compiled.num_textures, s.allocator)

	for &binding, binding_idx in gl_shd.texture_bindings {
		binding.loc = gl.GetUniformLocation(program, sc.compiled_shader_texture(compiled, binding_idx).name)
	}

	shader_handle, shader_add_err := hm.add(&s.shaders, gl_shd)
	if shader_add_err != nil {
		log.errorf("Failed to add shader. Error: %v", shader_add_err)
		return
	}

	return shader_handle, true
}

webgl_translate_pixel_format :: proc(f: Pixel_Format) -> (internal_format: gl.Enum, format: gl.Enum, type: gl.Enum) {
	switch f {
	case .RGBA_32_Float: return gl.RGBA32F, gl.RGBA, gl.FLOAT
	case .RGB_32_Float: return gl.RGB32F, gl.RGB, gl.FLOAT
	case .RG_32_Float: return gl.RG32F, gl.RG, gl.FLOAT
	case .R_32_Float: return gl.R32F, gl.RED, gl.FLOAT

	case .RGBA_8_Norm: return gl.RGBA8, gl.RGBA, gl.UNSIGNED_BYTE
	case .RG_8_Norm: return gl.RG8, gl.RG, gl.UNSIGNED_BYTE
	case .R_8_Norm: return gl.R8, gl.RED, gl.UNSIGNED_BYTE
	case .R_8_UInt: return gl.R8UI, gl.RED_INTEGER, gl.UNSIGNED_BYTE

	case .Unknown: fallthrough
	case: log.error("Unhandled pixel format %v", f)
	}

	return 0, 0, 0
}


webgl_describe_pixel_format :: proc(f: Pixel_Format) -> (format: gl.Enum, num_components: int, normalized: bool) {
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

webgl_destroy_shader :: proc(s: ^WebGL_State, h: Shader_Handle) {
	shd := hm.get(&s.shaders, h)

	if shd == nil {
		log.errorf("Invalid shader: %v", h)
		return
	}

	delete(shd.texture_bindings, s.allocator)
}

webgl_read_backbuffer :: proc(s: ^WebGL_State, pixels: []u8) -> bool {
	return false
}

webgl_get_depth_clip_range :: proc() -> (min: f32, max: f32) {
	return -1, 1
}
