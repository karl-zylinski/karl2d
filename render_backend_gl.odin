#+build windows, darwin, linux
#+vet explicit-allocators
#+private package
package karl2d

import "base:runtime"
import gl "vendor:OpenGL"
import hm "core:container/handle_map"
import "log"
import "core:strings"
import sc "shader_compiler"

GL_ES :: #config(KARL2D_GL_ES, ODIN_PLATFORM_SUBTARGET == .Android)
GL_SHADER_TARGET :: sc.Target.GLSL_ES_300 when GL_ES else sc.Target.GLSL_330

RENDER_BACKEND_GL :: Render_Backend_Interface {
	state_type = GL_State,
	init = gl_init,
	shutdown = gl_shutdown,
	clear = gl_clear,
	present = gl_present,
	set_vsync = gl_set_vsync,
	draw = gl_draw,
	resize_swapchain = gl_resize_swapchain,
	get_swapchain_width = gl_get_swapchain_width,
	get_swapchain_height = gl_get_swapchain_height,
	create_texture = gl_create_texture,
	load_texture = gl_load_texture,
	update_texture = gl_update_texture,
	generate_mipmap = gl_generate_mipmap,
	destroy_texture = gl_destroy_texture,
	flip_render_textures = true,
	create_render_texture = gl_create_render_texture,
	destroy_render_target = gl_destroy_render_target,
	shader_target = GL_SHADER_TARGET,
	load_shader = gl_load_shader,
	destroy_shader = gl_destroy_shader,
	read_backbuffer = gl_read_backbuffer,

	get_depth_clip_range = gl_get_depth_clip_range,
}

GL_State :: struct {
	using _: Render_Backend_State,
	width: int,
	height: int,
	allocator: runtime.Allocator,
	shaders: hm.Dynamic_Handle_Map(GL_Shader, Shader_Handle),
	glue: ^Window_Render_Glue,
	vertex_buffer_gpu: u32,
	textures: hm.Dynamic_Handle_Map(GL_Texture, Render_Backend_Texture),
	render_targets: hm.Dynamic_Handle_Map(GL_Render_Target, Render_Target_Handle),
	depth_test: bool,
	texture_samplers: map[Texture_Sampler]u32,
	border_wrap_supported: bool,
	border_wrap_warning_shown: bool,
	render_texture_internal_format: i32,
}

GL_Texture :: struct {
	handle: Render_Backend_Texture,
	id: u32,
	format: Pixel_Format,
	internal_format: i32,
}

GL_Pixel_Format :: struct {
	internal_format: i32,
	format: u32,
	type: u32,
}

GL_Texture_Binding :: struct {
	loc: i32,
}

GL_Render_Target :: struct {
	handle: Render_Target_Handle,
	framebuffer: u32,
	width: int,
	height: int,

	// Only set up when depth testing is enabled, see GL_State.depth_test.
	depth_renderbuffer: u32,
}

GL_Shader :: struct {
	handle: Shader_Handle,

	// This is like the "input layout"
	vao: u32,

	program: u32,

	constant_buffer: u32,
	texture_bindings: []GL_Texture_Binding, 
}

