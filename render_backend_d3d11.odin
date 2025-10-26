#+build windows
#+private file

package karl2d

@(private="package")
RENDER_BACKEND_INTERFACE_D3D11 :: Render_Backend_Interface {
	state_size = d3d11_state_size,
	init = d3d11_init,
	shutdown = d3d11_shutdown,
	clear = d3d11_clear,
	present = d3d11_present,
	draw = d3d11_draw,
	resize_swapchain = d3d11_resize_swapchain,
	get_swapchain_width = d3d11_get_swapchain_width,
	get_swapchain_height = d3d11_get_swapchain_height,
	set_internal_state = d3d11_set_internal_state,
	create_texture = d3d11_create_texture,
	load_texture = d3d11_load_texture,
	update_texture = d3d11_update_texture,
	destroy_texture = d3d11_destroy_texture,
	load_shader = d3d11_load_shader,
	destroy_shader = d3d11_destroy_shader,
}

import d3d11 "vendor:directx/d3d11"
import dxgi "vendor:directx/dxgi"
import "vendor:directx/d3d_compiler"
import "core:strings"
import "core:log"
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

	depth_stencil_desc := d3d11.DEPTH_STENCIL_DESC{
		DepthEnable    = false,
		DepthWriteMask = .ALL,
		DepthFunc      = .LESS,
	}
	ch(s.device->CreateDepthStencilState(&depth_stencil_desc, &s.depth_stencil_state))

	vertex_buffer_desc := d3d11.BUFFER_DESC{
		ByteWidth = VERTEX_BUFFER_MAX,
		Usage     = .DYNAMIC,
		BindFlags = {.VERTEX_BUFFER},
		CPUAccessFlags = {.WRITE},
	}
	ch(s.device->CreateBuffer(&vertex_buffer_desc, nil, &s.vertex_buffer_gpu))
	
	blend_desc := d3d11.BLEND_DESC {
		RenderTarget = {
			0 = {
				BlendEnable = true,
				SrcBlend = .SRC_ALPHA,
				DestBlend = .INV_SRC_ALPHA,
				BlendOp = .ADD,
				SrcBlendAlpha = .ONE,
				DestBlendAlpha = .ZERO,
				BlendOpAlpha = .ADD,
				RenderTargetWriteMask = u8(d3d11.COLOR_WRITE_ENABLE_ALL),
			},
		},
	}

	ch(s.device->CreateBlendState(&blend_desc, &s.blend_state))

	sampler_desc := d3d11.SAMPLER_DESC{
		Filter         = .MIN_MAG_MIP_POINT,
		AddressU       = .WRAP,
		AddressV       = .WRAP,
		AddressW       = .WRAP,
		ComparisonFunc = .NEVER,
	}
	s.device->CreateSamplerState(&sampler_desc, &s.sampler_state)
}

d3d11_shutdown :: proc() {
	s.sampler_state->Release()
	s.framebuffer_view->Release()
	s.depth_buffer_view->Release()
	s.depth_buffer->Release()
	s.framebuffer->Release()
	s.device_context->Release()
	s.vertex_buffer_gpu->Release()
	s.depth_stencil_state->Release()
	s.rasterizer_state->Release()
	s.swapchain->Release()
	s.blend_state->Release()
	s.dxgi_adapter->Release()

	when ODIN_DEBUG {
		debug: ^d3d11.IDebug

		if ch(s.device->QueryInterface(d3d11.IDebug_UUID, (^rawptr)(&debug))) >= 0 {
			ch(debug->ReportLiveDeviceObjects({.DETAIL, .IGNORE_INTERNAL}))
			log_messages()
		}

		debug->Release()
	}
	
	s.device->Release()
	s.info_queue->Release()
}

d3d11_clear :: proc(color: Color) {
	c := f32_color_from_color(color)
	s.device_context->ClearRenderTargetView(s.framebuffer_view, &c)
	s.device_context->ClearDepthStencilView(s.depth_buffer_view, {.DEPTH}, 1, 0)
}

