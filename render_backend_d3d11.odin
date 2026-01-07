#+build windows
#+vet explicit-allocators
#+private file

package karl2d

@(private="package")
RENDER_BACKEND_D3D11 :: Render_Backend_Interface {
	state_size = d3d11_state_size,
	init = d3d11_init,
	shutdown = d3d11_shutdown,
	clear = d3d11_clear,
	present = d3d11_present,
	draw = d3d11_draw,
	resize_swapchain = d3d11_resize_swapchain,
	get_swapchain_width = d3d11_get_swapchain_width,
	get_swapchain_height = d3d11_get_swapchain_height,
	depth_start = d3d11_depth_start,
	depth_increment_sign = d3d11_depth_increment_sign,
	set_internal_state = d3d11_set_internal_state,
	create_texture = d3d11_create_texture,
	load_texture = d3d11_load_texture,
	update_texture = d3d11_update_texture,
	destroy_texture = d3d11_destroy_texture,
	texture_needs_vertical_flip = d3d11_texture_needs_vertical_flip,
	create_render_texture = d3d11_create_render_texture,
	destroy_render_target = d3d11_destroy_render_target,
	set_texture_filter = d3d11_set_texture_filter,
	load_shader = d3d11_load_shader,
	destroy_shader = d3d11_destroy_shader,
	default_shader_vertex_source = d3d11_default_shader_vertex_source,
	default_shader_fragment_source = d3d11_default_shader_fragment_source,
}

import d3d11 "vendor:directx/d3d11"
import dxgi "vendor:directx/dxgi"
import "vendor:directx/d3d_compiler"
import "core:strings"
import "log"
import "core:slice"
import "core:mem"
import hm "handle_map"
import "base:runtime"

d3d11_state_size :: proc() -> int {
	return size_of(D3D11_State)
}

d3d11_init :: proc(state: rawptr, window_handle: Window_Handle, swapchain_width, swapchain_height: int, allocator := context.allocator) {
	s = (^D3D11_State)(state)
	s.allocator = allocator
	s.window_handle = dxgi.HWND(window_handle)
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

	when ODIN_DEBUG {
		device_flags := base_device_flags + { .DEBUG }
	
		device_err := ch(d3d11.CreateDevice(
			nil,
			.HARDWARE,
			nil,
			device_flags,
			&feature_levels[0], len(feature_levels),
			d3d11.SDK_VERSION, &base_device, nil, &base_device_context))

		if u32(device_err) == 0x887a002d {
			log.error("You're running in debug mode. So we are trying to create a debug D3D11 device. But you don't have DirectX SDK installed, so we can't enable debug layers. Creating a device without debug layers (you'll get no good D3D11 errors).")

			ch(d3d11.CreateDevice(
				nil,
				.HARDWARE,
				nil,
				base_device_flags,
				&feature_levels[0], len(feature_levels),
				d3d11.SDK_VERSION, &base_device, nil, &base_device_context))
		} else {
			ch(base_device->QueryInterface(d3d11.IInfoQueue_UUID, (^rawptr)(&s.info_queue)))
		}
	} else {
		ch(d3d11.CreateDevice(
			nil,
			.HARDWARE,
			nil,
			base_device_flags,
			&feature_levels[0], len(feature_levels),
			d3d11.SDK_VERSION, &base_device, nil, &base_device_context))
	}
	
	ch(base_device->QueryInterface(d3d11.IDevice_UUID, (^rawptr)(&s.device)))
	ch(base_device_context->QueryInterface(d3d11.IDeviceContext_UUID, (^rawptr)(&s.device_context)))
	dxgi_device: ^dxgi.IDevice
	ch(s.device->QueryInterface(dxgi.IDevice_UUID, (^rawptr)(&dxgi_device)))
	base_device->Release()
	base_device_context->Release()
	
	ch(dxgi_device->GetAdapter(&s.dxgi_adapter))

	create_swapchain(swapchain_width, swapchain_height)

	rasterizer_desc := d3d11.RASTERIZER_DESC{
		FillMode = .SOLID,
		CullMode = .BACK,
		ScissorEnable = true,
	}
	ch(s.device->CreateRasterizerState(&rasterizer_desc, &s.rasterizer_state))

	vertex_buffer_desc := d3d11.BUFFER_DESC{
		ByteWidth = VERTEX_BUFFER_MAX,
		Usage     = .DYNAMIC,
		BindFlags = {.VERTEX_BUFFER},
		CPUAccessFlags = {.WRITE},
	}
	ch(s.device->CreateBuffer(&vertex_buffer_desc, nil, &s.vertex_buffer_gpu))
	
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

	ch(s.device->CreateBlendState(&blend_alpha_desc, &s.blend_state_alpha))

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

	ch(s.device->CreateBlendState(&blend_premultiplied_alpha_desc, &s.blend_state_premultiplied_alpha))
}

