#+build windows

package karl2d
import "base:runtime"
import win32 "core:sys/windows"
import d3d11 "vendor:directx/d3d11"
import dxgi "vendor:directx/dxgi"
import "vendor:directx/d3d_compiler"
import "core:strings"
import "core:log"
import "core:math/linalg"
import "core:slice"
import "core:mem"
import "core:math"
import "core:image"

import "core:image/bmp"
import "core:image/png"
import "core:image/tga"

_ :: bmp
_ :: png
_ :: tga

_init :: proc(width: int, height: int, title: string,
              allocator := context.allocator, loc := #caller_location) -> ^State {
	s = new(State, allocator, loc)
	s.custom_context = context
	CLASS_NAME :: "karl2d"
	instance := win32.HINSTANCE(win32.GetModuleHandleW(nil))

	s.run = true
	s.width = width
	s.height = height

	cls := win32.WNDCLASSW {
		lpfnWndProc = window_proc,
		lpszClassName = CLASS_NAME,
		hInstance = instance,
		hCursor = win32.LoadCursorA(nil, win32.IDC_ARROW),
	}

	win32.RegisterClassW(&cls)

	r: win32.RECT
	r.right = i32(width)
	r.bottom = i32(height)

	style := win32.WS_OVERLAPPEDWINDOW | win32.WS_VISIBLE
	win32.AdjustWindowRect(&r, style, false)

	hwnd := win32.CreateWindowW(CLASS_NAME,
		win32.utf8_to_wstring(title),
		style,
		100, 10, r.right - r.left, r.bottom - r.top,
		nil, nil, instance, nil)

	assert(hwnd != nil, "Failed creating window")

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

	vs_blob: ^d3d11.IBlob
	vs_blob_errors: ^d3d11.IBlob
	ch(d3d_compiler.Compile(raw_data(shader_hlsl), len(shader_hlsl), "shader.hlsl", nil, nil, "vs_main", "vs_5_0", 0, 0, &vs_blob, &vs_blob_errors))

	if vs_blob_errors != nil {
		log.error("Failed compiling shader:")
		log.error(strings.string_from_ptr((^u8)(vs_blob_errors->GetBufferPointer()), int(vs_blob_errors->GetBufferSize())))
	}

	ch(s.device->CreateVertexShader(vs_blob->GetBufferPointer(), vs_blob->GetBufferSize(), nil, &s.vertex_shader))

	input_element_desc := [?]d3d11.INPUT_ELEMENT_DESC{
		{ "POS", 0, .R32G32_FLOAT,   0, 0,                            .VERTEX_DATA, 0 },
		{ "UV",  0, .R32G32_FLOAT,   0, d3d11.APPEND_ALIGNED_ELEMENT, .VERTEX_DATA, 0 },
		{ "COL", 0, .R8G8B8A8_UNORM, 0, d3d11.APPEND_ALIGNED_ELEMENT, .VERTEX_DATA, 0 },
	}

	ch(s.device->CreateInputLayout(&input_element_desc[0], len(input_element_desc), vs_blob->GetBufferPointer(), vs_blob->GetBufferSize(), &s.input_layout))

	ps_blob: ^d3d11.IBlob
	ps_blob_errors: ^d3d11.IBlob
	ch(d3d_compiler.Compile(raw_data(shader_hlsl), len(shader_hlsl), "shader.hlsl", nil, nil, "ps_main", "ps_5_0", 0, 0, &ps_blob, &ps_blob_errors))

	if ps_blob_errors != nil {
		log.error("Failed compiling shader:")
		log.error(strings.string_from_ptr((^u8)(ps_blob_errors->GetBufferPointer()), int(ps_blob_errors->GetBufferSize())))
	}

	ch(s.device->CreatePixelShader(ps_blob->GetBufferPointer(), ps_blob->GetBufferSize(), nil, &s.pixel_shader))

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

	constant_buffer_desc := d3d11.BUFFER_DESC{
		ByteWidth      = size_of(Constants),
		Usage          = .DYNAMIC,
		BindFlags      = {.CONSTANT_BUFFER},
		CPUAccessFlags = {.WRITE},
	}
	ch(s.device->CreateBuffer(&constant_buffer_desc, nil, &s.constant_buffer))

	vertex_buffer_desc := d3d11.BUFFER_DESC{
		ByteWidth = VERTEX_BUFFER_MAX * size_of(Vertex),
		Usage     = .DYNAMIC,
		BindFlags = {.VERTEX_BUFFER},
		CPUAccessFlags = {.WRITE},
	}
	ch(s.device->CreateBuffer(&vertex_buffer_desc, nil, &s.vertex_buffer_gpu))
	s.vertex_buffer_cpu = make([]Vertex, VERTEX_BUFFER_MAX)

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

	s.proj_matrix = make_default_projection(s.width, s.height)
	s.view_matrix = 1


	sampler_desc := d3d11.SAMPLER_DESC{
		Filter         = .MIN_MAG_MIP_POINT,
		AddressU       = .WRAP,
		AddressV       = .WRAP,
		AddressW       = .WRAP,
		ComparisonFunc = .NEVER,
	}
	s.device->CreateSamplerState(&sampler_desc, &s.sampler_state)

	white_rect: [16*16*4]u8
	slice.fill(white_rect[:], 255)
	s.shape_drawing_texture = _load_texture_from_memory(white_rect[:], 16, 16)

	return s
}