gl_init :: proc(
	s: ^GL_State,
	glue: ^Window_Render_Glue,
	swapchain_width: int,
	swapchain_height: int,
	options: Init_Options,
	allocator := context.allocator,
) {
	s.glue = glue
	s.width = swapchain_width
	s.height = swapchain_height
	s.allocator = allocator
	s.depth_test = options.depth_test
	s.texture_samplers = make(map[Texture_Sampler]u32, allocator)

	hm.dynamic_init(&s.shaders, allocator)
	hm.dynamic_init(&s.textures, allocator)
	hm.dynamic_init(&s.render_targets, allocator)

	make_context_ok := s.glue->make_context(options)

	if !make_context_ok {
		log.panic("Could not create a valid gl context")
	}

	gl.GenBuffers(1, &s.vertex_buffer_gpu)
	gl.BindBuffer(gl.ARRAY_BUFFER, s.vertex_buffer_gpu)
	gl.BufferData(gl.ARRAY_BUFFER, VERTEX_BUFFER_MAX, nil, gl.DYNAMIC_DRAW)
	gl.BindBuffer(gl.ARRAY_BUFFER, 0)

	gl.Enable(gl.BLEND)
	gl.Disable(gl.CULL_FACE)
	gl.PixelStorei(gl.UNPACK_ALIGNMENT, 1)

	// Note that AA also requires setup when choosing format for backbuffer, see for example
	// SAMPLE_BUFFER etc in the glue files.
	when !GL_ES {
		if options.anti_alias {
			gl.Enable(gl.MULTISAMPLE)
		} else {
			gl.Disable(gl.MULTISAMPLE)
		}
	}

	if s.depth_test {
		gl.Enable(gl.DEPTH_TEST)

		// Higher z ends up in front. GEQUAL instead of GREATER so that things drawn at the same z
		// fall back to drawing order, like when depth testing is off.
		gl.DepthFunc(gl.GEQUAL)

		when GL_ES {
			gl.ClearDepthf(0)
		} else {
			gl.ClearDepth(0)
		}
	}

	s.border_wrap_supported = true
	s.render_texture_internal_format = gl.RGBA32F

	when GL_ES {
		has_extension :: proc(name: string) -> bool {
			num_extensions: i32
			gl.GetIntegerv(gl.NUM_EXTENSIONS, &num_extensions)

			for extension_idx in 0..<num_extensions {
				if string(gl.GetStringi(gl.EXTENSIONS, u32(extension_idx))) == name {
					return true
				}
			}

			return false
		}

		version_major: i32
		version_minor: i32
		gl.GetIntegerv(gl.MAJOR_VERSION, &version_major)
		gl.GetIntegerv(gl.MINOR_VERSION, &version_minor)

		s.border_wrap_supported = (
			version_major > 3 ||
			(version_major == 3 && version_minor >= 2) ||
			has_extension("GL_EXT_texture_border_clamp") ||
			has_extension("GL_OES_texture_border_clamp")
		)

		color_buffer_float := has_extension("GL_EXT_color_buffer_float")

		if color_buffer_float && has_extension("GL_OES_texture_float_linear") {
			s.render_texture_internal_format = gl.RGBA32F
		} else if color_buffer_float || has_extension("GL_EXT_color_buffer_half_float") {
			s.render_texture_internal_format = gl.RGBA16F
		} else {
			s.render_texture_internal_format = 0
		}
	}
}

gl_shutdown :: proc(s: ^GL_State) {
	gl.DeleteBuffers(1, &s.vertex_buffer_gpu)

	for _, &smp in s.texture_samplers {
		gl.DeleteSamplers(1, &smp)
	}

	delete(s.texture_samplers)
	hm.dynamic_destroy(&s.shaders)
	hm.dynamic_destroy(&s.textures)
	hm.dynamic_destroy(&s.render_targets)
	s.glue->destroy()
}

gl_clear :: proc(s: ^GL_State, render_target: Render_Target_Handle, color: Color) {
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
		clear_mask |= gl.DEPTH_BUFFER_BIT
	}

	gl.Clear(clear_mask)
}

gl_present :: proc(s: ^GL_State) {
	s.glue->present()
}

gl_set_vsync :: proc(s: ^GL_State, enabled: bool) {
	s.glue->set_vsync(enabled)
}