d3d11_shutdown :: proc() {
	s.framebuffer_view->Release()
	s.framebuffer->Release()
	s.device_context->Release()
	s.vertex_buffer_gpu->Release()
	s.rasterizer_state->Release()
	s.swapchain->Release()
	s.blend_state_alpha->Release()
	s.blend_state_premultiplied_alpha->Release()
	s.dxgi_adapter->Release()

	when ODIN_DEBUG {
		d3d11_debug_print_live_objects()
		s.device->Release()

		if s.info_queue != nil {
			s.info_queue->Release()
		}
	} else {
		s.device->Release()
	}
}

// For finding D3D11 resource leaks etc
d3d11_debug_print_live_objects :: proc() {
	debug: ^d3d11.IDebug

	if s.info_queue != nil && ch(s.device->QueryInterface(d3d11.IDebug_UUID, (^rawptr)(&debug))) >= 0 {
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
	}

	debug->Release()
}

d3d11_clear :: proc(render_target: Render_Target_Handle, color: Color) {
	c := f32_color_from_color(color)

	if rt := hm.get(&s.render_targets, render_target); rt != nil {
		s.device_context->ClearRenderTargetView(rt.render_target_view, &c)
	} else {
		s.device_context->ClearRenderTargetView(s.framebuffer_view, &c)
	}
}

d3d11_present :: proc() {
	ch(s.swapchain->Present(1, {}))
}