shader_hlsl :: #load("shader.hlsl")

Vertex :: struct {
	pos: Vec2,
	uv: Vec2,
	color: Color,
}

s: ^State

VERTEX_BUFFER_MAX :: 10000

State :: struct {
	swapchain: ^dxgi.ISwapChain1,
	framebuffer_view: ^d3d11.IRenderTargetView,
	depth_buffer_view: ^d3d11.IDepthStencilView,
	device_context: ^d3d11.IDeviceContext,
	constant_buffer: ^d3d11.IBuffer,
	vertex_shader: ^d3d11.IVertexShader,
	pixel_shader: ^d3d11.IPixelShader,
	depth_stencil_state: ^d3d11.IDepthStencilState,
	rasterizer_state: ^d3d11.IRasterizerState,
	input_layout: ^d3d11.IInputLayout,
	device: ^d3d11.IDevice,
	depth_buffer: ^d3d11.ITexture2D,
	framebuffer: ^d3d11.ITexture2D,
	blend_state: ^d3d11.IBlendState,
	shape_drawing_texture: Texture,

	// these need to be generalized
	sampler_state: ^d3d11.ISamplerState,

	set_tex: Texture,

	info_queue: ^d3d11.IInfoQueue,
	vertex_buffer_gpu: ^d3d11.IBuffer,
	vertex_buffer_cpu: []Vertex,
	vertex_buffer_cpu_count: int,

	vertex_buffer_offset: int,

	run: bool,
	custom_context: runtime.Context,

	camera: Maybe(Camera),
	width: int,
	height: int,

	keys_went_down: #sparse [Keyboard_Key]bool,
	keys_went_up: #sparse [Keyboard_Key]bool,
	keys_is_held: #sparse [Keyboard_Key]bool,

	view_matrix: matrix[4,4]f32,
	proj_matrix: matrix[4,4]f32,
}

VK_MAP := [255]Keyboard_Key {
	win32.VK_A = .A,
	win32.VK_B = .B,
	win32.VK_C = .C,
	win32.VK_D = .D,
	win32.VK_E = .E,
	win32.VK_F = .F,
	win32.VK_G = .G,
	win32.VK_H = .H,
	win32.VK_I = .I,
	win32.VK_J = .J,
	win32.VK_K = .K,
	win32.VK_L = .L,
	win32.VK_M = .M,
	win32.VK_N = .N,
	win32.VK_O = .O,
	win32.VK_P = .P,
	win32.VK_Q = .Q,
	win32.VK_R = .R,
	win32.VK_S = .S,
	win32.VK_T = .T,
	win32.VK_U = .U,
	win32.VK_V = .V,
	win32.VK_W = .W,
	win32.VK_X = .X,
	win32.VK_Y = .Y,
	win32.VK_Z = .Z,
	win32.VK_LEFT = .Left,
	win32.VK_RIGHT = .Right,
	win32.VK_UP = .Up,
	win32.VK_DOWN = .Down,
}

window_proc :: proc "stdcall" (hwnd: win32.HWND, msg: win32.UINT, wparam: win32.WPARAM, lparam: win32.LPARAM) -> win32.LRESULT {
	context = s.custom_context
	switch msg {
	case win32.WM_DESTROY:
		win32.PostQuitMessage(0)
		s.run = false

	case win32.WM_CLOSE:
		s.run = false

	case win32.WM_KEYDOWN:
		key := VK_MAP[wparam]
		s.keys_went_down[key] = true
		s.keys_is_held[key] = true

	case win32.WM_KEYUP:
		key := VK_MAP[wparam]
		s.keys_is_held[key] = false
		s.keys_went_up[key] = true
	}

	return win32.DefWindowProcW(hwnd, msg, wparam, lparam)
}