d3d11_present :: proc() {
	ch(s.swapchain->Present(1, {}))
}

d3d11_draw :: proc(shd: Shader, texture: Texture_Handle, view_proj: Mat4, scissor: Maybe(Rect), vertex_buffer: []u8) {
	if len(vertex_buffer) == 0 {
		return
	}

	d3d_shd := hm.get(&s.shaders, shd.handle)

	if d3d_shd == nil {
		return
	}

	viewport := d3d11.VIEWPORT{
		0, 0,
		f32(s.width), f32(s.height),
		0, 1,
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

	for mloc, builtin in shd.constant_builtin_locations {
		loc, loc_ok := mloc.?

		if !loc_ok {
			continue
		}

		switch builtin {
		case .MVP:
			dst := (^matrix[4,4]f32)(&shd.constant_buffers[loc.buffer_idx].cpu_data[loc.offset])
			dst^ = view_proj
		}
	}

	dc->VSSetShader(d3d_shd.vertex_shader, nil, 0)

	assert(len(shd.constant_buffers) == len(d3d_shd.constant_buffers))

	for cb_idx in 0..<len(shd.constant_buffers) {
		cpu_data := shd.constant_buffers[cb_idx].cpu_data
		gpu_data := d3d_shd.constant_buffers[cb_idx].gpu_data
		
		if gpu_data == nil {
			continue
		}

		cb_data: d3d11.MAPPED_SUBRESOURCE
		ch(dc->Map(gpu_data, 0, .WRITE_DISCARD, {}, &cb_data))
		mem.copy(cb_data.pData, raw_data(cpu_data), len(cpu_data))
		dc->Unmap(gpu_data, 0)
		dc->VSSetConstantBuffers(u32(cb_idx), 1, &gpu_data)
		dc->PSSetConstantBuffers(u32(cb_idx), 1, &gpu_data)
	}

	dc->RSSetViewports(1, &viewport)
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

	if t := hm.get(&s.textures, texture); t != nil {
		dc->PSSetShaderResources(0, 1, &t.view)	
	}
	
	dc->PSSetSamplers(0, 1, &s.sampler_state)

	dc->OMSetRenderTargets(1, &s.framebuffer_view, s.depth_buffer_view)
	dc->OMSetDepthStencilState(s.depth_stencil_state, 0)
	dc->OMSetBlendState(s.blend_state, nil, ~u32(0))

	dc->Draw(u32(len(vertex_buffer)/shd.vertex_size), 0)
	log_messages()
}

d3d11_resize_swapchain :: proc(w, h: int) {
	s.depth_buffer->Release()
	s.depth_buffer_view->Release()
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

d3d11_set_internal_state :: proc(state: rawptr) {
	s = (^D3D11_State)(state)
}

d3d11_create_texture :: proc(width: int, height: int, format: Pixel_Format) -> Texture_Handle {
	texture_desc := d3d11.TEXTURE2D_DESC{
		Width      = u32(width),
		Height     = u32(height),
		MipLevels  = 1,
		ArraySize  = 1,
		// TODO: _SRGB or not?
		Format     = dxgi_format_from_pixel_format(format),
		SampleDesc = {Count = 1},
		Usage      = .DEFAULT,
		BindFlags  = {.SHADER_RESOURCE},
	}

	texture: ^d3d11.ITexture2D
	s.device->CreateTexture2D(&texture_desc, nil, &texture)

	texture_view: ^d3d11.IShaderResourceView
	s.device->CreateShaderResourceView(texture, nil, &texture_view)

	tex := D3D11_Texture {
		tex = texture,
		format = format,
		view = texture_view,
	}

	return hm.add(&s.textures, tex)
}

d3d11_load_texture :: proc(data: []u8, width: int, height: int, format: Pixel_Format) -> Texture_Handle {
	texture_desc := d3d11.TEXTURE2D_DESC{
		Width      = u32(width),
		Height     = u32(height),
		MipLevels  = 1,
		ArraySize  = 1,
		// TODO: _SRGB or not?
		Format     = dxgi_format_from_pixel_format(format),
		SampleDesc = {Count = 1},
		Usage      = .DEFAULT,
		BindFlags  = {.SHADER_RESOURCE},
	}

	texture_data := d3d11.SUBRESOURCE_DATA{
		pSysMem     = raw_data(data),
		SysMemPitch = u32(width * pixel_format_size(format)),
	}

	texture: ^d3d11.ITexture2D
	s.device->CreateTexture2D(&texture_desc, &texture_data, &texture)

	texture_view: ^d3d11.IShaderResourceView
	s.device->CreateShaderResourceView(texture, nil, &texture_view)

	tex := D3D11_Texture {
		tex = texture,
		format = format,
		view = texture_view,
	}

	return hm.add(&s.textures, tex)
}

d3d11_update_texture :: proc(th: Texture_Handle, data: []u8, rect: Rect) -> bool {
	tex := hm.get(&s.textures, th)

	if tex == nil {
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
	}

	hm.remove(&s.textures, th)
}

d3d11_load_shader :: proc(vs_source: string, ps_source: string, desc_allocator := frame_allocator, layout_formats: []Pixel_Format = {}) -> (handle: Shader_Handle, desc: Shader_Desc) {
	vs_blob: ^d3d11.IBlob
	vs_blob_errors: ^d3d11.IBlob
	ch(d3d_compiler.Compile(raw_data(vs_source), len(vs_source), nil, nil, nil, "vs_main", "vs_5_0", 0, 0, &vs_blob, &vs_blob_errors))

	if vs_blob_errors != nil {
		log.error("Failed compiling shader:")
		log.error(strings.string_from_ptr((^u8)(vs_blob_errors->GetBufferPointer()), int(vs_blob_errors->GetBufferSize())))
		return
	}

	vertex_shader: ^d3d11.IVertexShader

	ch(s.device->CreateVertexShader(vs_blob->GetBufferPointer(), vs_blob->GetBufferSize(), nil, &vertex_shader))

	ref: ^d3d11.IShaderReflection
	ch(d3d_compiler.Reflect(vs_blob->GetBufferPointer(), vs_blob->GetBufferSize(), d3d11.ID3D11ShaderReflection_UUID, (^rawptr)(&ref)))
	
	d3d_shd: D3D11_Shader
	d3d_desc: d3d11.SHADER_DESC
	ch(ref->GetDesc(&d3d_desc))

	{
		desc.inputs = make([]Shader_Input, d3d_desc.InputParameters, desc_allocator)
		assert(len(layout_formats) == 0 || len(layout_formats) == len(desc.inputs))

		for in_idx in 0..<d3d_desc.InputParameters {
			in_desc: d3d11.SIGNATURE_PARAMETER_DESC
			
			if ch(ref->GetInputParameterDesc(in_idx, &in_desc)) < 0 {
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

	{
		desc.constant_buffers = make([]Shader_Constant_Buffer_Desc, d3d_desc.ConstantBuffers, desc_allocator)
		d3d_shd.constant_buffers = make([]D3D11_Shader_Constant_Buffer, d3d_desc.ConstantBuffers, s.allocator)

		for cb_idx in 0..<d3d_desc.ConstantBuffers {
			cb_info := ref->GetConstantBufferByIndex(cb_idx)

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

			ch(s.device->CreateBuffer(&constant_buffer_desc, nil, &d3d_shd.constant_buffers[cb_idx].gpu_data))

			variables := make([]Shader_Constant_Buffer_Variable_Desc, cb_desc.Variables, desc_allocator)
			desc.constant_buffers[cb_idx].variables = variables
			desc.constant_buffers[cb_idx].size = int(cb_desc.Size)

			for var_idx in 0..<cb_desc.Variables {
				var_info := cb_info->GetVariableByIndex(var_idx)

				if var_info == nil {
					continue
				}

				var_desc: d3d11.SHADER_VARIABLE_DESC
				var_info->GetDesc(&var_desc)

				if var_desc.Name != "" {
					variables[var_idx] = {
						name = strings.clone_from_cstring(var_desc.Name, desc_allocator),
						loc = {
							buffer_idx = cb_idx,
							offset = var_desc.StartOffset,
						},
					}
				}
			}
		}
	}

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

	ps_blob: ^d3d11.IBlob
	ps_blob_errors: ^d3d11.IBlob
	ch(d3d_compiler.Compile(raw_data(ps_source), len(ps_source), nil, nil, nil, "ps_main", "ps_5_0", 0, 0, &ps_blob, &ps_blob_errors))

	if ps_blob_errors != nil {
		log.error("Failed compiling shader:")
		log.error(strings.string_from_ptr((^u8)(ps_blob_errors->GetBufferPointer()), int(ps_blob_errors->GetBufferSize())))
	}

	pixel_shader: ^d3d11.IPixelShader
	ch(s.device->CreatePixelShader(ps_blob->GetBufferPointer(), ps_blob->GetBufferSize(), nil, &pixel_shader))

	d3d_shd.vertex_shader = vertex_shader
	d3d_shd.pixel_shader = pixel_shader
	d3d_shd.input_layout = input_layout

	h := hm.add(&s.shaders, d3d_shd)
	return h, desc
}

d3d11_destroy_shader :: proc(h: Shader_Handle) {
	shd := hm.get(&s.shaders, h)

	if shd == nil {
		log.error("Invalid shader %v", h)
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

	delete(shd.constant_buffers, s.allocator)
	hm.remove(&s.shaders, h)
}

// API END

s: ^D3D11_State

D3D11_Shader_Constant_Buffer :: struct {
	gpu_data: ^d3d11.IBuffer,
}

D3D11_Shader :: struct {
	handle: Shader_Handle,
	vertex_shader: ^d3d11.IVertexShader,
	pixel_shader: ^d3d11.IPixelShader,
	input_layout: ^d3d11.IInputLayout,
	constant_buffers: []D3D11_Shader_Constant_Buffer,
}

D3D11_State :: struct {
	allocator: runtime.Allocator,

	window_handle: dxgi.HWND,
	width: int,
	height: int,

	dxgi_adapter: ^dxgi.IAdapter,
	swapchain: ^dxgi.ISwapChain1,
	framebuffer_view: ^d3d11.IRenderTargetView,
	depth_buffer_view: ^d3d11.IDepthStencilView,
	device_context: ^d3d11.IDeviceContext,
	depth_stencil_state: ^d3d11.IDepthStencilState,
	rasterizer_state: ^d3d11.IRasterizerState,
	device: ^d3d11.IDevice,
	depth_buffer: ^d3d11.ITexture2D,
	framebuffer: ^d3d11.ITexture2D,
	blend_state: ^d3d11.IBlendState,
	sampler_state: ^d3d11.ISamplerState,

	textures: hm.Handle_Map(D3D11_Texture, Texture_Handle, 1024*10),
	shaders: hm.Handle_Map(D3D11_Shader, Shader_Handle, 1024*10),

	info_queue: ^d3d11.IInfoQueue,
	vertex_buffer_gpu: ^d3d11.IBuffer,
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

	depth_buffer_desc: d3d11.TEXTURE2D_DESC
	s.framebuffer->GetDesc(&depth_buffer_desc)
	depth_buffer_desc.Format = .D24_UNORM_S8_UINT
	depth_buffer_desc.BindFlags = {.DEPTH_STENCIL}

	ch(s.device->CreateTexture2D(&depth_buffer_desc, nil, &s.depth_buffer))
	ch(s.device->CreateDepthStencilView(s.depth_buffer, nil, &s.depth_buffer_view))
}

Color_F32 :: [4]f32

f32_color_from_color :: proc(color: Color) -> Color_F32 {
	return {
		f32(color.r) / 255,
		f32(color.g) / 255,
		f32(color.b) / 255,
		f32(color.a) / 255,
	}
}

D3D11_Texture :: struct {
	handle: Texture_Handle,
	tex: ^d3d11.ITexture2D,
	view: ^d3d11.IShaderResourceView,
	format: Pixel_Format,
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