d3d11_draw :: proc(
	shd: Shader,
	render_target: Render_Target_Handle,
	bound_textures: []Texture_Handle,
	scissor: Maybe(Rect), 
	blend_mode: Blend_Mode,
	vertex_buffer: []u8,
) {
	if len(vertex_buffer) == 0 {
		return
	}

	d3d_shd := hm.get(&s.shaders, shd.handle)

	if d3d_shd == nil {
		log.error("Trying to draw with invalid shader %v", shd.handle)
		return
	}

	dc := s.device_context

	vb_data: d3d11.MAPPED_SUBRESOURCE
	ch(dc->Map(s.vertex_buffer_gpu, 0, .WRITE_DISCARD, {}, &vb_data))
	{
		gpu_map := slice.from_ptr((^u8)(vb_data.pData), VERTEX_BUFFER_MAX)
		copy(
			gpu_map,
			vertex_buffer,
		)
	}
	dc->Unmap(s.vertex_buffer_gpu, 0)

	dc->IASetPrimitiveTopology(.TRIANGLELIST)

	dc->IASetInputLayout(d3d_shd.input_layout)
	vertex_buffer_offset: u32
	vertex_buffer_stride := u32(shd.vertex_size)
	dc->IASetVertexBuffers(0, 1, &s.vertex_buffer_gpu, &vertex_buffer_stride, &vertex_buffer_offset)

	dc->VSSetShader(d3d_shd.vertex_shader, nil, 0)

	assert(len(shd.constants) == len(d3d_shd.constants))

	maps := make([]rawptr, len(d3d_shd.constant_buffers), frame_allocator)

	cpu_data := shd.constants_data
	for cidx in 0..<len(shd.constants) {
		cpu_loc := shd.constants[cidx]
		gpu_loc := d3d_shd.constants[cidx]//cpu_loc.gpu_constant_idx]
		gpu_buffer_info := d3d_shd.constant_buffers[gpu_loc.buffer_idx]
		gpu_data := gpu_buffer_info.gpu_data
		
		if gpu_data == nil {
			continue
		}

		if maps[gpu_loc.buffer_idx] == nil {
			// We do this little dance with the 'maps' array so we only have to map the memory once.
			// There can be multiple constants within a single constant buffer. So mapping and
			// unmapping for each one is slow.
			map_data: d3d11.MAPPED_SUBRESOURCE
			ch(dc->Map(gpu_data, 0, .WRITE_DISCARD, {}, &map_data))
			maps[gpu_loc.buffer_idx] = map_data.pData
		}

		data_slice := slice.bytes_from_ptr(maps[gpu_loc.buffer_idx], gpu_buffer_info.size)
		dst := data_slice[gpu_loc.offset:gpu_loc.offset+u32(cpu_loc.size)]
		src := cpu_data[cpu_loc.offset:cpu_loc.offset+cpu_loc.size]
		copy(dst, src)
	}

	for &cb, cb_idx in d3d_shd.constant_buffers {
		if .Vertex in cb.bound_shaders {
			dc->VSSetConstantBuffers(cb.bind_point, 1, &cb.gpu_data)
		}

		if .Pixel in cb.bound_shaders {
			dc->PSSetConstantBuffers(cb.bind_point, 1, &cb.gpu_data)
		}

		if maps[cb_idx] != nil {
			dc->Unmap(cb.gpu_data, 0)
			maps[cb_idx] = nil
		}
	}

	dc->RSSetState(s.rasterizer_state)

	scissor_rect := d3d11.RECT {
		right = i32(s.width),
		bottom = i32(s.height),
	}

	if sciss, sciss_ok := scissor.?; sciss_ok {
		scissor_rect = d3d11.RECT {
			left = i32(sciss.x),
			top = i32(sciss.y),
			right = i32(sciss.x + sciss.w),
			bottom = i32(sciss.y + sciss.h),
		}
	}
	
	dc->RSSetScissorRects(1, &scissor_rect)

	dc->PSSetShader(d3d_shd.pixel_shader, nil, 0)

	if len(bound_textures) == len(d3d_shd.texture_bindings) {
		for t, t_idx in bound_textures {
			d3d_t := d3d_shd.texture_bindings[t_idx]

			if t := hm.get(&s.textures, t); t != nil {
				dc->PSSetShaderResources(d3d_t.bind_point, 1, &t.view)	
				dc->PSSetSamplers(d3d_t.sampler_bind_point, 1, &t.sampler)
			}
		}
	}

	if rt := hm.get(&s.render_targets, render_target); rt != nil {
		dc->OMSetRenderTargets(1, &rt.render_target_view, nil)

		viewport := d3d11.VIEWPORT{
			0, 0,
			f32(rt.width), f32(rt.height),
			0, 1,
		}

		dc->RSSetViewports(1, &viewport)
	} else {
		dc->OMSetRenderTargets(1, &s.framebuffer_view, nil)

		viewport := d3d11.VIEWPORT{
			0, 0,
			f32(s.width), f32(s.height),
			0, 1,
		}

		dc->RSSetViewports(1, &viewport)
	}

	switch blend_mode {
	case .Alpha:
		dc->OMSetBlendState(s.blend_state_alpha, nil, ~u32(0))
	case .Premultiplied_Alpha:
		dc->OMSetBlendState(s.blend_state_premultiplied_alpha, nil, ~u32(0))
	}
	dc->Draw(u32(len(vertex_buffer)/shd.vertex_size), 0)
	dc->OMSetRenderTargets(0, nil, nil)
	log_messages()
}

d3d11_resize_swapchain :: proc(w, h: int) {
	s.framebuffer->Release()
	s.framebuffer_view->Release()
	s.swapchain->Release()
	s.width = w
	s.height = h

	create_swapchain(w, h)
}

d3d11_get_swapchain_width :: proc() -> int {
	return s.width
}

d3d11_get_swapchain_height :: proc() -> int {
	return s.height
}

d3d11_depth_start :: proc() -> f32 {
	return 1
}

d3d11_depth_increment_sign :: proc() -> int {
	return -1
}

d3d11_set_internal_state :: proc(state: rawptr) {
	s = (^D3D11_State)(state)
}

create_texture :: proc(
	width: int,
	height: int,
	format: Pixel_Format,
	data: rawptr,
) -> (
	Texture_Handle,
) {
	texture_desc := d3d11.TEXTURE2D_DESC{
		Width      = u32(width),
		Height     = u32(height),
		MipLevels  = 1,
		ArraySize  = 1,
		Format     = dxgi_format_from_pixel_format(format),
		SampleDesc = {Count = 1},
		Usage      = .DEFAULT,
		BindFlags  = {.SHADER_RESOURCE},
	}

	texture: ^d3d11.ITexture2D

	if data != nil {
		texture_data := d3d11.SUBRESOURCE_DATA{
			pSysMem     = data,
			SysMemPitch = u32(width * pixel_format_size(format)),
		}

		s.device->CreateTexture2D(&texture_desc, &texture_data, &texture)
	} else {
		s.device->CreateTexture2D(&texture_desc, nil, &texture)
	}
	
	texture_view: ^d3d11.IShaderResourceView
	s.device->CreateShaderResourceView(texture, nil, &texture_view)

	tex := D3D11_Texture {
		tex = texture,
		format = format,
		view = texture_view,
		sampler = create_sampler(.MIN_MAG_MIP_POINT),
	}

	return hm.add(&s.textures, tex)
}

