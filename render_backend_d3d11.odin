#+build windows
#+vet explicit-allocators
#+private package
package karl2d

import d3d11 "vendor:directx/d3d11"
import dxgi "vendor:directx/dxgi"
import sc "shader_compiler"
import "core:strings"
import "log"
import "core:slice"
import "core:mem"
import hm "core:container/handle_map"
import "base:runtime"

RENDER_BACKEND_D3D11 :: Render_Backend_Interface {
	state_type = D3D11_State,
	init = d3d11_init,
	shutdown = d3d11_shutdown,
	clear = d3d11_clear,
	present = d3d11_present,
	set_vsync = d3d11_set_vsync,
	draw = d3d11_draw,
	resize_swapchain = d3d11_resize_swapchain,
	get_swapchain_width = d3d11_get_swapchain_width,
	get_swapchain_height = d3d11_get_swapchain_height,
	create_texture = d3d11_create_texture,
	load_texture = d3d11_load_texture,
	update_texture = d3d11_update_texture,
	generate_mipmap = d3d11_generate_mipmap,
	destroy_texture = d3d11_destroy_texture,
	flip_render_textures = false,
	create_render_texture = d3d11_create_render_texture,
	destroy_render_target = d3d11_destroy_render_target,
	shader_target = .DXBC,
	load_shader = d3d11_load_shader,
	destroy_shader = d3d11_destroy_shader,
	read_backbuffer = d3d11_read_backbuffer,
	get_depth_clip_range = d3d11_get_depth_clip_range,
}

d3d11_init :: proc(
	s: ^D3D11_State,
	glue: ^Window_Render_Glue,
	swapchain_width: int,
	swapchain_height: int,
	options: Init_Options,
	allocator := context.allocator,
) {
	s.allocator = allocator

	hm.dynamic_init(&s.shaders, allocator)
	hm.dynamic_init(&s.textures, allocator)
	hm.dynamic_init(&s.render_targets, allocator)
	s.texture_samplers = make(map[Texture_Sampler]^d3d11.ISamplerState, allocator)

	/*
	This comes from
	
	s.window_render_glue = (^Window_Render_Glue)(s.hwnd)	

	in `platform_windows.odin`
	*/
	s.window_handle = dxgi.HWND(glue)
	
	s.width = swapchain_width
	s.height = swapchain_height
	feature_levels := [?]d3d11.FEATURE_LEVEL{
		._11_1,
		._11_0,
	}
	
	base_device: ^d3d11.IDevice
	base_device_context: ^d3d11.IDeviceContext

	base_device_flags := d3d11.CREATE_DEVICE_FLAGS {
		.BGRA_SUPPORT,
	}

	err: d3d11.HRESULT

	when ODIN_DEBUG {
		device_flags := base_device_flags + { .DEBUG }
	
		err = d3d11.CreateDevice(
			nil,
			.HARDWARE,
			nil,
			device_flags,
			&feature_levels[0],
			len(feature_levels),
			d3d11.SDK_VERSION,
			&base_device,
			nil,
			&base_device_context,
		)

		d3d11_check(s, err)

		if u32(err) == 0x887a002d {
			log.error("You're running in debug mode. So we are trying to create a debug D3D11 device. But you don't have DirectX SDK installed, so we can't enable debug layers. Creating a device without debug layers (you'll get no good D3D11 errors).")

			err = d3d11.CreateDevice(
				nil,
				.HARDWARE,
				nil,
				base_device_flags,
				&feature_levels[0],
				len(feature_levels),
				d3d11.SDK_VERSION,
				&base_device,
				nil,
				&base_device_context,
			)

			d3d11_check(s, err)
		} else {
			err = base_device->QueryInterface(d3d11.IInfoQueue_UUID, (^rawptr)(&s.info_queue))
			d3d11_check(s, err)
		}
	} else {
		err = d3d11.CreateDevice(
			nil,
			.HARDWARE,
			nil,
			base_device_flags,
			&feature_levels[0],
			len(feature_levels),
			d3d11.SDK_VERSION,
			&base_device,
			nil,
			&base_device_context,
		)

		d3d11_check(s, err)
	}
	
	err = base_device->QueryInterface(d3d11.IDevice_UUID, (^rawptr)(&s.device))
	d3d11_check(s, err)
	err = base_device_context->QueryInterface(
		d3d11.IDeviceContext_UUID,
		(^rawptr)(&s.device_context),
	)

	d3d11_check(s, err)
	dxgi_device: ^dxgi.IDevice
	err = s.device->QueryInterface(dxgi.IDevice_UUID, (^rawptr)(&dxgi_device))
	d3d11_check(s, err)
	base_device->Release()
	base_device_context->Release()
	
	err = dxgi_device->GetAdapter(&s.dxgi_adapter)
	d3d11_check(s, err)
	s.anti_alias = options.anti_alias
	s.vsync = !options.disable_vsync
	s.depth_test = options.depth_test

	d3d11_create_swapchain(s, swapchain_width, swapchain_height)

	rasterizer_desc := d3d11.RASTERIZER_DESC{
		FillMode = .SOLID,
		CullMode = .NONE,
		ScissorEnable = true,
		MultisampleEnable = d3d11.BOOL(options.anti_alias),
	}

	err = s.device->CreateRasterizerState(&rasterizer_desc, &s.rasterizer_state)
	d3d11_check(s, err)

	if s.depth_test {
		// Higher z ends up in front. GREATER_EQUAL instead of GREATER so that things drawn at the
		// same z fall back to drawing order, like when depth testing is off.
		depth_stencil_desc := d3d11.DEPTH_STENCIL_DESC{
			DepthEnable    = true,
			DepthWriteMask = .ALL,
			DepthFunc      = .GREATER_EQUAL,
		}
		err = s.device->CreateDepthStencilState(&depth_stencil_desc, &s.depth_stencil_state)
		d3d11_check(s, err)
	}

	vertex_buffer_desc := d3d11.BUFFER_DESC{
		ByteWidth = VERTEX_BUFFER_MAX,
		Usage     = .DYNAMIC,
		BindFlags = {.VERTEX_BUFFER},
		CPUAccessFlags = {.WRITE},
	}
	err = s.device->CreateBuffer(&vertex_buffer_desc, nil, &s.vertex_buffer_gpu)
	d3d11_check(s, err)
	
	blend_alpha_desc := d3d11.BLEND_DESC {
		RenderTarget = {
			0 = {
				BlendEnable = true,
				SrcBlend = .SRC_ALPHA,
				DestBlend = .INV_SRC_ALPHA,
				BlendOp = .ADD,
				SrcBlendAlpha = .SRC_ALPHA,
				DestBlendAlpha = .INV_SRC_ALPHA,
				BlendOpAlpha = .ADD,
				RenderTargetWriteMask = u8(d3d11.COLOR_WRITE_ENABLE_ALL),
			},
		},
	}

	err = s.device->CreateBlendState(&blend_alpha_desc, &s.blend_state_alpha)
	d3d11_check(s, err)

	blend_premultiplied_alpha_desc := d3d11.BLEND_DESC {
		RenderTarget = {
			0 = {
				BlendEnable = true,
				SrcBlend = .ONE,
				DestBlend = .INV_SRC_ALPHA,
				BlendOp = .ADD,
				SrcBlendAlpha = .ONE,
				DestBlendAlpha = .INV_SRC_ALPHA,
				BlendOpAlpha = .ADD,
				RenderTargetWriteMask = u8(d3d11.COLOR_WRITE_ENABLE_ALL),
			},
		},
	}

	err = s.device->CreateBlendState(
		&blend_premultiplied_alpha_desc,
		&s.blend_state_premultiplied_alpha,
	)

	d3d11_check(s, err)

	blend_additive_desc := d3d11.BLEND_DESC {
		RenderTarget = {
			0 = {
				BlendEnable = true,
				SrcBlend = .SRC_ALPHA,
				DestBlend = .ONE,
				BlendOp = .ADD,
				SrcBlendAlpha = .SRC_ALPHA,
				DestBlendAlpha = .ONE,
				BlendOpAlpha = .ADD,
				RenderTargetWriteMask = u8(d3d11.COLOR_WRITE_ENABLE_ALL),
			},
		},
	}

	err = s.device->CreateBlendState(&blend_additive_desc, &s.blend_state_additive)
	d3d11_check(s, err)
}