gl_draw :: proc(s: ^GL_State, vertex_buffer: []u8, draw_calls: []Draw_Call) {
	if len(vertex_buffer) == 0 || len(draw_calls) == 0 {
		return
	}

	// All the draw calls read from this one buffer. It only needs uploading once. Orphaning it
	// first lets the driver hand us fresh memory instead of waiting for the previous frame.
	gl.BindBuffer(gl.ARRAY_BUFFER, s.vertex_buffer_gpu)
	gl.BufferData(gl.ARRAY_BUFFER, len(vertex_buffer), nil, gl.DYNAMIC_DRAW)
	gl.BufferSubData(gl.ARRAY_BUFFER, 0, len(vertex_buffer), raw_data(vertex_buffer))
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
			gl_set_constants(call.constants_data, gl_shd^)
		}

		if .Textures in changed {
			gl_bind_textures(s, call.textures, gl_shd^)
		}

		// Only the render target and scissor setup need the render target. Skipping the lookup
		// otherwise keeps it out of the common case, where only the texture changed.
		rt: ^GL_Render_Target

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

		gl.DrawArrays(gl.TRIANGLES, i32(call.vertex_offset/call.vertex_size), i32(call.vertex_count))
	}

	gl.Disable(gl.SCISSOR_TEST)
}

gl_set_constants :: proc(
	constants_data: []u8,
	gl_shd: GL_Shader,
) {
	if gl_shd.constant_buffer == 0 {
		return
	}

	gl.BindBuffer(gl.UNIFORM_BUFFER, gl_shd.constant_buffer)
	gl.BufferData(gl.UNIFORM_BUFFER, len(constants_data), raw_data(constants_data), gl.DYNAMIC_DRAW)
	gl.BindBufferBase(gl.UNIFORM_BUFFER, 0, gl_shd.constant_buffer)
}

gl_bind_textures :: proc(s: ^GL_State, textures: []Draw_Call_Texture, gl_shd: GL_Shader) {
	if len(textures) != len(gl_shd.texture_bindings) {
		return
	}

	for t, t_idx in textures {
		gl_t := gl_shd.texture_bindings[t_idx]
		gl.ActiveTexture(gl.TEXTURE0 + u32(t_idx))

		gl.BindSampler(u32(t_idx), gl_get_texture_sampler(s, t.sampler))

		if tex := hm.get(&s.textures, t.handle); tex != nil {
			gl.BindTexture(gl.TEXTURE_2D, tex.id)
		} else {
			gl.BindTexture(gl.TEXTURE_2D, 0)
		}

		gl.Uniform1i(gl_t.loc, i32(t_idx))
	}
}

gl_resize_swapchain :: proc(s: ^GL_State, w, h: int) {
	s.width = w
	s.height = h
	gl.Viewport(0, 0, i32(w), i32(h))
	s.glue->viewport_resized()
}

gl_get_swapchain_width :: proc(s: ^GL_State) -> int {
	return s.width
}

gl_get_swapchain_height :: proc(s: ^GL_State) -> int {
	return s.height
}

// GL hands out errors through a queue instead of return values, and nothing else in this backend
// reads it, so it can hold something an earlier call left behind. Empty it, so that a check right
// after a call only sees what that call did. The bound stops a lost context spinning here forever.
GL_ERROR_QUEUE_DRAIN_LIMIT :: 32

gl_drain_errors :: proc() {
	for _ in 0..<GL_ERROR_QUEUE_DRAIN_LIMIT {
		if gl.GetError() == gl.NO_ERROR {
			return
		}
	}
}

_gl_create_texture :: proc(
	width: int,
	height: int,
	format: Pixel_Format,
	internal_format: i32,
	data: [][]u8,
) -> (GL_Texture, bool) {
	id: u32
	gl.GenTextures(1, &id)
	gl.BindTexture(gl.TEXTURE_2D, id)

	gl_drain_errors()

	gl_format := gl_translate_pixel_format(format)
	level_width := width
	level_height := height

	for level_data, level in data {
		level_data_ptr := len(level_data) > 0 ? raw_data(level_data) : nil

		gl.TexImage2D(
			gl.TEXTURE_2D,
			i32(level),
			internal_format,
			i32(level_width),
			i32(level_height),
			0,
			gl_format.format,
			gl_format.type,
			level_data_ptr,
		)

		level_width = max(level_width / 2, 1)
		level_height = max(level_height / 2, 1)
	}

	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAX_LEVEL, i32(len(data) - 1))

	// This is where a texture that is too big for the GPU, or one the GPU has no memory left for,
	// gets caught. Without the check it would become a texture that silently draws nothing.
	if err := gl.GetError(); err != gl.NO_ERROR {
		log.errorf("Failed creating %v x %v texture. GL error: 0x%x", width, height, err)
		gl.DeleteTextures(1, &id)
		return {}, false
	}

	return {
		id = id,
		format = format,
		internal_format = internal_format,
	}, true
}