d3d11_create_texture :: proc(width: int, height: int, format: Pixel_Format) -> Texture_Handle {
	return create_texture(width, height, format, nil)
}

d3d11_create_render_texture :: proc(width: int, height: int) -> (Texture_Handle, Render_Target_Handle) {
	texture_desc := d3d11.TEXTURE2D_DESC{
		Width      = u32(width),
		Height     = u32(height),
		MipLevels  = 1,
		ArraySize  = 1,
		Format     = dxgi_format_from_pixel_format(.RGBA_32_Float),
		SampleDesc = {Count = 1},
		Usage      = .DEFAULT,
		BindFlags  = {.SHADER_RESOURCE, .RENDER_TARGET},
	}

	texture: ^d3d11.ITexture2D
	ch(s.device->CreateTexture2D(&texture_desc, nil, &texture))

	texture_view: ^d3d11.IShaderResourceView
	ch(s.device->CreateShaderResourceView(texture, nil, &texture_view))

	depth_stencil_desc := d3d11.TEXTURE2D_DESC{
		Width      = u32(width),
		Height     = u32(height),
		MipLevels  = 1,
		ArraySize  = 1,
		Format     = .D24_UNORM_S8_UINT,
		SampleDesc = {Count = 1},
		Usage      = .DEFAULT,
		BindFlags  = {.DEPTH_STENCIL},
	}

	depth_stencil_texture: ^d3d11.ITexture2D
	ch(ch(s.device->CreateTexture2D(&depth_stencil_desc, nil, &depth_stencil_texture)))

	depth_stencil_texture_view: ^d3d11.IDepthStencilView
	ch(s.device->CreateDepthStencilView(depth_stencil_texture, nil, &depth_stencil_texture_view))

	render_target_view_desc := d3d11.RENDER_TARGET_VIEW_DESC {
		Format = texture_desc.Format,
		ViewDimension = .TEXTURE2D,
	}

	render_target_view: ^d3d11.IRenderTargetView

	ch(s.device->CreateRenderTargetView(texture, &render_target_view_desc, &render_target_view))

	d3d11_texture := D3D11_Texture {
		tex = texture,
		view = texture_view,
		format = .RGBA_32_Float,
		sampler = create_sampler(.MIN_MAG_MIP_POINT),
	}

	d3d11_render_target := D3D11_Render_Target {
		render_target_view = render_target_view,
		width = width,
		height = height,
	}

	return hm.add(&s.textures, d3d11_texture), hm.add(&s.render_targets, d3d11_render_target)
}

d3d11_destroy_render_target :: proc(render_target: Render_Target_Handle) {
	if rt := hm.get(&s.render_targets, render_target); rt != nil {
		rt.render_target_view->Release()
	}

	hm.remove(&s.render_targets, render_target)
}

d3d11_load_texture :: proc(data: []u8, width: int, height: int, format: Pixel_Format) -> Texture_Handle {
	return create_texture(width, height, format, raw_data(data))
}

d3d11_update_texture :: proc(th: Texture_Handle, data: []u8, rect: Rect) -> bool {
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

	row_pitch := pixel_format_size(tex.format) * int(rect.w)
	s.device_context->UpdateSubresource(tex.tex, 0, &box, raw_data(data), u32(row_pitch), 0)
	return true
}

d3d11_destroy_texture :: proc(th: Texture_Handle) {
	if t := hm.get(&s.textures, th); t != nil {
		t.tex->Release()
		t.view->Release()	

		if t.sampler != nil {
			t.sampler->Release()
		}
	}

	hm.remove(&s.textures, th)
}

d3d11_texture_needs_vertical_flip :: proc(th: Texture_Handle) -> bool {
	return false
}