_shutdown :: proc() {
	_destroy_texture(s.shape_drawing_texture)
	s.sampler_state->Release()
	s.framebuffer_view->Release()
	s.depth_buffer_view->Release()
	s.depth_buffer->Release()
	s.framebuffer->Release()
	s.device_context->Release()
	s.vertex_buffer_gpu->Release()
	s.constant_buffer->Release()
	s.vertex_shader->Release()
	s.pixel_shader->Release()
	s.depth_stencil_state->Release()
	s.rasterizer_state->Release()
	s.input_layout->Release()
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

_set_internal_state :: proc(new_state: ^State) {
	s = new_state
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

_clear :: proc(color: Color) {
	c := f32_color_from_color(color)
	s.device_context->ClearRenderTargetView(s.framebuffer_view, &c)
	s.device_context->ClearDepthStencilView(s.depth_buffer_view, {.DEPTH}, 1, 0)
}

_Texture_Type :: struct {
	tex: ^d3d11.ITexture2D,
	view: ^d3d11.IShaderResourceView,
}



_load_texture_from_file :: proc(filename: string) -> Texture {
	img, img_err := image.load_from_file(filename, allocator = context.temp_allocator)

	if img_err != nil {
		log.errorf("Error loading texture %v: %v", filename, img_err)
		return {}
	}

	return _load_texture_from_memory(img.pixels.buf[:], img.width, img.height)
}

_load_texture_from_memory :: proc(data: []u8, width: int, height: int) -> Texture {
	texture_desc := d3d11.TEXTURE2D_DESC{
		Width      = u32(width),
		Height     = u32(height),
		MipLevels  = 1,
		ArraySize  = 1,
		// TODO: _SRGB or not?
		Format     = .R8G8B8A8_UNORM_SRGB,
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
	return {
		id = {
			tex = texture,
			view = texture_view,
		},
		width = width,
		height = height,
	}
}

_destroy_texture :: proc(tex: Texture) {
	tex.id.tex->Release()
	tex.id.view->Release()
}

_draw_texture :: proc(tex: Texture, pos: Vec2, tint := WHITE) {
	_draw_texture_ex(
		tex,
		{0, 0, f32(tex.width), f32(tex.height)},
		{pos.x, pos.y, f32(tex.width), f32(tex.height)},
		{},
		0,
		tint,
	)
}

_draw_texture_rect :: proc(tex: Texture, rect: Rect, pos: Vec2, tint := WHITE) {
	_draw_texture_ex(
		tex,
		rect,
		{pos.x, pos.y, rect.w, rect.h},
		{},
		0,
		tint,
	)
}

batch_vertex :: proc(v: Vec2, uv: Vec2, color: Color) {
	v := v

	if s.vertex_buffer_cpu_count == len(s.vertex_buffer_cpu) {
		panic("Must dispatch here")
	}

	s.vertex_buffer_cpu[s.vertex_buffer_cpu_count] = {
		pos = v,
		uv = uv,
		color = color,
	}

	s.vertex_buffer_cpu_count += 1
}

_draw_texture_ex :: proc(tex: Texture, src: Rect, dst: Rect, origin: Vec2, rot: f32, tint := WHITE) {
	if tex.width == 0 || tex.height == 0 || tex.id.tex == nil {
		return
	}

	if s.set_tex.id.tex != nil && s.set_tex.id.tex != tex.id.tex {
		maybe_draw_current_batch()
	}

	r := dst

	r.x -= origin.x
	r.y -= origin.y

	s.set_tex = tex
	tl, tr, bl, br: Vec2

	// Rotation adapted from Raylib's "DrawTexturePro"
	if rot == 0 {
		x := dst.x - origin.x
		y := dst.y - origin.y
		tl = { x,         y }
		tr = { x + dst.w, y }
		bl = { x,         y + dst.h }
		br = { x + dst.w, y + dst.h }
	} else {
		sin_rot := math.sin(rot * math.RAD_PER_DEG)
		cos_rot := math.cos(rot * math.RAD_PER_DEG)
		x := dst.x
		y := dst.y
		dx := -origin.x
		dy := -origin.y

		tl = {
			x + dx * cos_rot - dy * sin_rot,
			y + dx * sin_rot + dy * cos_rot,
		}

		tr = {
			x + (dx + dst.w) * cos_rot - dy * sin_rot,
			y + (dx + dst.w) * sin_rot + dy * cos_rot,
		}

		bl = {
			x + dx * cos_rot - (dy + dst.h) * sin_rot,
			y + dx * sin_rot + (dy + dst.h) * cos_rot,
		}

		br = {
			x + (dx + dst.w) * cos_rot - (dy + dst.h) * sin_rot,
			y + (dx + dst.w) * sin_rot + (dy + dst.h) * cos_rot,
		}
	}
	
	ts := Vec2{f32(tex.width), f32(tex.height)}
	up := Vec2{src.x, src.y} / ts
	us := Vec2{src.w, src.h} / ts
	c := tint
	batch_vertex(tl, up, c)
	batch_vertex(tr, up + {us.x, 0}, c)
	batch_vertex(br, up + us, c)
	batch_vertex(tl, up, c)
	batch_vertex(br, up + us, c)
	batch_vertex(bl, up + {0, us.y}, c)
}

_draw_rectangle :: proc(r: Rect, c: Color) {
	if s.set_tex.id.tex != nil && s.set_tex.id.tex != s.shape_drawing_texture.id.tex {
		maybe_draw_current_batch()
	}

	s.set_tex = s.shape_drawing_texture

	batch_vertex({r.x, r.y}, {0, 0}, c)
	batch_vertex({r.x + r.w, r.y}, {1, 0}, c)
	batch_vertex({r.x + r.w, r.y + r.h}, {1, 1}, c)
	batch_vertex({r.x, r.y}, {0, 0}, c)
	batch_vertex({r.x + r.w, r.y + r.h}, {1, 1}, c)
	batch_vertex({r.x, r.y + r.h}, {0, 1}, c)
}

_draw_rectangle_outline :: proc(r: Rect, thickness: f32, color: Color) {
	t := thickness
	
	// Based on DrawRectangleLinesEx from Raylib

	top := Rect {
		r.x,
		r.y,
		r.w,
		t,
	}

	bottom := Rect {
		r.x,
		r.y + r.h - t,
		r.w,
		t,
	}

	left := Rect {
		r.x,
		r.y + t,
		t,
		r.h - t * 2,
	}

	right := Rect {
		r.x + r.w - t,
		r.y + t,
		t,
		r.h - t * 2,
	}

	_draw_rectangle(top, color)
	_draw_rectangle(bottom, color)
	_draw_rectangle(left, color)
	_draw_rectangle(right, color)
}

_draw_circle :: proc(center: Vec2, radius: f32, color: Color) {
}

_draw_line :: proc(start: Vec2, end: Vec2, thickness: f32, color: Color) {
}

_get_screen_width :: proc() -> int {
	return 0
}

_get_screen_height :: proc() -> int {
	return 0
}

_key_went_down :: proc(key: Keyboard_Key) -> bool {
	return s.keys_went_down[key]
}

_key_went_up :: proc(key: Keyboard_Key) -> bool {
	return s.keys_went_up[key]
}

_key_is_held :: proc(key: Keyboard_Key) -> bool {
	return s.keys_is_held[key]
}

_window_should_close :: proc() -> bool {
	return !s.run
}

_draw_text :: proc(text: string, pos: Vec2, font_size: f32, color: Color) {
}

_mouse_button_pressed  :: proc(button: Mouse_Button) -> bool {
	return false
}

_mouse_button_released :: proc(button: Mouse_Button) -> bool {
	return false
}

_mouse_button_held     :: proc(button: Mouse_Button) -> bool {
	return false
}

_mouse_wheel_delta :: proc() -> f32 {
	return 0
}

_mouse_position :: proc() -> Vec2 {
	return {}
}

_enable_scissor :: proc(x, y, w, h: int) {
}

_disable_scissor :: proc() {
}

_set_window_size :: proc(width: int, height: int) {
}

_set_window_position :: proc(x: int, y: int) {
}

_screen_to_world :: proc(pos: Vec2, camera: Camera) -> Vec2 {
	return pos
}

Vec3 :: [3]f32

vec3_from_vec2 :: proc(v: Vec2) -> Vec3 {
	return {
		v.x, v.y, 0,
	}
}

_set_camera :: proc(camera: Maybe(Camera)) {
	if camera == s.camera {
		return
	}

	s.camera = camera
	maybe_draw_current_batch()

	if c, c_ok := camera.?; c_ok {
		origin_trans :=linalg.matrix4_translate(vec3_from_vec2(-c.origin))
		translate := linalg.matrix4_translate(vec3_from_vec2(c.target))
		rot := linalg.matrix4_rotate_f32(c.rotation * math.RAD_PER_DEG, {0, 0, 1})
		camera_matrix := translate * rot * origin_trans
		s.view_matrix = linalg.inverse(camera_matrix)

		s.proj_matrix = make_default_projection(s.width, s.height)
		s.proj_matrix[0, 0] *= c.zoom
		s.proj_matrix[1, 1] *= c.zoom
	} else {
		s.proj_matrix = make_default_projection(s.width, s.height)
		s.view_matrix = 1
	}
}

_set_scissor_rect :: proc(scissor_rect: Maybe(Rect)) {

}

_set_shader :: proc(shader: Maybe(Shader)) {

}

_process_events :: proc() {
	s.keys_went_up = {}
	s.keys_went_down = {}

	msg: win32.MSG

	for win32.PeekMessageW(&msg, nil, 0, 0, win32.PM_REMOVE) {
		win32.TranslateMessage(&msg)
		win32.DispatchMessageW(&msg)			
	}
}

maybe_draw_current_batch :: proc() {
	if s.vertex_buffer_cpu_count == 0 {
		return
	}

	_draw_current_batch()
}

_draw_current_batch :: proc() {
	viewport := d3d11.VIEWPORT{
		0, 0,
		f32(s.width), f32(s.height),
		0, 1,
	}

	dc := s.device_context

	vb_data: d3d11.MAPPED_SUBRESOURCE
	ch(dc->Map(s.vertex_buffer_gpu, 0, .WRITE_NO_OVERWRITE, {}, &vb_data))
	{
		gpu_map := slice.from_ptr((^Vertex)(vb_data.pData), VERTEX_BUFFER_MAX)
		copy(
			gpu_map[s.vertex_buffer_offset:s.vertex_buffer_cpu_count],
			s.vertex_buffer_cpu[s.vertex_buffer_offset:s.vertex_buffer_cpu_count],
		)
	}
	dc->Unmap(s.vertex_buffer_gpu, 0)

	cb_data: d3d11.MAPPED_SUBRESOURCE
	ch(dc->Map(s.constant_buffer, 0, .WRITE_DISCARD, {}, &cb_data))
	{
		constants := (^Constants)(cb_data.pData)
		constants.mvp = s.proj_matrix * s.view_matrix
	}
	dc->Unmap(s.constant_buffer, 0)

	dc->IASetPrimitiveTopology(.TRIANGLELIST)
	dc->IASetInputLayout(s.input_layout)
	vertex_buffer_offset := u32(0)
	vertex_buffer_stride := u32(size_of(Vertex))
	dc->IASetVertexBuffers(0, 1, &s.vertex_buffer_gpu, &vertex_buffer_stride, &vertex_buffer_offset)

	dc->VSSetShader(s.vertex_shader, nil, 0)
	dc->VSSetConstantBuffers(0, 1, &s.constant_buffer)

	dc->RSSetViewports(1, &viewport)
	dc->RSSetState(s.rasterizer_state)

	dc->PSSetShader(s.pixel_shader, nil, 0)
	dc->PSSetShaderResources(0, 1, &s.set_tex.id.view)
	dc->PSSetSamplers(0, 1, &s.sampler_state)

	dc->OMSetRenderTargets(1, &s.framebuffer_view, s.depth_buffer_view)
	dc->OMSetDepthStencilState(s.depth_stencil_state, 0)
	dc->OMSetBlendState(s.blend_state, nil, ~u32(0))

	dc->Draw(u32(s.vertex_buffer_cpu_count - s.vertex_buffer_offset), u32(s.vertex_buffer_offset))
	s.vertex_buffer_offset = s.vertex_buffer_cpu_count
	log_messages()
}

Constants :: struct #align (16) {
	mvp: matrix[4, 4]f32,
}

make_default_projection :: proc(w, h: int) -> matrix[4,4]f32 {
	return linalg.matrix_ortho3d_f32(0, f32(w), f32(h), 0, 0.001, 2)
}

_present :: proc() {
	maybe_draw_current_batch()
	ch(s.swapchain->Present(1, {}))
	s.vertex_buffer_offset = 0
	s.vertex_buffer_cpu_count = 0
}

_load_shader :: proc(vs: string, fs: string) -> Shader {
	return {}
}

_destroy_shader :: proc(shader: Shader) {
}

_get_shader_location :: proc(shader: Shader, uniform_name: string) -> int {
	return 0
}

_set_shader_value_f32 :: proc(shader: Shader, loc: int, val: f32) {
}

_set_shader_value_vec2 :: proc(shader: Shader, loc: int, val: Vec2) {
}

temp_cstring :: proc(str: string, loc := #caller_location) -> cstring {
	return strings.clone_to_cstring(str, context.temp_allocator, loc)
}

// CHeck win errors and print message log if there is any error
ch :: proc(hr: win32.HRESULT, loc := #caller_location) -> win32.HRESULT {
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