gl_create_texture :: proc(
	s: ^GL_State,
	width: int,
	height: int,
	format: Pixel_Format,
	mip_levels: int,
) -> (Render_Backend_Texture, bool) {
	@(static, rodata) empty_data: [MAX_MIP_LEVELS][]u8
	gl_tex, gl_tex_ok := _gl_create_texture(
		width,
		height,
		format,
		gl_translate_pixel_format(format).internal_format,
		empty_data[:mip_levels],
	)

	if !gl_tex_ok {
		return {}, false
	}

	tex, tex_add_err := hm.add(&s.textures, gl_tex)

	if tex_add_err != nil {
		log.errorf("Failed to create texture. Error: %v", tex_add_err)
		gl.DeleteTextures(1, &gl_tex.id)
		return {}, false
	}

	return tex, true
}

gl_load_texture :: proc(
	s: ^GL_State,
	data: [][]u8,
	width: int,
	height: int,
	format: Pixel_Format,
) -> (Render_Backend_Texture, bool) {
	gl_tex, gl_tex_ok := _gl_create_texture(
		width,
		height,
		format,
		gl_translate_pixel_format(format).internal_format,
		data,
	)

	if !gl_tex_ok {
		return {}, false
	}

	tex, tex_add_err := hm.add(&s.textures, gl_tex)

	if tex_add_err != nil {
		log.errorf("Failed to load texture. Error: %v", tex_add_err)
		gl.DeleteTextures(1, &gl_tex.id)
		return {}, false
	}

	return tex, true
}

gl_update_texture :: proc(
	s: ^GL_State,
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

	gl_format := gl_translate_pixel_format(tex.format)
	gl.BindTexture(gl.TEXTURE_2D, tex.id)
	gl.PixelStorei(gl.UNPACK_ROW_LENGTH, i32(pitch / pixel_format_size(tex.format)))

	gl.TexSubImage2D(
		gl.TEXTURE_2D,
		i32(mip_level),
		i32(rect.x),
		i32(rect.y),
		i32(rect.w),
		i32(rect.h),
		gl_format.format,
		gl_format.type,
		raw_data(data),
	)

	gl.PixelStorei(gl.UNPACK_ROW_LENGTH, 0)
	return true
}

gl_generate_mipmap :: proc(s: ^GL_State, th: Render_Backend_Texture) -> bool {
	tex := hm.get(&s.textures, th)

	if tex == nil {
		log.errorf("Trying to generate mipmap for texture %v, but it is invalid.", th)
		return false
	}

	gl.BindTexture(gl.TEXTURE_2D, tex.id)
	gl_drain_errors()
	gl.GenerateMipmap(gl.TEXTURE_2D)

	if err := gl.GetError(); err != gl.NO_ERROR {
		log.errorf("Failed generating mipmap. GL error: 0x%x", err)
		return false
	}

	return true
}

gl_destroy_texture :: proc(s: ^GL_State, th: Render_Backend_Texture) {
	tex := hm.get(&s.textures, th)

	if tex == nil {
		return
	}

	gl.DeleteTextures(1, &tex.id)
	hm.remove(&s.textures, th)
}