d3d11_set_texture_filter :: proc(
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

	d := scale_down_filter
	u := scale_up_filter
	m := mip_filter
	f: d3d11.FILTER

	if d == .Point && u == .Point && m == .Point {
		f = .MIN_MAG_MIP_POINT
	} else if d == .Linear && u == .Linear && m == .Linear {
		f = .MIN_MAG_MIP_LINEAR
	} else if d == .Point && u == .Point && m == .Linear {
		f = .MIN_MAG_POINT_MIP_LINEAR
	} else if d == .Point && u == .Linear && m == .Linear {
		f = .MIN_POINT_MAG_MIP_LINEAR
	} else if d == .Linear && u == .Linear && m == .Linear {
		f = .MIN_MAG_MIP_LINEAR
	} else if d == .Linear && u == .Linear && m == .Point {
		f = .MIN_MAG_LINEAR_MIP_POINT
	} else if d == .Linear && u == .Point && m == .Point {
		f = .MIN_LINEAR_MAG_MIP_POINT
	} else if d == .Linear && u == .Point && m == .Linear {
		f = .MIN_LINEAR_MAG_POINT_MIP_LINEAR
	} else if d == .Point && u == .Linear && m == .Point {
		f = .MIN_POINT_MAG_LINEAR_MIP_POINT
	}

	if t.sampler != nil {
		t.sampler->Release()
	}

	t.sampler = create_sampler(f)
}

create_sampler :: proc(filter: d3d11.FILTER) -> ^d3d11.ISamplerState {
	sampler_desc := d3d11.SAMPLER_DESC{
		Filter = filter,
		AddressU = .WRAP,
		AddressV = .WRAP,
		AddressW = .WRAP,
		ComparisonFunc = .NEVER,
	}

	smp: ^d3d11.ISamplerState
	ch(s.device->CreateSamplerState(&sampler_desc, &smp))
	return smp
}