d3d11_shutdown :: proc(s: ^D3D11_State) {
	s.framebuffer_view->Release()
	s.framebuffer->Release()
	s.device_context->Release()
	s.vertex_buffer_gpu->Release()
	s.rasterizer_state->Release()
	s.swapchain->Release()
	s.blend_state_alpha->Release()
	s.blend_state_premultiplied_alpha->Release()
	s.blend_state_additive->Release()
	s.dxgi_adapter->Release()

	for _, smp in s.texture_samplers {
		if smp != nil {
			smp->Release()
		}
	}

	delete(s.texture_samplers)

	if s.depth_test {
		s.depth_buffer->Release()
		s.depth_buffer_view->Release()
		s.depth_stencil_state->Release()
	}

	when ODIN_DEBUG {
		d3d11_debug_print_live_objects(s)
		s.device->Release()

		if s.info_queue != nil {
			s.info_queue->Release()
		}
	} else {
		s.device->Release()
	}

	hm.dynamic_destroy(&s.shaders)
	hm.dynamic_destroy(&s.textures)
	hm.dynamic_destroy(&s.render_targets)
}

// For finding D3D11 resource leaks etc
d3d11_debug_print_live_objects :: proc(s: ^D3D11_State) {
	debug: ^d3d11.IDebug

	if s.info_queue == nil {
		return
	}

	err := s.device->QueryInterface(d3d11.IDebug_UUID, (^rawptr)(&debug))
	d3d11_check(s, err)

	if err >= 0 {
		live_objs_res := debug->ReportLiveDeviceObjects({.DETAIL, .IGNORE_INTERNAL})

		if live_objs_res >= 0 {
			iq := s.info_queue
			n := iq->GetNumStoredMessages()

			longest_msg: d3d11.SIZE_T

			for i in 0..=n {
				msglen: d3d11.SIZE_T
				iq->GetMessage(i, nil, &msglen)

				if msglen > longest_msg {
					longest_msg = msglen
				}
			}

			if longest_msg > 0 {
				msg_raw_ptr, _ := (mem.alloc(int(longest_msg), allocator = frame_allocator))
				printed_header: bool

				for i in 0..=n {
					msglen: d3d11.SIZE_T
					iq->GetMessage(i, nil, &msglen)

					if msglen > 0 {
						msg := (^d3d11.MESSAGE)(msg_raw_ptr)
						iq->GetMessage(i, msg, &msglen)
						msg_str := string(msg.pDescription)

						// I can't figure out how to not make the report include the device, since
						// the info_queue and debug interface depends on it. So I skip that message.
						if !strings.contains(msg_str, "Live ID3D11Device at") {
							if !printed_header {
								log.error("D3D11 objects leaked:")
								printed_header = true
							}

							log.error(msg_str)
						}
					}
				}
			}

			iq->ClearStoredMessages()
		}

		debug->Release()
	}
}