gl_create_render_texture :: proc(
	s: ^GL_State,
	width: int,
	height: int,
	mip_levels: int,
) -> (Render_Backend_Texture, Render_Target_Handle, bool) {
	@(static, rodata) empty_data: [MAX_MIP_LEVELS][]u8
	if s.render_texture_internal_format == 0 {
		log.error("Can't create render texture: This GPU can't render to float textures.")
		return {}, {}, false
	}

	texture, texture_ok := _gl_create_texture(
		width,
		height,
		.RGBA_32_Float,
		s.render_texture_internal_format,
		empty_data[:mip_levels],
	)

	if !texture_ok {
		return {}, {}, false
	}

	framebuffer: u32
	gl.GenFramebuffers(1, &framebuffer)
	gl.BindFramebuffer(gl.FRAMEBUFFER, framebuffer)

	gl.FramebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, texture.id, 0)
	draw_buffers := u32(gl.COLOR_ATTACHMENT0)
	gl.DrawBuffers(1, &draw_buffers)

	depth_renderbuffer: u32

	if s.depth_test {
		gl.GenRenderbuffers(1, &depth_renderbuffer)
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
		gl.DeleteTextures(1, &texture.id)
		gl.DeleteFramebuffers(1, &framebuffer)

		if s.depth_test {
			gl.DeleteRenderbuffers(1, &depth_renderbuffer)
		}

		return {}, {}, false
	}

	gl.BindFramebuffer(gl.FRAMEBUFFER, 0)
	gl.BindRenderbuffer(gl.RENDERBUFFER, 0)

	rt := GL_Render_Target {
		framebuffer = framebuffer,
		width = width,
		height = height,
		depth_renderbuffer = depth_renderbuffer,
	}

	tex_handle, tex_add_err := hm.add(&s.textures, texture)

	if tex_add_err != nil {
		log.errorf("Failed to create texture. Error: %v", tex_add_err)
		gl.DeleteTextures(1, &texture.id)
		gl.DeleteFramebuffers(1, &framebuffer)

		if s.depth_test {
			gl.DeleteRenderbuffers(1, &depth_renderbuffer)
		}

		return {}, {}, false
	}

	rt_handle, rt_add_err := hm.add(&s.render_targets, rt)
	if rt_add_err != nil {
		log.errorf("Failed to create render target. Error: %v", rt_add_err)
		hm.remove(&s.textures, tex_handle)
		gl.DeleteTextures(1, &texture.id)
		gl.DeleteFramebuffers(1, &framebuffer)

		if s.depth_test {
			gl.DeleteRenderbuffers(1, &depth_renderbuffer)
		}

		return {}, {}, false
	}

	return tex_handle, rt_handle, true
}

gl_destroy_render_target :: proc(s: ^GL_State, render_target: Render_Target_Handle) {
	if rt := hm.get(&s.render_targets, render_target); rt != nil {
		gl.DeleteFramebuffers(1, &rt.framebuffer)

		if rt.depth_renderbuffer != 0 {
			gl.DeleteRenderbuffers(1, &rt.depth_renderbuffer)
		}
	}
}

