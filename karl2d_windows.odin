#+build windows

package karl2d
import "base:runtime"
import win "core:sys/windows"
import D3D11 "vendor:directx/d3d11"
import DXGI "vendor:directx/dxgi"
import D3D "vendor:directx/d3d_compiler"
import "core:strings"
import "core:log"
import "core:math/linalg"
import "core:slice"
import "core:mem"

_init :: proc(width: int, height: int, title: string,
              allocator := context.allocator, loc := #caller_location) -> ^State {
	s = new(State, allocator, loc)
	s.custom_context = context
	CLASS_NAME :: "karl2d"
	instance := win.HINSTANCE(win.GetModuleHandleW(nil))

	s.run = true
	s.width = width
	s.height = height

	cls := win.WNDCLASSW {
		lpfnWndProc = window_proc,
		lpszClassName = CLASS_NAME,
		hInstance = instance,
		hCursor = win.LoadCursorA(nil, win.IDC_ARROW),
	}

	win.RegisterClassW(&cls)

	r: win.RECT
	r.right = i32(width)
	r.bottom = i32(height)

	style := win.WS_OVERLAPPEDWINDOW | win.WS_VISIBLE
	win.AdjustWindowRect(&r, style, false)

	hwnd := win.CreateWindowW(CLASS_NAME,
		win.utf8_to_wstring(title),
		style,
		100, 10, r.right - r.left, r.bottom - r.top,
		nil, nil, instance, nil)

	assert(hwnd != nil, "Failed creating window")

	feature_levels := [?]D3D11.FEATURE_LEVEL{
		._11_1,
		._11_0,
	}

	base_device: ^D3D11.IDevice
	base_device_context: ^D3D11.IDeviceContext

	device_flags := D3D11.CREATE_DEVICE_FLAGS {
		.BGRA_SUPPORT,
	}

	when ODIN_DEBUG {
		device_flags += { .DEBUG }
	}

	ch(D3D11.CreateDevice(
		nil,
		.HARDWARE,
		nil,
		device_flags,
		&feature_levels[0], len(feature_levels),
		D3D11.SDK_VERSION, &base_device, nil, &base_device_context))

	ch(base_device->QueryInterface(D3D11.IInfoQueue_UUID, (^rawptr)(&s.info_queue)))
	ch(base_device->QueryInterface(D3D11.IDevice_UUID, (^rawptr)(&s.device)))
	ch(base_device_context->QueryInterface(D3D11.IDeviceContext_UUID, (^rawptr)(&s.device_context)))
	dxgi_device: ^DXGI.IDevice
	ch(s.device->QueryInterface(DXGI.IDevice_UUID, (^rawptr)(&dxgi_device)))
	base_device->Release()
	base_device_context->Release()

	dxgi_adapter: ^DXGI.IAdapter
	
	ch(dxgi_device->GetAdapter(&dxgi_adapter))
	dxgi_device->Release()

	dxgi_factory: ^DXGI.IFactory2
	ch(dxgi_adapter->GetParent(DXGI.IFactory2_UUID, (^rawptr)(&dxgi_factory)))

	swapchain_desc := DXGI.SWAP_CHAIN_DESC1 {
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
	ch(s.swapchain->GetBuffer(0, D3D11.ITexture2D_UUID, (^rawptr)(&s.framebuffer)))
	ch(s.device->CreateRenderTargetView(s.framebuffer, nil, &s.framebuffer_view))

	depth_buffer_desc: D3D11.TEXTURE2D_DESC
	s.framebuffer->GetDesc(&depth_buffer_desc)
	depth_buffer_desc.Format = .D24_UNORM_S8_UINT
	depth_buffer_desc.BindFlags = {.DEPTH_STENCIL}

	ch(s.device->CreateTexture2D(&depth_buffer_desc, nil, &s.depth_buffer))
	ch(s.device->CreateDepthStencilView(s.depth_buffer, nil, &s.depth_buffer_view))

	vs_blob: ^D3D11.IBlob
	vs_blob_errors: ^D3D11.IBlob
	ch(D3D.Compile(raw_data(shader_hlsl), len(shader_hlsl), "shader.hlsl", nil, nil, "vs_main", "vs_5_0", 0, 0, &vs_blob, &vs_blob_errors))

	if vs_blob_errors != nil {
		log.error("Failed compiling shader:")
		log.error(strings.string_from_ptr((^u8)(vs_blob_errors->GetBufferPointer()), int(vs_blob_errors->GetBufferSize())))
	}

	ch(s.device->CreateVertexShader(vs_blob->GetBufferPointer(), vs_blob->GetBufferSize(), nil, &s.vertex_shader))

	input_element_desc := [?]D3D11.INPUT_ELEMENT_DESC{
		{ "POS", 0, .R32G32_FLOAT, 0, 0, .VERTEX_DATA, 0 },
		{ "COL", 0, .R8G8B8A8_UNORM , 0, D3D11.APPEND_ALIGNED_ELEMENT, .VERTEX_DATA, 0 },
	}

	ch(s.device->CreateInputLayout(&input_element_desc[0], len(input_element_desc), vs_blob->GetBufferPointer(), vs_blob->GetBufferSize(), &s.input_layout))

	ps_blob: ^D3D11.IBlob
	ps_blob_errors: ^D3D11.IBlob
	ch(D3D.Compile(raw_data(shader_hlsl), len(shader_hlsl), "shader.hlsl", nil, nil, "ps_main", "ps_5_0", 0, 0, &ps_blob, &ps_blob_errors))

	if ps_blob_errors != nil {
		log.error("Failed compiling shader:")
		log.error(strings.string_from_ptr((^u8)(ps_blob_errors->GetBufferPointer()), int(ps_blob_errors->GetBufferSize())))
	}

	ch(s.device->CreatePixelShader(ps_blob->GetBufferPointer(), ps_blob->GetBufferSize(), nil, &s.pixel_shader))

	rasterizer_desc := D3D11.RASTERIZER_DESC{
		FillMode = .SOLID,
		CullMode = .BACK,
	}
	ch(s.device->CreateRasterizerState(&rasterizer_desc, &s.rasterizer_state))

	depth_stencil_desc := D3D11.DEPTH_STENCIL_DESC{
		DepthEnable    = false,
		DepthWriteMask = .ALL,
		DepthFunc      = .LESS,
	}
	ch(s.device->CreateDepthStencilState(&depth_stencil_desc, &s.depth_stencil_state))

	constant_buffer_desc := D3D11.BUFFER_DESC{
		ByteWidth      = size_of(Constants),
		Usage          = .DYNAMIC,
		BindFlags      = {.CONSTANT_BUFFER},
		CPUAccessFlags = {.WRITE},
	}
	ch(s.device->CreateBuffer(&constant_buffer_desc, nil, &s.constant_buffer))

	vertex_buffer_desc := D3D11.BUFFER_DESC{
		ByteWidth = VERTEX_BUFFER_MAX * size_of(Vertex),
		Usage     = .DYNAMIC,
		BindFlags = {.VERTEX_BUFFER},
		CPUAccessFlags = {.WRITE},
	}
	ch(s.device->CreateBuffer(&vertex_buffer_desc, nil, &s.vertex_buffer_gpu))
	s.vertex_buffer_cpu = make([]Vertex, VERTEX_BUFFER_MAX)
	s.proj_matrix = make_default_projection(s.width, s.height)
	return s
}



shader_hlsl :: #load("shader.hlsl")

Vertex :: struct {
	pos: Vec2,
	color: Color,
}

s: ^State

VERTEX_BUFFER_MAX :: 10000

State :: struct {
	swapchain: ^DXGI.ISwapChain1,
	framebuffer_view: ^D3D11.IRenderTargetView,
	depth_buffer_view: ^D3D11.IDepthStencilView,
	device_context: ^D3D11.IDeviceContext,
	constant_buffer: ^D3D11.IBuffer,
	vertex_shader: ^D3D11.IVertexShader,
	pixel_shader: ^D3D11.IPixelShader,
	depth_stencil_state: ^D3D11.IDepthStencilState,
	rasterizer_state: ^D3D11.IRasterizerState,
	input_layout: ^D3D11.IInputLayout,
	device: ^D3D11.IDevice,
	depth_buffer: ^D3D11.ITexture2D,
	framebuffer: ^D3D11.ITexture2D,

	info_queue: ^D3D11.IInfoQueue,
	vertex_buffer_gpu: ^D3D11.IBuffer,
	vertex_buffer_cpu: []Vertex,
	vertex_buffer_cpu_count: int,

	run: bool,
	custom_context: runtime.Context,

	width: int,
	height: int,

	keys_went_down: #sparse [Keyboard_Key]bool,
	keys_went_up: #sparse [Keyboard_Key]bool,
	keys_is_held: #sparse [Keyboard_Key]bool,

	proj_matrix: matrix[4,4]f32,
}

VK_MAP := [255]Keyboard_Key {
	win.VK_A = .A,
	win.VK_B = .B,
	win.VK_C = .C,
	win.VK_D = .D,
	win.VK_E = .E,
	win.VK_F = .F,
	win.VK_G = .G,
	win.VK_H = .H,
	win.VK_I = .I,
	win.VK_J = .J,
	win.VK_K = .K,
	win.VK_L = .L,
	win.VK_M = .M,
	win.VK_N = .N,
	win.VK_O = .O,
	win.VK_P = .P,
	win.VK_Q = .Q,
	win.VK_R = .R,
	win.VK_S = .S,
	win.VK_T = .T,
	win.VK_U = .U,
	win.VK_V = .V,
	win.VK_W = .W,
	win.VK_X = .X,
	win.VK_Y = .Y,
	win.VK_Z = .Z,
	win.VK_LEFT = .Left,
	win.VK_RIGHT = .Right,
	win.VK_UP = .Up,
	win.VK_DOWN = .Down,
}

window_proc :: proc "stdcall" (hwnd: win.HWND, msg: win.UINT, wparam: win.WPARAM, lparam: win.LPARAM) -> win.LRESULT {
	context = s.custom_context
	switch msg {
	case win.WM_DESTROY:
		win.PostQuitMessage(0)
		s.run = false

	case win.WM_CLOSE:
		s.run = false

	case win.WM_KEYDOWN:
		key := VK_MAP[wparam]
		s.keys_went_down[key] = true
		s.keys_is_held[key] = true

	case win.WM_KEYUP:
		key := VK_MAP[wparam]
		s.keys_is_held[key] = false
		s.keys_went_up[key] = true
	}

	return win.DefWindowProcW(hwnd, msg, wparam, lparam)
}

_shutdown :: proc() {
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

	when ODIN_DEBUG {
		debug: ^D3D11.IDebug

		if ch(s.device->QueryInterface(D3D11.IDebug_UUID, (^rawptr)(&debug))) >= 0 {
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

_load_texture :: proc(filename: string) -> Texture {
	return {}
}

_destroy_texture :: proc(tex: Texture) {

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

add_vertex :: proc(v: Vec2, color: Color) {
	if s.vertex_buffer_cpu_count == len(s.vertex_buffer_cpu) {
		panic("Must dispatch here")
	}

	s.vertex_buffer_cpu[s.vertex_buffer_cpu_count] = {
		pos = v,
		color = color,
	}

	s.vertex_buffer_cpu_count += 1
}

_draw_texture_ex :: proc(tex: Texture, src: Rect, dst: Rect, origin: Vec2, rot: f32, tint := WHITE) {
	p := Vec2 {
		dst.x, dst.y,
	}

	p -= origin

	add_vertex({p.x, p.y}, tint)
	add_vertex({p.x + dst.w, p.y}, tint)
	add_vertex({p.x + dst.w, p.y + dst.h}, tint)
	add_vertex({p.x, p.y}, tint)
	add_vertex({p.x + dst.w, p.y + dst.h}, tint)
	add_vertex({p.x, p.y + dst.h}, tint)
}

_draw_rectangle :: proc(r: Rect, color: Color) {
	add_vertex({r.x, r.y}, color)
	add_vertex({r.x + r.w, r.y}, color)
	add_vertex({r.x + r.w, r.y + r.h}, color)
	add_vertex({r.x, r.y}, color)
	add_vertex({r.x + r.w, r.y + r.h}, color)
	add_vertex({r.x, r.y + r.h}, color)
}

_draw_rectangle_outline :: proc(rect: Rect, thickness: f32, color: Color) {
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

_set_camera :: proc(camera: Maybe(Camera)) {
	if c, c_ok := camera.?; c_ok {
		s.proj_matrix = make_default_projection(s.width, s.height)
		s.proj_matrix[0, 0] *= c.zoom
		s.proj_matrix[1, 1] *= c.zoom
	} else {
		s.proj_matrix = make_default_projection(s.width, s.height)
	}
}

_set_scissor_rect :: proc(scissor_rect: Maybe(Rect)) {

}

_set_shader :: proc(shader: Maybe(Shader)) {

}

_process_events :: proc() {
	s.keys_went_up = {}
	s.keys_went_down = {}

	msg: win.MSG

	for win.PeekMessageW(&msg, nil, 0, 0, win.PM_REMOVE) {
		win.TranslateMessage(&msg)
		win.DispatchMessageW(&msg)			
	}
}

_flush :: proc() {
}

Constants :: struct #align (16) {
	projection: matrix[4, 4]f32,
}

make_default_projection :: proc(w, h: int) -> matrix[4,4]f32 {
	return linalg.matrix_ortho3d_f32(0, f32(w), f32(h), 0, 0.001, 2)
}

_present :: proc(do_flush := true) {
	viewport := D3D11.VIEWPORT{
		0, 0,
		f32(s.width), f32(s.height),
		0, 1,
	}

	dc := s.device_context

	vb_data: D3D11.MAPPED_SUBRESOURCE
	ch(dc->Map(s.vertex_buffer_gpu, 0, .WRITE_NO_OVERWRITE, {}, &vb_data))
	{
		gpu_map := slice.from_ptr((^Vertex)(vb_data.pData), VERTEX_BUFFER_MAX)
		copy(gpu_map, s.vertex_buffer_cpu[:s.vertex_buffer_cpu_count])
	}
	dc->Unmap(s.vertex_buffer_gpu, 0)

	cb_data: D3D11.MAPPED_SUBRESOURCE
	ch(dc->Map(s.constant_buffer, 0, .WRITE_DISCARD, {}, &cb_data))
	{
		constants := (^Constants)(cb_data.pData)
		constants.projection = s.proj_matrix
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

	dc->OMSetRenderTargets(1, &s.framebuffer_view, s.depth_buffer_view)
	dc->OMSetDepthStencilState(s.depth_stencil_state, 0)
	dc->OMSetBlendState(nil, nil, ~u32(0)) // use default blend mode (i.e. disable)

	dc->Draw(u32(s.vertex_buffer_cpu_count), 0)
	log_messages()

	ch(s.swapchain->Present(1, {}))

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
	return strings.clone_to_cstring(str, context.temp_allocator)
}

// CHeck win errors and print message log if there is any error
ch :: proc(hr: win.HRESULT, loc := #caller_location) -> win.HRESULT {
	if hr >= 0 {
		return hr
	}

	log.errorf("D3D11 error: %0x", u32(hr), location = loc)
	log_messages(loc)
	return hr
}

log_messages :: proc(loc := #caller_location) {
	iq := s.info_queue
	
	if iq == nil {
		return
	}

	n := iq->GetNumStoredMessages()
	longest_msg: D3D11.SIZE_T

	for i in 0..=n {
		msglen: D3D11.SIZE_T
		iq->GetMessage(i, nil, &msglen)

		if msglen > longest_msg {
			longest_msg = msglen
		}
	}

	if longest_msg > 0 {
		msg_raw_ptr, _ := (mem.alloc(int(longest_msg), allocator = context.temp_allocator))

		for i in 0..=n {
			msglen: D3D11.SIZE_T
			iq->GetMessage(i, nil, &msglen)

			if msglen > 0 {
				msg := (^D3D11.MESSAGE)(msg_raw_ptr)
				iq->GetMessage(i, msg, &msglen)
				log.error(msg.pDescription, location = loc)
			}
		}
	}

	iq->ClearStoredMessages()
}