d3d11_clear :: proc(s: ^D3D11_State, render_target: Render_Target_Handle, color: Color) {
	c := f32_color_from_color(color)

	if rt := hm.get(&s.render_targets, render_target); rt != nil {
		s.device_context->ClearRenderTargetView(rt.render_target_view, &c)

		if s.depth_test {
			s.device_context->ClearDepthStencilView(rt.depth_buffer_view, {.DEPTH}, 0, 0)
		}
	} else {
		s.device_context->ClearRenderTargetView(s.framebuffer_view, &c)

		if s.depth_test {
			s.device_context->ClearDepthStencilView(s.depth_buffer_view, {.DEPTH}, 0, 0)
		}
	}
}

d3d11_present :: proc(s: ^D3D11_State) {
	err := s.swapchain->Present(s.vsync ? 1 : 0, {})
	d3d11_check(s, err)
}

d3d11_set_vsync :: proc(s: ^D3D11_State, enabled: bool) {
	s.vsync = enabled
}

d3d11_draw :: proc(s: ^D3D11_State, vertex_buffer: []u8, draw_calls: []Draw_Call) {
	if len(vertex_buffer) == 0 || len(draw_calls) == 0 {
		return
	}

	dc := s.device_context

	// All the draw calls read from this one buffer. It only needs uploading once.
	vb_data: d3d11.MAPPED_SUBRESOURCE
	err := dc->Map(s.vertex_buffer_gpu, 0, .WRITE_DISCARD, {}, &vb_data)
	d3d11_check(s, err)
	{
		gpu_map := slice.from_ptr((^u8)(vb_data.pData), VERTEX_BUFFER_MAX)
		copy(gpu_map, vertex_buffer)
	}
	dc->Unmap(s.vertex_buffer_gpu, 0)

	dc->IASetPrimitiveTopology(.TRIANGLELIST)
	dc->RSSetState(s.rasterizer_state)

	// Never changes for the lifetime of the backend, so it only needs setting once here rather than
	// per draw call.
	if s.depth_test {
		dc->OMSetDepthStencilState(s.depth_stencil_state, 0)
	}

	// Changes that belong to draw calls we could not draw. They never reached the device context.
	// The next draw call we do run has to make them.
	missed: bit_set[Draw_Call_Change]

	for &call in draw_calls {
		changed := call.changed + missed
		d3d_shd := hm.get(&s.shaders, call.shader)

		if d3d_shd == nil {
			log.errorf("Trying to draw with invalid shader %v", call.shader)
			missed = changed
			continue
		}

		missed = {}

		if .Shader in changed {
			dc->IASetInputLayout(d3d_shd.input_layout)
			vertex_buffer_offset: u32
			vertex_buffer_stride := u32(call.vertex_size)

			dc->IASetVertexBuffers(
				0, 1,
				&s.vertex_buffer_gpu,
				&vertex_buffer_stride,
				&vertex_buffer_offset,
			)

			dc->VSSetShader(d3d_shd.vertex_shader, nil, 0)
			dc->PSSetShader(d3d_shd.pixel_shader, nil, 0)
		}

		if .Constants in changed {
			d3d11_set_constants(s, call.constants_data, d3d_shd)
		}

		if .Textures in changed {
			if len(call.textures) == d3d_shd.num_textures {
				for t, t_idx in call.textures {
					if tex := hm.get(&s.textures, t.handle); tex != nil {
						smp := d3d11_get_texture_sampler(s, t.sampler)
						dc->PSSetShaderResources(u32(t_idx), 1, &tex.view)
						dc->PSSetSamplers(u32(t_idx), 1, &smp)

						if t_idx in d3d_shd.vertex_textures {
							dc->VSSetShaderResources(u32(t_idx), 1, &tex.view)
							dc->VSSetSamplers(u32(t_idx), 1, &smp)
						}
					}
				}
			}
		}

		// Only the render target and scissor setup need the render target. Skipping the lookup
		// otherwise keeps it out of the common case, where only the texture changed.
		rt: ^D3D11_Render_Target

		if .Render_Target in changed || .Scissor in changed {
			rt = hm.get(&s.render_targets, call.render_target)
		}

		if .Render_Target in changed {
			if rt != nil {
				dc->OMSetRenderTargets(1, &rt.render_target_view, s.depth_test ? rt.depth_buffer_view : nil)

				viewport := d3d11.VIEWPORT {
					0, 0,
					f32(rt.width), f32(rt.height),
					0, 1,
				}

				dc->RSSetViewports(1, &viewport)
			} else {
				dc->OMSetRenderTargets(1, &s.framebuffer_view, s.depth_test ? s.depth_buffer_view : nil)

				viewport := d3d11.VIEWPORT {
					0, 0,
					f32(s.width), f32(s.height),
					0, 1,
				}

				dc->RSSetViewports(1, &viewport)
			}
		}

		if .Scissor in changed {
			scissor_rect := d3d11.RECT {
				right = i32(s.width),
				bottom = i32(s.height),
			}

			if rt != nil {
				scissor_rect.right = i32(rt.width)
				scissor_rect.bottom = i32(rt.height)
			}

			if sciss, sciss_ok := call.scissor.?; sciss_ok {
				scissor_rect = d3d11.RECT {
					left = i32(sciss.x),
					top = i32(sciss.y),
					right = i32(sciss.x + sciss.w),
					bottom = i32(sciss.y + sciss.h),
				}
			}

			dc->RSSetScissorRects(1, &scissor_rect)
		}

		if .Blend_Mode in changed {
			switch call.blend_mode {
			case .Alpha:
				dc->OMSetBlendState(s.blend_state_alpha, nil, ~u32(0))
			case .Premultiplied_Alpha:
				dc->OMSetBlendState(s.blend_state_premultiplied_alpha, nil, ~u32(0))
			case .Additive:
				dc->OMSetBlendState(s.blend_state_additive, nil, ~u32(0))
			}
		}

		dc->Draw(u32(call.vertex_count), u32(call.vertex_offset/call.vertex_size))
	}

	dc->OMSetRenderTargets(0, nil, nil)
	d3d11_log_messages(s)
}