gl_get_texture_sampler :: proc(s: ^GL_State, sampler: Texture_Sampler) -> u32 {
	if smp, has_smp := s.texture_samplers[sampler]; has_smp {
		return smp
	}

	wrap_x := sampler.wrap_x
	wrap_y := sampler.wrap_y

	if !s.border_wrap_supported {
		if (wrap_x == .Border || wrap_y == .Border) && !s.border_wrap_warning_shown {
			log.warn("This GPU does not support the Border texture wrap mode. Using Clamp instead.")
			s.border_wrap_warning_shown = true
		}

		if wrap_x == .Border {
			wrap_x = .Clamp
		}

		if wrap_y == .Border {
			wrap_y = .Clamp
		}
	}

	smp: u32
	gl.GenSamplers(1, &smp)

	min_filter: i32

	switch sampler.scale_down_filter {
	case .Point: min_filter = sampler.mip_filter == .Point ? gl.NEAREST_MIPMAP_NEAREST : gl.NEAREST_MIPMAP_LINEAR
	case .Linear: min_filter = sampler.mip_filter == .Point ? gl.LINEAR_MIPMAP_NEAREST : gl.LINEAR_MIPMAP_LINEAR
	}

	mag_filter: i32 = sampler.scale_up_filter == .Point ? gl.NEAREST : gl.LINEAR

	wrap_border_color: [4]f32

	switch sampler.wrap_border_color {
	case .Transparent_Black: wrap_border_color = { 0, 0, 0, 0 }
	case .Black: wrap_border_color = { 0, 0, 0, 1 }
	case .White: wrap_border_color = { 1, 1, 1, 1 }
	}

	gl.SamplerParameteri(smp, gl.TEXTURE_MIN_FILTER, min_filter)
	gl.SamplerParameteri(smp, gl.TEXTURE_MAG_FILTER, mag_filter)

	gl_translate_texture_wrap :: proc(wrap: Texture_Wrap) -> i32 {
		switch wrap {
		case .Clamp: return gl.CLAMP_TO_EDGE
		case .Repeat: return gl.REPEAT
		case .Mirrored_Repeat: return gl.MIRRORED_REPEAT
		case .Border: return gl.CLAMP_TO_BORDER
		}

		return gl.CLAMP_TO_EDGE
	}

	gl.SamplerParameteri(smp, gl.TEXTURE_WRAP_S, gl_translate_texture_wrap(wrap_x))
	gl.SamplerParameteri(smp, gl.TEXTURE_WRAP_T, gl_translate_texture_wrap(wrap_y))

	if s.border_wrap_supported {
		gl.SamplerParameterfv(smp, gl.TEXTURE_BORDER_COLOR, &wrap_border_color[0])
	}

	s.texture_samplers[sampler] = smp
	return smp
}

