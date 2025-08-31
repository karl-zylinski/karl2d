#+build windows

package karl2d
import d3d11 "vendor:directx/d3d11"
import dxgi "vendor:directx/dxgi"
import "vendor:directx/d3d_compiler"
import "core:strings"
import "core:log"
import "core:math/linalg"
import "core:slice"
import "core:mem"
import hm "handle_map"
import "base:runtime"


BACKEND_D3D11 :: Rendering_Backend {
	state_size = d3d11_state_size,
	init = d3d11_init,
	shutdown = d3d11_shutdown,
	clear = d3d11_clear,
	present = d3d11_present,
	draw = d3d11_draw,
	
	get_swapchain_width = d3d11_get_swapchain_width,
	get_swapchain_height = d3d11_get_swapchain_height,

	set_view_projection_matrix = d3d11_set_view_projection_matrix,

	set_internal_state = d3d11_set_internal_state,

	load_texture = d3d11_load_texture,
	destroy_texture = d3d11_destroy_texture,

	load_shader = d3d11_load_shader,
	destroy_shader = d3d11_destroy_shader,
}

@(private="file")
s: ^D3D11_State

d3d11_state_size :: proc() -> int {
	return size_of(D3D11_State)
}

d3d11_init :: proc(state: rawptr, window_handle: uintptr, swapchain_width, swapchain_height: int,
	allocator := context.allocator, loc := #caller_location) {
	hwnd := dxgi.HWND(window_handle)
	s = (^D3D11_State)(state)
	s.allocator = allocator
	s.width = swapchain_width
	s.height = swapchain_height
	feature_levels := [?]d3d11.FEATURE_LEVEL{
		._11_1,
		._11_0,
	}

	base_device: ^d3d11.IDevice
	base_device_context: ^d3d11.IDeviceContext

	device_flags := d3d11.CREATE_DEVICE_FLAGS {
		.BGRA_SUPPORT,
	}

	when ODIN_DEBUG {
		device_flags += { .DEBUG }
	}

	ch(d3d11.CreateDevice(
		nil,
		.HARDWARE,
		nil,
		device_flags,
		&feature_levels[0], len(feature_levels),
		d3d11.SDK_VERSION, &base_device, nil, &base_device_context))

	ch(base_device->QueryInterface(d3d11.IInfoQueue_UUID, (^rawptr)(&s.info_queue)))
	ch(base_device->QueryInterface(d3d11.IDevice_UUID, (^rawptr)(&s.device)))
	ch(base_device_context->QueryInterface(d3d11.IDeviceContext_UUID, (^rawptr)(&s.device_context)))
	dxgi_device: ^dxgi.IDevice
	ch(s.device->QueryInterface(dxgi.IDevice_UUID, (^rawptr)(&dxgi_device)))
	base_device->Release()
	base_device_context->Release()

	dxgi_adapter: ^dxgi.IAdapter
	
	ch(dxgi_device->GetAdapter(&dxgi_adapter))
	dxgi_device->Release()

	dxgi_factory: ^dxgi.IFactory2
	ch(dxgi_adapter->GetParent(dxgi.IFactory2_UUID, (^rawptr)(&dxgi_factory)))

	swapchain_desc := dxgi.SWAP_CHAIN_DESC1 {
		Format = .B8G8R8A8_UNORM,
		SampleDesc = {
			Count   = 1,
		},
		BufferUsage = {.RENDER_TARGET_OUTPUT},
		BufferCount = 2,
		Scaling     = .STRETCH,
		SwapEffect  = .DISCARD,
	}

	ch(dxgi_factory->CreateSwapChainForHwnd(s.device, hwnd, &swapchain_desc, nil, nil, &s.swapchain))
	ch(s.swapchain->GetBuffer(0, d3d11.ITexture2D_UUID, (^rawptr)(&s.framebuffer)))
	ch(s.device->CreateRenderTargetView(s.framebuffer, nil, &s.framebuffer_view))

	depth_buffer_desc: d3d11.TEXTURE2D_DESC
	s.framebuffer->GetDesc(&depth_buffer_desc)
	depth_buffer_desc.Format = .D24_UNORM_S8_UINT
	depth_buffer_desc.BindFlags = {.DEPTH_STENCIL}

	ch(s.device->CreateTexture2D(&depth_buffer_desc, nil, &s.depth_buffer))
	ch(s.device->CreateDepthStencilView(s.depth_buffer, nil, &s.depth_buffer_view))


	rasterizer_desc := d3d11.RASTERIZER_DESC{
		FillMode = .SOLID,
		CullMode = .BACK,
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
	//s.constant_buffer->Release()
	s.depth_stencil_state->Release()
	s.rasterizer_state->Release()
	s.swapchain->Release()
	s.blend_state->Release()

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

d3d11_set_internal_state :: proc(state: rawptr) {
	s = (^D3D11_State)(state)
}

d3d11_get_swapchain_width :: proc() -> int {
	return s.width
}

d3d11_get_swapchain_height :: proc() -> int {
	return s.height
}

d3d11_set_view_projection_matrix :: proc(m: Mat4) {
	s.view_proj = m
}

VERTEX_BUFFER_MAX :: 1000000

TEXTURE_NONE :: Texture_Handle {}

Shader_Constant_Buffer :: struct {
	gpu_data: ^d3d11.IBuffer,
	cpu_data: []u8,
}

Shader_Builtin_Constant :: enum {
	MVP,
}

Shader_Input_Type :: enum {
	F32,
	Vec2,
	Vec3,
	Vec4,
}

Shader_Input :: struct {
	name: string,
	register: int,
	type: Shader_Input_Type,
	format: Shader_Input_Format,
}

Shader_Default_Inputs :: enum {
	Position,
	UV,
	Color,
}

D3D11_Shader :: struct {
	handle: Shader_Handle,
	vertex_shader: ^d3d11.IVertexShader,
	pixel_shader: ^d3d11.IPixelShader,
	input_layout: ^d3d11.IInputLayout,
}

D3D11_State :: struct {
	allocator: runtime.Allocator,

	width: int,
	height: int,

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

	vertex_buffer_offset: int,
	
	batch_shader: Shader_Handle,

	view_proj: Mat4,
}

vec3_from_vec2 :: proc(v: Vec2) -> Vec3 {
	return {
		v.x, v.y, 0,
	}
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

d3d11_clear :: proc(color: Color) {
	c := f32_color_from_color(color)
	s.device_context->ClearRenderTargetView(s.framebuffer_view, &c)
	s.device_context->ClearDepthStencilView(s.depth_buffer_view, {.DEPTH}, 1, 0)
}

D3D11_Texture :: struct {
	handle: Texture_Handle,
	tex: ^d3d11.ITexture2D,
	view: ^d3d11.IShaderResourceView,
}

d3d11_load_texture :: proc(data: []u8, width: int, height: int) -> Texture_Handle {
	texture_desc := d3d11.TEXTURE2D_DESC{
		Width      = u32(width),
		Height     = u32(height),
		MipLevels  = 1,
		ArraySize  = 1,
		// TODO: _SRGB or not?
		Format     = .R8G8B8A8_UNORM,
		SampleDesc = {Count = 1},
		Usage      = .IMMUTABLE,
		BindFlags  = {.SHADER_RESOURCE},
	}

	texture_data := d3d11.SUBRESOURCE_DATA{
		pSysMem     = raw_data(data),
		SysMemPitch = u32(width * 4),
	}

	texture: ^d3d11.ITexture2D
	s.device->CreateTexture2D(&texture_desc, &texture_data, &texture)

	texture_view: ^d3d11.IShaderResourceView
	s.device->CreateShaderResourceView(texture, nil, &texture_view)

	tex := D3D11_Texture {
		tex = texture,
		view = texture_view,
	}

	return hm.add(&s.textures, tex)
}

d3d11_destroy_texture :: proc(th: Texture_Handle) {
	if t := hm.get(&s.textures, th); t != nil {
		t.tex->Release()
		t.view->Release()	
	}

	hm.remove(&s.textures, th)
}

Shader_Input_Value_Override :: struct {
	val: [256]u8,
	used: int,
}

create_vertex_input_override :: proc(val: $T) -> Shader_Input_Value_Override {
	assert(size_of(T) < 256)
	res: Shader_Input_Value_Override
	((^T)(raw_data(&res.val)))^ = val
	res.used = size_of(T)
	return res
}

d3d11_draw :: proc(shd: Shader, texture: Texture_Handle, vertex_buffer: []u8) {
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
	ch(dc->Map(s.vertex_buffer_gpu, 0, .WRITE_NO_OVERWRITE, {}, &vb_data))
	{
		gpu_map := slice.from_ptr((^u8)(vb_data.pData), VERTEX_BUFFER_MAX)
		copy(
			gpu_map[s.vertex_buffer_offset:s.vertex_buffer_offset+len(vertex_buffer)],
			vertex_buffer,
		)
	}
	dc->Unmap(s.vertex_buffer_gpu, 0)


	dc->IASetPrimitiveTopology(.TRIANGLELIST)

	dc->IASetInputLayout(d3d_shd.input_layout)
	vertex_buffer_offset := u32(0)
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
			dst^ = s.view_proj
		}
	}

	dc->VSSetShader(d3d_shd.vertex_shader, nil, 0)

	for &c, c_idx in shd.constant_buffers {
		if c.gpu_data == nil {
			continue
		}

		cb_data: d3d11.MAPPED_SUBRESOURCE
		ch(dc->Map(c.gpu_data, 0, .WRITE_DISCARD, {}, &cb_data))
		mem.copy(cb_data.pData, raw_data(c.cpu_data), len(c.cpu_data))
		dc->Unmap(c.gpu_data, 0)
		dc->VSSetConstantBuffers(u32(c_idx), 1, &c.gpu_data)
		dc->PSSetConstantBuffers(u32(c_idx), 1, &c.gpu_data)
	}

	dc->RSSetViewports(1, &viewport)
	dc->RSSetState(s.rasterizer_state)

	dc->PSSetShader(d3d_shd.pixel_shader, nil, 0)

	if t := hm.get(&s.textures, texture); t != nil {
		dc->PSSetShaderResources(0, 1, &t.view)	
	}
	
	dc->PSSetSamplers(0, 1, &s.sampler_state)

	dc->OMSetRenderTargets(1, &s.framebuffer_view, s.depth_buffer_view)
	dc->OMSetDepthStencilState(s.depth_stencil_state, 0)
	dc->OMSetBlendState(s.blend_state, nil, ~u32(0))

	dc->Draw(u32(len(vertex_buffer)/shd.vertex_size), u32(s.vertex_buffer_offset/shd.vertex_size))
	s.vertex_buffer_offset += len(vertex_buffer)
	log_messages()
}

make_default_projection :: proc(w, h: int) -> matrix[4,4]f32 {
	return linalg.matrix_ortho3d_f32(0, f32(w), f32(h), 0, 0.001, 2)
}

d3d11_present :: proc() {
	ch(s.swapchain->Present(1, {}))
	s.vertex_buffer_offset = 0
}

Shader_Constant_Location :: struct {
	buffer_idx: u32,
	offset: u32,
}

d3d11_load_shader :: proc(shader: string, layout_formats: []Shader_Input_Format = {}) -> Shader {
	vs_blob: ^d3d11.IBlob
	vs_blob_errors: ^d3d11.IBlob
	ch(d3d_compiler.Compile(raw_data(shader), len(shader), nil, nil, nil, "vs_main", "vs_5_0", 0, 0, &vs_blob, &vs_blob_errors))

	if vs_blob_errors != nil {
		log.error("Failed compiling shader:")
		log.error(strings.string_from_ptr((^u8)(vs_blob_errors->GetBufferPointer()), int(vs_blob_errors->GetBufferSize())))
	}

	vertex_shader: ^d3d11.IVertexShader

	ch(s.device->CreateVertexShader(vs_blob->GetBufferPointer(), vs_blob->GetBufferSize(), nil, &vertex_shader))

	ref: ^d3d11.IShaderReflection
	ch(d3d_compiler.Reflect(vs_blob->GetBufferPointer(), vs_blob->GetBufferSize(), d3d11.ID3D11ShaderReflection_UUID, (^rawptr)(&ref)))

	constant_buffers: []Shader_Constant_Buffer
	constant_lookup: map[string]Shader_Constant_Location
	constant_builtin_locations: [Shader_Builtin_Constant]Maybe(Shader_Constant_Location)
	inputs: []Shader_Input
	{
		context.allocator = s.allocator
		d: d3d11.SHADER_DESC
		ch(ref->GetDesc(&d))

		inputs = make([]Shader_Input, d.InputParameters)

		for in_idx in 0..<d.InputParameters {
			in_desc: d3d11.SIGNATURE_PARAMETER_DESC
			
			if ch(ref->GetInputParameterDesc(in_idx, &in_desc)) < 0 {
				log.errorf("Invalid input: %v in shader %v", in_idx, shader)
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

			inputs[in_idx] = {
				name = strings.clone_from_cstring(in_desc.SemanticName),
				register = int(in_idx),
				type = type,
			}
		}

		constant_buffers = make([]Shader_Constant_Buffer, d.ConstantBuffers)

		for cb_idx in 0..<d.ConstantBuffers {
			cb_info := ref->GetConstantBufferByIndex(cb_idx)

			if cb_info == nil {
				continue
			}

			cb_desc: d3d11.SHADER_BUFFER_DESC
			cb_info->GetDesc(&cb_desc)

			if cb_desc.Size == 0 {
				continue
			}

			b := &constant_buffers[cb_idx]
			b.cpu_data = make([]u8, cb_desc.Size, s.allocator)

			constant_buffer_desc := d3d11.BUFFER_DESC{
				ByteWidth      = cb_desc.Size,
				Usage          = .DYNAMIC,
				BindFlags      = {.CONSTANT_BUFFER},
				CPUAccessFlags = {.WRITE},
			}
			ch(s.device->CreateBuffer(&constant_buffer_desc, nil, &b.gpu_data))

			for var_idx in 0..<cb_desc.Variables {
				var_info := cb_info->GetVariableByIndex(var_idx)

				if var_info == nil {
					continue
				}

				var_desc: d3d11.SHADER_VARIABLE_DESC
				var_info->GetDesc(&var_desc)

				if var_desc.Name != "" {
					loc := Shader_Constant_Location {
						buffer_idx = cb_idx,
						offset = var_desc.StartOffset,
					}

					constant_lookup[strings.clone_from_cstring(var_desc.Name)] = loc

					switch var_desc.Name {
					case "mvp":
						constant_builtin_locations[.MVP] = loc
					}
				}

				// TODO add the size or type somewhere so we set it correctly

				/*log.info(var_desc)

				type_info := var_info->GetType()

				type_info_desc: d3d11.SHADER_TYPE_DESC
				type_info->GetDesc(&type_info_desc)
				log.info(type_info_desc)*/
			}
		}
	}

	default_input_offsets: [Shader_Default_Inputs]int
	for &d in default_input_offsets {
		d = -1
	}
	input_offset: int

	if len(layout_formats) > 0 {
		if len(layout_formats) != len(inputs) {
			log.error("Passed number of layout formats isn't same as number of shader inputs")
		} else {
			for &i, idx in inputs {
				i.format = layout_formats[idx]

				if i.name == "POS" && i.type == .Vec2 {
					default_input_offsets[.Position] = input_offset
				} else if i.name == "UV" && i.type == .Vec2 {
					default_input_offsets[.UV] = input_offset
				} else if i.name == "COL" && i.type == .Vec4 {
					default_input_offsets[.Color] = input_offset
				}

				input_offset += shader_input_format_size(i.format)
			}
		}
	} else {
		for &i in inputs {
			if i.name == "POS" && i.type == .Vec2 {
				i.format = .RG32_Float
				default_input_offsets[.Position] = input_offset
			} else if i.name == "UV" && i.type == .Vec2 {
				i.format = .RG32_Float
				default_input_offsets[.UV] = input_offset
			} else if i.name == "COL" && i.type == .Vec4 {
				i.format = .RGBA8_Norm
				default_input_offsets[.Color] = input_offset
			} else {
				switch i.type {
				case .F32: i.format = .R32_Float
				case .Vec2: i.format = .RG32_Float
				case .Vec3: i.format = .RGBA32_Float
				case .Vec4: i.format = .RGBA32_Float
				}
			}

			input_offset += shader_input_format_size(i.format)
		}
	}

	input_layout_desc := make([]d3d11.INPUT_ELEMENT_DESC, len(inputs), context.temp_allocator)

	for idx in 0..<len(inputs) {
		input := inputs[idx]
		input_layout_desc[idx] = {
			SemanticName = temp_cstring(input.name),
			Format = dxgi_format_from_shader_input_format(input.format),
			AlignedByteOffset = idx == 0 ? 0 : d3d11.APPEND_ALIGNED_ELEMENT,
			InputSlotClass = .VERTEX_DATA,
		}
	}

	input_layout: ^d3d11.IInputLayout
	ch(s.device->CreateInputLayout(raw_data(input_layout_desc), u32(len(input_layout_desc)), vs_blob->GetBufferPointer(), vs_blob->GetBufferSize(), &input_layout))

	ps_blob: ^d3d11.IBlob
	ps_blob_errors: ^d3d11.IBlob
	ch(d3d_compiler.Compile(raw_data(shader), len(shader), nil, nil, nil, "ps_main", "ps_5_0", 0, 0, &ps_blob, &ps_blob_errors))

	if ps_blob_errors != nil {
		log.error("Failed compiling shader:")
		log.error(strings.string_from_ptr((^u8)(ps_blob_errors->GetBufferPointer()), int(ps_blob_errors->GetBufferSize())))
	}

	pixel_shader: ^d3d11.IPixelShader
	ch(s.device->CreatePixelShader(ps_blob->GetBufferPointer(), ps_blob->GetBufferSize(), nil, &pixel_shader))

	shd := D3D11_Shader {
		vertex_shader = vertex_shader,
		pixel_shader = pixel_shader,
		input_layout = input_layout,
	}

	h := hm.add(&s.shaders, shd)
	return {
		handle = h,
		constant_buffers = constant_buffers,
		constant_lookup = constant_lookup,
		constant_builtin_locations = constant_builtin_locations,
		inputs = inputs,
		input_overrides = make([]Shader_Input_Value_Override, len(inputs)),
		default_input_offsets = default_input_offsets,
		vertex_size = input_offset,
	}
}

dxgi_format_from_shader_input_format :: proc(f: Shader_Input_Format) -> dxgi.FORMAT {
	switch f {
	case .Unknown: return .UNKNOWN
	case .RGBA32_Float: return .R32G32B32A32_FLOAT
	case .RGBA8_Norm: return .R8G8B8A8_UNORM
	case .RGBA8_Norm_SRGB: return .R8G8B8A8_UNORM_SRGB
	case .RG32_Float: return .R32G32_FLOAT
	case .R32_Float: return .R32_FLOAT
	}

	log.error("Unknown format")
	return .UNKNOWN
}

shader_input_format_size :: proc(f: Shader_Input_Format) -> int {
	switch f {
	case .Unknown: return 0
	case .RGBA32_Float: return 32
	case .RGBA8_Norm: return 4
	case .RGBA8_Norm_SRGB: return 4
	case .RG32_Float: return 8
	case .R32_Float: return 4
	}

	return 0
}

d3d11_destroy_shader :: proc(shd: Shader) {
	if d3d_shd := hm.get(&s.shaders, shd.handle); d3d_shd != nil {
		d3d_shd.input_layout->Release()
		d3d_shd.vertex_shader->Release()
		d3d_shd.pixel_shader->Release()
	}
	hm.remove(&s.shaders, shd.handle)

	for c in shd.constant_buffers {
		if c.gpu_data != nil {
			c.gpu_data->Release()
		}

		delete(c.cpu_data)
	}

	delete(shd.constant_buffers)

	for k,_ in shd.constant_lookup {
		delete(k)
	}

	delete(shd.constant_lookup)
	for i in shd.inputs {
		delete(i.name)
	}
	delete(shd.inputs)
	delete(shd.input_overrides)
}

temp_cstring :: proc(str: string, loc := #caller_location) -> cstring {
	return strings.clone_to_cstring(str, context.temp_allocator, loc)
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
		msg_raw_ptr, _ := (mem.alloc(int(longest_msg), allocator = context.temp_allocator))

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