d3d11_set_constants :: proc(
	s: ^D3D11_State,
	constants_data: []u8,
	d3d_shd: ^D3D11_Shader,
) {
	dc := s.device_context

	if d3d_shd.constant_buffer == nil {
		return
	}

	map_data: d3d11.MAPPED_SUBRESOURCE
	err := dc->Map(d3d_shd.constant_buffer, 0, .WRITE_DISCARD, {}, &map_data)

	if !d3d11_check(s, err) {
		return
	}

	mem.copy(map_data.pData, raw_data(constants_data), len(constants_data))
	dc->Unmap(d3d_shd.constant_buffer, 0)
	dc->VSSetConstantBuffers(0, 1, &d3d_shd.constant_buffer)
	dc->PSSetConstantBuffers(0, 1, &d3d_shd.constant_buffer)
}

d3d11_resize_swapchain :: proc(s: ^D3D11_State, w, h: int) {
	s.framebuffer->Release()
	s.framebuffer_view->Release()
	s.swapchain->Release()

	if s.depth_test {
		s.depth_buffer->Release()
		s.depth_buffer_view->Release()
	}

	s.width = w
	s.height = h

	d3d11_create_swapchain(s, w, h)
}

d3d11_get_swapchain_width :: proc(s: ^D3D11_State) -> int {
	return s.width
}

d3d11_get_swapchain_height :: proc(s: ^D3D11_State) -> int {
	return s.height
}

_d3d11_create_texture :: proc(
	s: ^D3D11_State,
	width: int,
	height: int,
	format: Pixel_Format,
	data: [][]u8,
) -> (
	Render_Backend_Texture,
	bool,
) {
	mip_levels := len(data)

	if mip_levels < 1 {
		log.error("Trying to create a texture with zero mip levels")
		return RENDER_BACKEND_TEXTURE_NONE, false
	}

	texture_desc := d3d11.TEXTURE2D_DESC{
		Width      = u32(width),
		Height     = u32(height),
		MipLevels  = u32(mip_levels),
		ArraySize  = 1,
		Format     = dxgi_format_from_pixel_format(format),
		SampleDesc = {Count = 1},
		Usage      = .DEFAULT,
		BindFlags  = {.SHADER_RESOURCE},
	}

	can_generate_mips := false

	if mip_levels > 1 {
		format_support: u32
		s.device->CheckFormatSupport(texture_desc.Format, &format_support)
		required := u32(d3d11.FORMAT_SUPPORT.MIP_AUTOGEN) | u32(d3d11.FORMAT_SUPPORT.RENDER_TARGET)
		can_generate_mips = format_support & required == required

		if can_generate_mips {
			texture_desc.BindFlags += {.RENDER_TARGET}
			texture_desc.MiscFlags = {.GENERATE_MIPS}
		}
	}

	texture: ^d3d11.ITexture2D
	err: d3d11.HRESULT

	has_all_levels := true

	for level_data in data {
		if len(level_data) == 0 {
			has_all_levels = false
		}
	}

	if has_all_levels {
		texture_data: [MAX_MIP_LEVELS]d3d11.SUBRESOURCE_DATA
		level_width := width

		for level_data, level in data {
			texture_data[level] = {
				pSysMem     = raw_data(level_data),
				SysMemPitch = u32(level_width * pixel_format_size(format)),
			}

			level_width = max(level_width / 2, 1)
		}

		err = s.device->CreateTexture2D(&texture_desc, &texture_data[0], &texture)

		if !d3d11_check(s, err) {
			return {}, false
		}
	} else {
		err = s.device->CreateTexture2D(&texture_desc, nil, &texture)

		if !d3d11_check(s, err) {
			return {}, false
		}

		level_width := width

		for level_data, level in data {
			if len(level_data) > 0 {
				row_pitch := u32(level_width * pixel_format_size(format))
				s.device_context->UpdateSubresource(
					texture,
					u32(level),
					nil,
					raw_data(level_data),
					row_pitch,
					0,
				)
			}

			level_width = max(level_width / 2, 1)
		}
	}

	texture_view: ^d3d11.IShaderResourceView

	err = s.device->CreateShaderResourceView(texture, nil, &texture_view)

	if !d3d11_check(s, err) {
		texture->Release()
		return {}, false
	}

	tex := D3D11_Texture {
		tex = texture,
		format = format,
		view = texture_view,
		can_generate_mips = can_generate_mips,
	}

	tex_handle, tex_add_err := hm.add(&s.textures, tex)

	if tex_add_err != nil {
		log.errorf("Failed to add texture. Error: %v", tex_add_err)
		texture_view->Release()
		texture->Release()
		return RENDER_BACKEND_TEXTURE_NONE, false
	}

	return tex_handle, true
}

d3d11_create_texture :: proc(
	s: ^D3D11_State,
	width: int,
	height: int,
	format: Pixel_Format,
	mip_levels: int,
) -> (Render_Backend_Texture, bool) {
	@(static, rodata) empty_data: [MAX_MIP_LEVELS][]u8
	return _d3d11_create_texture(s, width, height, format, empty_data[:mip_levels])
}