d3d11_load_shader :: proc(
	vs_source: []byte,
	ps_source: []byte,
	desc_allocator := frame_allocator,
	layout_formats: []Pixel_Format = {},
) -> (
	handle: Shader_Handle,
	desc: Shader_Desc,
) {
	vs_blob: ^d3d11.IBlob
	vs_blob_errors: ^d3d11.IBlob
	ch(d3d_compiler.Compile(raw_data(vs_source), len(vs_source), nil, nil, nil, "vs_main", "vs_5_0", 0, 0, &vs_blob, &vs_blob_errors))

	if vs_blob_errors != nil {
		log.error("Failed compiling shader:")
		log.error(strings.string_from_ptr((^u8)(vs_blob_errors->GetBufferPointer()), int(vs_blob_errors->GetBufferSize())))
		return
	}

	// VERTEX SHADER

	vertex_shader: ^d3d11.IVertexShader
	ch(s.device->CreateVertexShader(vs_blob->GetBufferPointer(), vs_blob->GetBufferSize(), nil, &vertex_shader))

	vs_ref: ^d3d11.IShaderReflection
	ch(d3d_compiler.Reflect(vs_blob->GetBufferPointer(), vs_blob->GetBufferSize(), d3d11.ID3D11ShaderReflection_UUID, (^rawptr)(&vs_ref)))
	
	vs_desc: d3d11.SHADER_DESC
	ch(vs_ref->GetDesc(&vs_desc))

	{
		desc.inputs = make([]Shader_Input, vs_desc.InputParameters, desc_allocator)
		assert(len(layout_formats) == 0 || len(layout_formats) == len(desc.inputs))

		for in_idx in 0..<vs_desc.InputParameters {
			in_desc: d3d11.SIGNATURE_PARAMETER_DESC
			
			if ch(vs_ref->GetInputParameterDesc(in_idx, &in_desc)) < 0 {
				log.errorf("Invalid shader input: %v", in_idx)
				continue
			}

			type: Shader_Input_Type

			if in_desc.SemanticIndex > 0 {
				log.errorf("Matrix shader input types not yet implemented")
				continue
			}

			switch in_desc.ComponentType {
			case .UNKNOWN: log.errorf("Unknown component type")
			case .UINT32: log.errorf("Not implemented")
			case .SINT32: log.errorf("Not implemented")
			case .FLOAT32:
				switch in_desc.Mask {
				case 0: log.errorf("Invalid input mask"); continue
				case 1: type = .F32
				case 3: type = .Vec2
				case 7: type = .Vec3
				case 15: type = .Vec4
				}
			}

			name := strings.clone_from_cstring(in_desc.SemanticName, desc_allocator)

			format := len(layout_formats) > 0 ? layout_formats[in_idx] : get_shader_input_format(name, type)
			desc.inputs[in_idx] = {
				name = name,
				register = int(in_idx),
				format = format,
				type = type,
			}
		}
	}

	constant_descs := make([dynamic]Shader_Constant_Desc, desc_allocator)
	d3d_constants := make([dynamic]D3D11_Shader_Constant, s.allocator)
	d3d_constant_buffers := make([dynamic]D3D11_Shader_Constant_Buffer, s.allocator)
	d3d_texture_bindings := make([dynamic]D3D11_Texture_Binding, s.allocator)
	texture_bindpoint_descs := make([dynamic]Shader_Texture_Bindpoint_Desc, desc_allocator)
	reflect_shader_constants(
		vs_desc,
		vs_ref,
		&constant_descs,
		&d3d_constants,
		&d3d_constant_buffers,
		&d3d_texture_bindings,
		&texture_bindpoint_descs,
		desc_allocator,
		.Vertex,
	)

	input_layout_desc := make([]d3d11.INPUT_ELEMENT_DESC, len(desc.inputs), frame_allocator)

	for idx in 0..<len(desc.inputs) {
		input := desc.inputs[idx]
		input_layout_desc[idx] = {
			SemanticName = frame_cstring(input.name),
			Format = dxgi_format_from_pixel_format(input.format),
			AlignedByteOffset = idx == 0 ? 0 : d3d11.APPEND_ALIGNED_ELEMENT,
			InputSlotClass = .VERTEX_DATA,
		}
	}

	input_layout: ^d3d11.IInputLayout
	ch(s.device->CreateInputLayout(raw_data(input_layout_desc), u32(len(input_layout_desc)), vs_blob->GetBufferPointer(), vs_blob->GetBufferSize(), &input_layout))

	// PIXEL SHADER

	ps_blob: ^d3d11.IBlob
	ps_blob_errors: ^d3d11.IBlob
	ch(d3d_compiler.Compile(raw_data(ps_source), len(ps_source), nil, nil, nil, "ps_main", "ps_5_0", 0, 0, &ps_blob, &ps_blob_errors))

	if ps_blob_errors != nil {
		log.error("Failed compiling shader:")
		log.error(strings.string_from_ptr((^u8)(ps_blob_errors->GetBufferPointer()), int(ps_blob_errors->GetBufferSize())))
		return
	}

	pixel_shader: ^d3d11.IPixelShader
	ch(s.device->CreatePixelShader(ps_blob->GetBufferPointer(), ps_blob->GetBufferSize(), nil, &pixel_shader))

	ps_ref: ^d3d11.IShaderReflection
	ch(d3d_compiler.Reflect(ps_blob->GetBufferPointer(), ps_blob->GetBufferSize(), d3d11.ID3D11ShaderReflection_UUID, (^rawptr)(&ps_ref)))
	
	ps_desc: d3d11.SHADER_DESC
	ch(ps_ref->GetDesc(&ps_desc))

	reflect_shader_constants(
		ps_desc,
		ps_ref,
		&constant_descs,
		&d3d_constants,
		&d3d_constant_buffers,
		&d3d_texture_bindings,
		&texture_bindpoint_descs,
		desc_allocator,
		.Pixel,
	)

	// Done with vertex and pixel shader. Just combine all the state.

	desc.constants = constant_descs[:]
	desc.texture_bindpoints = texture_bindpoint_descs[:]

	d3d_shd := D3D11_Shader {
		constants = d3d_constants[:],
		constant_buffers = d3d_constant_buffers[:],
		vertex_shader = vertex_shader,
		pixel_shader = pixel_shader,
		input_layout = input_layout,
		texture_bindings = d3d_texture_bindings[:],
	}

	h := hm.add(&s.shaders, d3d_shd)
	return h, desc
}

D3D11_Shader_Type :: enum {
	Vertex,
	Pixel,
}