gl_compile_shader_from_source :: proc(shader_data: []byte, shader_type: gl.Shader_Type, err_buf: []u8, err_msg: ^string) -> (shader_id: u32, ok: bool) {
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

gl_link_shader :: proc(vs_shader: u32, fs_shader: u32, err_buf: []u8, err_msg: ^string) -> (program_id: u32, ok: bool) {
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

gl_load_shader :: proc(
	s: ^GL_State,
	compiled: sc.Compiled_Shader,
	inputs: []Shader_Input,
) -> (
	_handle: Shader_Handle,
	_ok: bool,
) {
	code := compiled.code[GL_SHADER_TARGET]

	@static err: [1024]u8
	err_msg: string
	vs_shader, vs_shader_ok := gl_compile_shader_from_source(code.vertex, gl.Shader_Type.VERTEX_SHADER, err[:], &err_msg)

	if !vs_shader_ok  {
		log.errorf("Vertex shader failed to compile: %s", err_msg)
		return
	}
	
	fs_shader, fs_shader_ok := gl_compile_shader_from_source(code.fragment, gl.Shader_Type.FRAGMENT_SHADER, err[:], &err_msg)

	if !fs_shader_ok {
		log.errorf("Fragment shader failed to compile: %s", err_msg)
		gl.DeleteShader(vs_shader)
		return
	}

	program, program_ok := gl_link_shader(vs_shader, fs_shader, err[:], &err_msg)
	gl.DeleteShader(vs_shader)
	gl.DeleteShader(fs_shader)

	if !program_ok {
		log.errorf("Shader failed to link: %s", err_msg)
		return
	}

	stride: int

	for input in inputs {
		stride += pixel_format_size(input.format)
	}

	gl_shd := GL_Shader {
		program = program,
	}

	gl.BindBuffer(gl.ARRAY_BUFFER, s.vertex_buffer_gpu)
	gl.GenVertexArrays(1, &gl_shd.vao)
	gl.BindVertexArray(gl_shd.vao)

	translate_attrib_format :: proc(f: Pixel_Format) -> (type: u32, components: i32, norm: bool) {
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

		log.errorf("Unknown format %v", f)
		return 0, 0, false
	}

	offset: int
	for input in inputs {
		format_size := pixel_format_size(input.format)
		gl.EnableVertexAttribArray(u32(input.register))
		attrib_type, attrib_components, attrib_norm := translate_attrib_format(input.format)

		gl.VertexAttribPointer(
			u32(input.register),
			attrib_components,
			attrib_type,
			attrib_norm ? gl.TRUE : gl.FALSE,
			i32(stride),
			uintptr(offset),
		)
		offset += format_size
	}

	gl.BindBuffer(gl.ARRAY_BUFFER, 0)

	if compiled.constants_size > 0 {
		block_index := gl.GetUniformBlockIndex(program, sc.CONSTANTS_BLOCK_NAME)

		if block_index != gl.INVALID_INDEX {
			gl.UniformBlockBinding(program, block_index, 0)
			gl.GenBuffers(1, &gl_shd.constant_buffer)
			gl.BindBuffer(gl.UNIFORM_BUFFER, gl_shd.constant_buffer)
			gl.BufferData(gl.UNIFORM_BUFFER, compiled.constants_size, nil, gl.DYNAMIC_DRAW)
			gl.BindBuffer(gl.UNIFORM_BUFFER, 0)
		}
	}

	gl_shd.texture_bindings = make([]GL_Texture_Binding, compiled.num_textures, s.allocator)

	for &binding, binding_idx in gl_shd.texture_bindings {
		name := sc.compiled_shader_texture(compiled, binding_idx).name
		binding.loc = gl.GetUniformLocation(program, strings.clone_to_cstring(name, frame_allocator))
	}

	shader_handle, shader_add_err := hm.add(&s.shaders, gl_shd)
	if shader_add_err != nil {
		log.errorf("Failed to add shader. Error: %v", shader_add_err)
		return
	}

	return shader_handle, true
}

gl_translate_pixel_format :: proc(f: Pixel_Format) -> GL_Pixel_Format {
	switch f {
	case .RGBA_32_Float: return { gl.RGBA32F, gl.RGBA, gl.FLOAT }
	case .RGB_32_Float: return { gl.RGB32F, gl.RGB, gl.FLOAT }
	case .RG_32_Float: return { gl.RG32F, gl.RG, gl.FLOAT }
	case .R_32_Float: return { gl.R32F, gl.RED, gl.FLOAT }

	case .RGBA_8_Norm: return { gl.RGBA8, gl.RGBA, gl.UNSIGNED_BYTE }
	case .RG_8_Norm: return { gl.RG8, gl.RG, gl.UNSIGNED_BYTE }
	case .R_8_Norm: return { gl.R8, gl.RED, gl.UNSIGNED_BYTE }
	case .R_8_UInt: return { gl.R8UI, gl.RED_INTEGER, gl.UNSIGNED_BYTE }

	case .Unknown: fallthrough
	case: log.error("Unhandled pixel format %v", f)
	}

	return {}
}

gl_destroy_shader :: proc(s: ^GL_State, h: Shader_Handle) {
	shd := hm.get(&s.shaders, h)

	if shd == nil {
		log.errorf("Invalid shader: %v", h)
		return
	}

	delete(shd.texture_bindings, s.allocator)
}

gl_read_backbuffer :: proc(s: ^GL_State, pixels: []u8) -> bool {
	row_size := s.width * 4

	if len(pixels) != row_size * s.height {
		return false
	}

	gl.BindFramebuffer(gl.FRAMEBUFFER, 0)
	gl.Finish()
	gl.ReadPixels(0, 0, i32(s.width), i32(s.height), gl.RGBA, gl.UNSIGNED_BYTE, raw_data(pixels))
	row := make([]u8, row_size, frame_allocator)

	for y in 0..<s.height / 2 {
		top := pixels[y * row_size:(y + 1) * row_size]
		bottom := pixels[(s.height - 1 - y) * row_size:(s.height - y) * row_size]
		copy(row, top)
		copy(top, bottom)
		copy(bottom, row)
	}

	return true
}

gl_get_depth_clip_range :: proc() -> (min: f32, max: f32) {
	return -1, 1
}