d3d11_create_render_texture :: proc(
	s: ^D3D11_State,
	width: int,
	height: int,
	mip_levels: int,
) -> (
	_rt_texture: Render_Backend_Texture,
	_rt: Render_Target_Handle,
	_ok: bool,
) {
	texture_desc := d3d11.TEXTURE2D_DESC{
		Width      = u32(width),
		Height     = u32(height),
		MipLevels  = u32(mip_levels),
		ArraySize  = 1,
		Format     = dxgi_format_from_pixel_format(.RGBA_32_Float),
		SampleDesc = {Count = 1},
		Usage      = .DEFAULT,
		BindFlags  = {.SHADER_RESOURCE, .RENDER_TARGET},
	}

	can_generate_mips := false

	if mip_levels > 1 {
		format_support: u32
		s.device->CheckFormatSupport(texture_desc.Format, &format_support)
		can_generate_mips = format_support & u32(d3d11.FORMAT_SUPPORT.MIP_AUTOGEN) != 0

		if can_generate_mips {
			texture_desc.MiscFlags = {.GENERATE_MIPS}
		}
	}

	texture: ^d3d11.ITexture2D

	err := s.device->CreateTexture2D(&texture_desc, nil, &texture)

	if !d3d11_check(s, err) {
		return
	}

	texture_view: ^d3d11.IShaderResourceView

	err = s.device->CreateShaderResourceView(texture, nil, &texture_view)

	if !d3d11_check(s, err) {
		texture->Release()
		return
	}

	render_target_view_desc := d3d11.RENDER_TARGET_VIEW_DESC {
		Format = texture_desc.Format,
		ViewDimension = .TEXTURE2D,
	}

	render_target_view: ^d3d11.IRenderTargetView

	err = s.device->CreateRenderTargetView(
		texture, &render_target_view_desc, &render_target_view,
	)

	if !d3d11_check(s, err) {
		texture_view->Release()
		texture->Release()
		return
	}

	d3d11_texture := D3D11_Texture {
		tex = texture,
		view = texture_view,
		format = .RGBA_32_Float,
		can_generate_mips = can_generate_mips,
	}

	d3d11_render_target := D3D11_Render_Target {
		render_target_view = render_target_view,
		width = width,
		height = height,
	}

	if s.depth_test {
		depth_buffer_desc := d3d11.TEXTURE2D_DESC{
			Width      = u32(width),
			Height     = u32(height),
			MipLevels  = 1,
			ArraySize  = 1,
			Format     = .D24_UNORM_S8_UINT,
			SampleDesc = {Count = 1},
			Usage      = .DEFAULT,
			BindFlags  = {.DEPTH_STENCIL},
		}

		err = s.device->CreateTexture2D(
			&depth_buffer_desc,
			nil,
			&d3d11_render_target.depth_buffer,
		)

		if !d3d11_check(s, err) {
			render_target_view->Release()
			texture_view->Release()
			texture->Release()
			return
		}

		err = s.device->CreateDepthStencilView(
			d3d11_render_target.depth_buffer,
			nil,
			&d3d11_render_target.depth_buffer_view,
		)

		if !d3d11_check(s, err) {
			d3d11_render_target.depth_buffer->Release()
			render_target_view->Release()
			texture_view->Release()
			texture->Release()
			return
		}
	}

	tex_handle, tex_add_err := hm.add(&s.textures, d3d11_texture)

	if tex_add_err != nil {
		log.errorf("Failed to add texture. Error: %v", tex_add_err)

		if s.depth_test {
			d3d11_render_target.depth_buffer_view->Release()
			d3d11_render_target.depth_buffer->Release()
		}

		render_target_view->Release()
		texture_view->Release()
		texture->Release()
		return
	}

	rt_handle, rt_add_err := hm.add(&s.render_targets, d3d11_render_target)

	if rt_add_err != nil {
		log.errorf("Failed to add render target. Error: %v", rt_add_err)

		if s.depth_test {
			d3d11_render_target.depth_buffer_view->Release()
			d3d11_render_target.depth_buffer->Release()
		}

		render_target_view->Release()
		texture_view->Release()
		texture->Release()
		return
	}

	return tex_handle, rt_handle, true
}

d3d11_destroy_render_target :: proc(s: ^D3D11_State, render_target: Render_Target_Handle) {
	if rt := hm.get(&s.render_targets, render_target); rt != nil {
		rt.render_target_view->Release()

		if s.depth_test {
			rt.depth_buffer->Release()
			rt.depth_buffer_view->Release()
		}
	}

	hm.remove(&s.render_targets, render_target)
}

d3d11_load_texture :: proc(
	s: ^D3D11_State,
	data: [][]u8,
	width: int,
	height: int,
	format: Pixel_Format,
) -> (Render_Backend_Texture, bool) {
	return _d3d11_create_texture(s, width, height, format, data)
}

d3d11_update_texture :: proc(
	s: ^D3D11_State,
	th: Render_Backend_Texture,
	data: []u8,
	rect: Rect,
	pitch: int,
	mip_level: int,
) -> bool {
	tex := hm.get(&s.textures, th)

	if tex == nil || tex.tex == nil {
		log.errorf("Trying to update texture %v with new data, but it is invalid.", th)
		return false
	}

	box := d3d11.BOX {
		left = u32(rect.x),
		top = u32(rect.y),
		bottom = u32(rect.y + rect.h),
		right = u32(rect.x + rect.w),
		back = 1,
		front = 0,
	}

	row_pitch := pitch

	if row_pitch == 0 {
		row_pitch = pixel_format_size(tex.format) * int(rect.w)
	}

	s.device_context->UpdateSubresource(
		tex.tex,
		u32(mip_level),
		&box,
		raw_data(data),
		u32(row_pitch),
		0,
	)

	return true
}