reflect_shader_constants :: proc(
	d3d_desc: d3d11.SHADER_DESC,
	ref: ^d3d11.IShaderReflection,
	constant_descs: ^[dynamic]Shader_Constant_Desc,
	d3d_constants: ^[dynamic]D3D11_Shader_Constant,
	d3d_constant_buffers: ^[dynamic]D3D11_Shader_Constant_Buffer,
	d3d_texture_bindings: ^[dynamic]D3D11_Texture_Binding,
	texture_bindpoint_descs: ^[dynamic]Shader_Texture_Bindpoint_Desc,
	desc_allocator: runtime.Allocator,
	shader_type: D3D11_Shader_Type,
) {
	found_sampler_bindpoints := make([dynamic]u32, frame_allocator)

	for br_idx in 0..<d3d_desc.BoundResources {
		bind_desc: d3d11.SHADER_INPUT_BIND_DESC
		ref->GetResourceBindingDesc(br_idx, &bind_desc)

		#partial switch bind_desc.Type {
		case .SAMPLER:
			append(&found_sampler_bindpoints, bind_desc.BindPoint)

		case .TEXTURE:
			append(d3d_texture_bindings, D3D11_Texture_Binding {
				bind_point = bind_desc.BindPoint,
			})

			append(texture_bindpoint_descs, Shader_Texture_Bindpoint_Desc {
				name = strings.clone_from_cstring(bind_desc.Name, desc_allocator),
			})
			
		case .CBUFFER:
			cb_info := ref->GetConstantBufferByName(bind_desc.Name)

			if cb_info == nil {
				continue
			}

			cb_desc: d3d11.SHADER_BUFFER_DESC
			cb_info->GetDesc(&cb_desc)

			if cb_desc.Size == 0 {
				continue
			}

			constant_buffer_desc := d3d11.BUFFER_DESC{
				ByteWidth      = cb_desc.Size,
				Usage          = .DYNAMIC,
				BindFlags      = {.CONSTANT_BUFFER},
				CPUAccessFlags = {.WRITE},
			}
			buffer_idx := -1

			for &existing, existing_idx in d3d_constant_buffers {
				if existing.bind_point == bind_desc.BindPoint {
					existing.bound_shaders += {shader_type}
					buffer_idx = existing_idx
					break
				}
			}

			if buffer_idx == -1 {
				buffer_idx = len(d3d_constant_buffers)

				buf := D3D11_Shader_Constant_Buffer {
					bound_shaders = {shader_type},
				}

				ch(s.device->CreateBuffer(&constant_buffer_desc, nil, &buf.gpu_data))
				buf.size = int(cb_desc.Size)
				buf.bind_point = bind_desc.BindPoint
				append(d3d_constant_buffers, buf)
			}

			for var_idx in 0..<cb_desc.Variables {
				var_info := cb_info->GetVariableByIndex(var_idx)

				if var_info == nil {
					continue
				}

				var_desc: d3d11.SHADER_VARIABLE_DESC
				var_info->GetDesc(&var_desc)

				if var_desc.Name != "" {
					append(constant_descs, Shader_Constant_Desc {
						name = strings.clone_from_cstring(var_desc.Name, desc_allocator),
						size = int(var_desc.Size),
					})

					append(d3d_constants, D3D11_Shader_Constant {
						buffer_idx = u32(buffer_idx),
						offset = var_desc.StartOffset,
					})
				}
			}
		case:
			log.errorf("Type is %v", bind_desc.Type)
		}
	}

	// Make sure each texture has a sampler. In GL samplers are associated with textures. In D3D11
	// several textures can use a single sampler. We don't want this as we want to be able to
	// configure filters etc on a per-texture level. Since two textures can arrive at a draw call
	// with different filters set, if they use the same sampler, then it will be impossible to set
	// that filtering up.
	for &t, t_idx in d3d_texture_bindings {
		found := false

		for sampler_bindpoint in found_sampler_bindpoints {
			if t.bind_point == sampler_bindpoint {
				t.sampler_bind_point = sampler_bindpoint
				found = true
				break
			}
		}

		if !found {
			log.errorf(
				"Texture %v at bindpoint %v does not have a dedicated sampler at " +
				"the sampler register with the same bindpoint number. This is required to " +
				"in order to make D3D11 behave the same way as OpenGL etc",
				texture_bindpoint_descs[t_idx].name,
				t.bind_point,
			)
		}
	}
}