d3d11_generate_mipmap :: proc(s: ^D3D11_State, th: Render_Backend_Texture) -> bool {
	tex := hm.get(&s.textures, th)

	if tex == nil || tex.view == nil {
		log.errorf("Trying to generate mipmap for texture %v, but it is invalid.", th)
		return false
	}

	if !tex.can_generate_mips {
		log.errorf("Pixel format %v does not support generating mipmaps", tex.format)
		return false
	}

	s.device_context->GenerateMips(tex.view)
	return true
}

d3d11_destroy_texture :: proc(s: ^D3D11_State, th: Render_Backend_Texture) {
	if t := hm.get(&s.textures, th); t != nil {
		t.tex->Release()
		t.view->Release()
	}

	hm.remove(&s.textures, th)
}

d3d11_get_texture_sampler :: proc(s: ^D3D11_State, sampler: Texture_Sampler) -> ^d3d11.ISamplerState {
	if smp, has_smp := s.texture_samplers[sampler]; has_smp {
		return smp
	}

	d := sampler.scale_down_filter
	u := sampler.scale_up_filter
	m := sampler.mip_filter
	f: d3d11.FILTER

	if d == .Point && u == .Point && m == .Point {
		f = .MIN_MAG_MIP_POINT
	} else if d == .Linear && u == .Linear && m == .Linear {
		f = .MIN_MAG_MIP_LINEAR
	} else if d == .Point && u == .Point && m == .Linear {
		f = .MIN_MAG_POINT_MIP_LINEAR
	} else if d == .Point && u == .Linear && m == .Linear {
		f = .MIN_POINT_MAG_MIP_LINEAR
	} else if d == .Linear && u == .Linear && m == .Point {
		f = .MIN_MAG_LINEAR_MIP_POINT
	} else if d == .Linear && u == .Point && m == .Point {
		f = .MIN_LINEAR_MAG_MIP_POINT
	} else if d == .Linear && u == .Point && m == .Linear {
		f = .MIN_LINEAR_MAG_POINT_MIP_LINEAR
	} else if d == .Point && u == .Linear && m == .Point {
		f = .MIN_POINT_MAG_LINEAR_MIP_POINT
	}

	d3d11_translate_texture_wrap :: proc(wrap: Texture_Wrap) -> d3d11.TEXTURE_ADDRESS_MODE {
		switch wrap {
		case .Clamp: return .CLAMP
		case .Repeat: return .WRAP
		case .Mirrored_Repeat: return .MIRROR
		case .Border: return .BORDER
		}

		return .CLAMP
	}

	wrap_color: [4]f32
	switch sampler.wrap_border_color {
	case .Transparent_Black: wrap_color = { 0, 0, 0, 0 }
	case .Black: wrap_color = { 0, 0, 0, 1 }
	case .White: wrap_color = { 1, 1, 1, 1 }
	}

	sampler_desc := d3d11.SAMPLER_DESC {
		Filter = f,
		AddressU = d3d11_translate_texture_wrap(sampler.wrap_x),
		AddressV = d3d11_translate_texture_wrap(sampler.wrap_y),
		AddressW = .CLAMP,
		ComparisonFunc = .NEVER,
		BorderColor = wrap_color,
		MaxLOD = d3d11.FLOAT32_MAX,
	}

	smp: ^d3d11.ISamplerState
	err := s.device->CreateSamplerState(&sampler_desc, &smp)

	// We store nil for a failed sampler so that it isn't re-created on each try. That would spam
	// the log etc.
	if !d3d11_check(s, err) {
		s.texture_samplers[sampler] = nil
		return nil
	}

	s.texture_samplers[sampler] = smp
	return smp
}

d3d11_load_shader :: proc(
	s: ^D3D11_State,
	compiled: sc.Compiled_Shader,
	inputs: []Shader_Input,
) -> (
	_handle: Shader_Handle,
	_ok: bool,
) {
	code := compiled.code[.DXBC]
	d3d_shd: D3D11_Shader

	err := s.device->CreateVertexShader(
		raw_data(code.vertex),
		len(code.vertex),
		nil,
		&d3d_shd.vertex_shader,
	)

	if !d3d11_check(s, err) {
		return
	}

	input_layout_desc := make([]d3d11.INPUT_ELEMENT_DESC, len(inputs), frame_allocator)

	for input, idx in inputs {
		input_layout_desc[idx] = {
			SemanticName = sc.DXBC_INPUT_SEMANTIC,
			SemanticIndex = u32(input.register),
			Format = dxgi_format_from_pixel_format(input.format),
			AlignedByteOffset = idx == 0 ? 0 : d3d11.APPEND_ALIGNED_ELEMENT,
			InputSlotClass = .VERTEX_DATA,
		}
	}

	err = s.device->CreateInputLayout(
		raw_data(input_layout_desc),
		u32(len(input_layout_desc)),
		raw_data(code.vertex),
		len(code.vertex),
		&d3d_shd.input_layout,
	)

	if !d3d11_check(s, err) {
		d3d11_release_shader(d3d_shd)
		return
	}

	err = s.device->CreatePixelShader(
		raw_data(code.fragment),
		len(code.fragment),
		nil,
		&d3d_shd.pixel_shader,
	)

	if !d3d11_check(s, err) {
		d3d11_release_shader(d3d_shd)
		return
	}

	if compiled.constants_size > 0 {
		constant_buffer_desc := d3d11.BUFFER_DESC{
			ByteWidth      = u32(compiled.constants_size),
			Usage          = .DYNAMIC,
			BindFlags      = {.CONSTANT_BUFFER},
			CPUAccessFlags = {.WRITE},
		}

		err = s.device->CreateBuffer(&constant_buffer_desc, nil, &d3d_shd.constant_buffer)

		if !d3d11_check(s, err) {
			log.error("Failed creating constant buffer.")
			d3d11_release_shader(d3d_shd)
			return
		}
	}

	d3d_shd.num_textures = compiled.num_textures
	d3d_shd.vertex_textures = compiled.vertex_textures
	h, h_add_err := hm.add(&s.shaders, d3d_shd)

	if h_add_err != nil {
		log.errorf("Failed to add shader. Error: %v", h_add_err)
		d3d11_release_shader(d3d_shd)
		return
	}

	return h, true
}

d3d11_release_shader :: proc(shd: D3D11_Shader) {
	if shd.input_layout != nil {
		shd.input_layout->Release()
	}

	if shd.vertex_shader != nil {
		shd.vertex_shader->Release()
	}

	if shd.pixel_shader != nil {
		shd.pixel_shader->Release()
	}

	if shd.constant_buffer != nil {
		shd.constant_buffer->Release()
	}
}

d3d11_destroy_shader :: proc(s: ^D3D11_State, h: Shader_Handle) {
	shd := hm.get(&s.shaders, h)

	if shd == nil {
		log.errorf("Invalid shader: %v", h)
		return
	}

	d3d11_release_shader(shd^)
	hm.remove(&s.shaders, h)
}

// API END

D3D11_Shader :: struct {
	handle: Shader_Handle,
	vertex_shader: ^d3d11.IVertexShader,
	pixel_shader: ^d3d11.IPixelShader,
	input_layout: ^d3d11.IInputLayout,
	constant_buffer: ^d3d11.IBuffer,
	num_textures: int,
	vertex_textures: bit_set[0..<32; u32],
}

D3D11_State :: struct {
	using _: Render_Backend_State,
	allocator: runtime.Allocator,

	window_handle: dxgi.HWND,
	width: int,
	height: int,

	dxgi_adapter: ^dxgi.IAdapter,
	swapchain: ^dxgi.ISwapChain1,
	framebuffer_view: ^d3d11.IRenderTargetView,
	device_context: ^d3d11.IDeviceContext,
	rasterizer_state: ^d3d11.IRasterizerState,
	device: ^d3d11.IDevice,
	framebuffer: ^d3d11.ITexture2D,
	blend_state_alpha: ^d3d11.IBlendState,
	blend_state_premultiplied_alpha: ^d3d11.IBlendState,
	blend_state_additive: ^d3d11.IBlendState,
	anti_alias: bool,
	vsync: bool,

	textures: hm.Dynamic_Handle_Map(D3D11_Texture, Render_Backend_Texture),
	render_targets: hm.Dynamic_Handle_Map(D3D11_Render_Target, Render_Target_Handle),
	shaders: hm.Dynamic_Handle_Map(D3D11_Shader, Shader_Handle),

	info_queue: ^d3d11.IInfoQueue,
	vertex_buffer_gpu: ^d3d11.IBuffer,

	texture_samplers: map[Texture_Sampler]^d3d11.ISamplerState,

	// The depth things below are only created when `depth_test` is true.
	depth_test: bool,
	depth_buffer: ^d3d11.ITexture2D,
	depth_buffer_view: ^d3d11.IDepthStencilView,
	depth_stencil_state: ^d3d11.IDepthStencilState,
}

d3d11_create_swapchain :: proc(s: ^D3D11_State, w, h: int) {
	sample_count: u32 = 1
	num_sample_quality_levels: u32

	SWAPCHAIN_FORMAT :: dxgi.FORMAT.B8G8R8A8_UNORM

	if s.anti_alias {
		check_multisample_res := s.device->CheckMultisampleQualityLevels(SWAPCHAIN_FORMAT, 4, &num_sample_quality_levels)

		if check_multisample_res >= 0 {
			sample_count = 4
		}
	}

	swapchain_desc := dxgi.SWAP_CHAIN_DESC1 {
		Width = u32(w),
		Height = u32(h),
		Format = SWAPCHAIN_FORMAT,
		SampleDesc = {
			Count = sample_count,
			Quality = num_sample_quality_levels > 0 ? num_sample_quality_levels - 1 : 0,
		},
		BufferUsage = {.RENDER_TARGET_OUTPUT},
		BufferCount = 2,
		Scaling     = .STRETCH,
		SwapEffect  = .DISCARD,
	}

	dxgi_factory: ^dxgi.IFactory2
	err := s.dxgi_adapter->GetParent(dxgi.IFactory2_UUID, (^rawptr)(&dxgi_factory))
	d3d11_check(s, err)
	err = dxgi_factory->CreateSwapChainForHwnd(
		s.device,
		s.window_handle,
		&swapchain_desc,
		nil,
		nil,
		&s.swapchain,
	)

	d3d11_check(s, err)
	err = s.swapchain->GetBuffer(0, d3d11.ITexture2D_UUID, (^rawptr)(&s.framebuffer))
	d3d11_check(s, err)
	err = s.device->CreateRenderTargetView(s.framebuffer, nil, &s.framebuffer_view)
	d3d11_check(s, err)
	dxgi_factory->MakeWindowAssociation(s.window_handle, { .NO_ALT_ENTER })

	if s.depth_test {
		depth_buffer_desc := d3d11.TEXTURE2D_DESC{
			Width      = u32(w),
			Height     = u32(h),
			MipLevels  = 1,
			ArraySize  = 1,
			Format     = .D24_UNORM_S8_UINT,
			SampleDesc = {Count = sample_count, Quality = swapchain_desc.SampleDesc.Quality},
			Usage      = .DEFAULT,
			BindFlags  = {.DEPTH_STENCIL},
		}

		err = s.device->CreateTexture2D(&depth_buffer_desc, nil, &s.depth_buffer)
		d3d11_check(s, err)
		err = s.device->CreateDepthStencilView(s.depth_buffer, nil, &s.depth_buffer_view)
		d3d11_check(s, err)
	}
}