d3d11_destroy_shader :: proc(h: Shader_Handle) {
	shd := hm.get(&s.shaders, h)

	if shd == nil {
		log.errorf("Invalid shader: %v", h)
		return
	}

	shd.input_layout->Release()
	shd.vertex_shader->Release()
	shd.pixel_shader->Release()

	for c in shd.constant_buffers {
		if c.gpu_data != nil {
			c.gpu_data->Release()
		}
	}

	delete(shd.texture_bindings, s.allocator)
	delete(shd.constants, s.allocator)
	delete(shd.constant_buffers, s.allocator)
	hm.remove(&s.shaders, h)
}

// API END

s: ^D3D11_State

D3D11_Shader_Constant_Buffer :: struct {
	gpu_data: ^d3d11.IBuffer,
	size: int,
	bound_shaders: bit_set[D3D11_Shader_Type],
	bind_point: u32,
}

D3D11_Texture_Binding :: struct {
	bind_point: u32,
	sampler_bind_point: u32,
}

D3D11_Shader_Constant :: struct {
	buffer_idx: u32,
	offset: u32,
}

D3D11_Shader :: struct {
	handle: Shader_Handle,
	vertex_shader: ^d3d11.IVertexShader,
	pixel_shader: ^d3d11.IPixelShader,
	input_layout: ^d3d11.IInputLayout,
	constant_buffers: []D3D11_Shader_Constant_Buffer,
	constants: []D3D11_Shader_Constant,
	texture_bindings: []D3D11_Texture_Binding,
}

D3D11_State :: struct {
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

	textures: hm.Handle_Map(D3D11_Texture, Texture_Handle, 1024*10),
	render_targets: hm.Handle_Map(D3D11_Render_Target, Render_Target_Handle, 1024*10),
	shaders: hm.Handle_Map(D3D11_Shader, Shader_Handle, 1024*10),

	info_queue: ^d3d11.IInfoQueue,
	vertex_buffer_gpu: ^d3d11.IBuffer,

	all_samplers: map[^d3d11.ISamplerState]struct{},
}

create_swapchain :: proc(w, h: int) {
	swapchain_desc := dxgi.SWAP_CHAIN_DESC1 {
		Width = u32(w),
		Height = u32(h),
		Format = .B8G8R8A8_UNORM,
		SampleDesc = {
			Count   = 1,
		},
		BufferUsage = {.RENDER_TARGET_OUTPUT},
		BufferCount = 2,
		Scaling     = .STRETCH,
		SwapEffect  = .DISCARD,
	}

	dxgi_factory: ^dxgi.IFactory2
	ch(s.dxgi_adapter->GetParent(dxgi.IFactory2_UUID, (^rawptr)(&dxgi_factory)))
	ch(dxgi_factory->CreateSwapChainForHwnd(s.device, s.window_handle, &swapchain_desc, nil, nil, &s.swapchain))
	ch(s.swapchain->GetBuffer(0, d3d11.ITexture2D_UUID, (^rawptr)(&s.framebuffer)))
	ch(s.device->CreateRenderTargetView(s.framebuffer, nil, &s.framebuffer_view))
}

D3D11_Texture :: struct {
	handle: Texture_Handle,
	tex: ^d3d11.ITexture2D,
	view: ^d3d11.IShaderResourceView,
	format: Pixel_Format,

	// It may seem strange that we have a sampler here. But samplers are reused if you recreate them
	// with the same options. D3D11 will return the same object. So each time we set the filter
	// mode or the UV wrapping settings, then we just ask D3D11 for the sampler state for those
	// settings.
	//
	// Moreover, in order to make D3D11 behave a bit like GL (or rather, to make them behave more
	// similarly), we require that each texture in the HLSL shaders have a dedicated sampler.
	sampler: ^d3d11.ISamplerState,
}

D3D11_Render_Target :: struct {
	handle: Render_Target_Handle,
	render_target_view: ^d3d11.IRenderTargetView,
	width: int,
	height: int,
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
ch :: proc(hr: dxgi.HRESULT, loc := #caller_location) -> dxgi.HRESULT {
	if hr >= 0 {
		return hr
	}

	log.errorf("d3d11 error: %0x", u32(hr), location = loc)
	log_messages(loc)
	return hr
}

log_messages :: proc(loc := #caller_location) {
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

DEFAULT_SHADER_SOURCE :: #load("render_backend_d3d11_default_shader.hlsl")

d3d11_default_shader_vertex_source :: proc() -> []byte {
	s := DEFAULT_SHADER_SOURCE
	return s
}

d3d11_default_shader_fragment_source :: proc() -> []byte {
	s := DEFAULT_SHADER_SOURCE
	return s
}