D3D11_Texture :: struct {
	handle: Render_Backend_Texture,
	tex: ^d3d11.ITexture2D,
	view: ^d3d11.IShaderResourceView,
	format: Pixel_Format,
	can_generate_mips: bool,
}

D3D11_Render_Target :: struct {
	handle: Render_Target_Handle,
	render_target_view: ^d3d11.IRenderTargetView,
	width: int,
	height: int,

	// Only set up when depth testing is enabled, see D3D11_State.depth_test.
	depth_buffer: ^d3d11.ITexture2D,
	depth_buffer_view: ^d3d11.IDepthStencilView,
}

dxgi_format_from_pixel_format :: proc(f: Pixel_Format) -> dxgi.FORMAT {
	switch f {
	case .Unknown: return .UNKNOWN
	case .RGBA_32_Float: return .R32G32B32A32_FLOAT
	case .RGB_32_Float: return .R32G32B32_FLOAT
	case .RG_32_Float: return .R32G32_FLOAT
	case .R_32_Float: return .R32_FLOAT

	case .RGBA_8_Norm: return .R8G8B8A8_UNORM
	case .RG_8_Norm: return .R8G8_UNORM
	case .R_8_Norm: return .R8_UNORM
	case .R_8_UInt: return .R8_UINT
	}

	log.error("Unknown format")
	return .UNKNOWN
}

// CHeck win errors and print message log if there is any error
d3d11_check :: proc(s: ^D3D11_State, hr: dxgi.HRESULT, loc := #caller_location) -> bool {
	if hr >= 0 {
		return true
	}

	log.errorf("d3d11 error: 0x%0x", u32(hr), location = loc)
	d3d11_log_messages(s, loc)
	return false
}

d3d11_log_messages :: proc(s: ^D3D11_State, loc := #caller_location) {
	iq := s.info_queue
	
	if iq == nil {
		return
	}

	n := iq->GetNumStoredMessages()
	longest_msg: d3d11.SIZE_T

	for i in 0..=n {
		msglen: d3d11.SIZE_T
		iq->GetMessage(i, nil, &msglen)

		if msglen > longest_msg {
			longest_msg = msglen
		}
	}

	if longest_msg > 0 {
		msg_raw_ptr, _ := (mem.alloc(int(longest_msg), allocator = frame_allocator))

		for i in 0..=n {
			msglen: d3d11.SIZE_T
			iq->GetMessage(i, nil, &msglen)

			if msglen > 0 {
				msg := (^d3d11.MESSAGE)(msg_raw_ptr)
				iq->GetMessage(i, msg, &msglen)
				log.error(msg.pDescription, location = loc)
			}
		}
	}

	iq->ClearStoredMessages()
}

d3d11_read_backbuffer :: proc(s: ^D3D11_State, pixels: []u8) -> bool {
	if len(pixels) != s.width * s.height * 4 {
		return false
	}

	backbuffer: ^d3d11.ITexture2D
	err := s.swapchain->GetBuffer(0, d3d11.ITexture2D_UUID, (^rawptr)(&backbuffer))

	if !d3d11_check(s, err) {
		return false
	}

	desc: d3d11.TEXTURE2D_DESC
	backbuffer->GetDesc(&desc)
	bgra := desc.Format == .B8G8R8A8_UNORM || desc.Format == .B8G8R8A8_UNORM_SRGB
	desc.Usage = .STAGING
	desc.BindFlags = {}
	desc.CPUAccessFlags = {.READ}
	desc.MiscFlags = {}
	desc.SampleDesc = { Count = 1 }
	staging: ^d3d11.ITexture2D
	err = s.device->CreateTexture2D(&desc, nil, &staging)

	if !d3d11_check(s, err) {
		backbuffer->Release()
		return false
	}

	s.device_context->CopyResource(staging, backbuffer)
	mapped: d3d11.MAPPED_SUBRESOURCE
	err = s.device_context->Map(staging, 0, .READ, {}, &mapped)

	if !d3d11_check(s, err) {
		staging->Release()
		backbuffer->Release()
		return false
	}

	for y in 0..<s.height {
		src := ([^]u8)(mapped.pData)[y * int(mapped.RowPitch):]
		dst := pixels[y * s.width * 4:]

		for x in 0..<s.width {
			dst[x * 4 + 0] = bgra ? src[x * 4 + 2] : src[x * 4 + 0]
			dst[x * 4 + 1] = src[x * 4 + 1]
			dst[x * 4 + 2] = bgra ? src[x * 4 + 0] : src[x * 4 + 2]
			dst[x * 4 + 3] = src[x * 4 + 3]
		}
	}

	s.device_context->Unmap(staging, 0)
	staging->Release()
	backbuffer->Release()
	return true
}

d3d11_get_depth_clip_range :: proc() -> (min: f32, max: f32) {
	return 0, 1
}