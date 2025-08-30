package karl2d

import win32 "core:sys/windows"
import "base:runtime"
import "core:mem"
import "core:log"
import "core:math"
import "core:math/linalg"
import "core:slice"

import "core:image"
import "core:image/bmp"
import "core:image/png"
import "core:image/tga"

import hm "handle_map"

_ :: bmp
_ :: png
_ :: tga

Handle :: hm.Handle
Texture_Handle :: distinct Handle

// Opens a window and initializes some internal state. The internal state will use `allocator` for
// all dynamically allocated memory. The return value can be ignored unless you need to later call
// `set_state`.
init :: proc(window_width: int, window_height: int, window_title: string,
             allocator := context.allocator, loc := #caller_location) -> ^State {
	win32.SetProcessDPIAware()
	s = new(State, allocator, loc)
	s.allocator = allocator
	s.custom_context = context

	CLASS_NAME :: "karl2d"
	instance := win32.HINSTANCE(win32.GetModuleHandleW(nil))

	s.run = true
	s.width = window_width
	s.height = window_height

	cls := win32.WNDCLASSW {
		lpfnWndProc = window_proc,
		lpszClassName = CLASS_NAME,
		hInstance = instance,
		hCursor = win32.LoadCursorA(nil, win32.IDC_ARROW),
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

	win32.RegisterClassW(&cls)

	r: win32.RECT
	r.right = i32(window_width)
	r.bottom = i32(window_height)

	style := win32.WS_OVERLAPPEDWINDOW | win32.WS_VISIBLE
	win32.AdjustWindowRect(&r, style, false)

	hwnd := win32.CreateWindowW(CLASS_NAME,
		win32.utf8_to_wstring(window_title),
		style,
		100, 10, r.right - r.left, r.bottom - r.top,
		nil, nil, instance, nil)

	s.window = hwnd

	assert(hwnd != nil, "Failed creating window")

	s.rb = BACKEND_D3D11
	rb_alloc_error: runtime.Allocator_Error
	s.rb_state, rb_alloc_error = mem.alloc(s.rb.state_size())
	log.assertf(rb_alloc_error == nil, "Failed allocating memory for rendering backend: %v", rb_alloc_error)
	s.proj_matrix = make_default_projection(window_width, window_height)
	s.view_matrix = 1
	s.rb.init(s.rb_state, uintptr(hwnd), window_width, window_height, allocator, loc)
	white_rect: [16*16*4]u8
	slice.fill(white_rect[:], 255)
	s.shape_drawing_texture = s.rb.load_texture(white_rect[:], 16, 16)
	return s
}

// Closes the window and cleans up the internal state.
shutdown :: proc() {
	s.rb.destroy_texture(s.shape_drawing_texture)
	s.rb.shutdown()

	win32.DestroyWindow(s.window)

	a := s.allocator
	free(s.rb_state, a)
	free(s, a)
	s = nil
}

// Clear the backbuffer with supplied color.
clear :: proc(color: Color) {
	s.rb.clear(color)
}

// Present the backbuffer. Call at end of frame to make everything you've drawn appear on the screen.
present :: proc() {
	s.rb.present()
}

// Call at start or end of frame to process all events that have arrived to the window.
//
// WARNING: Not calling this will make your program impossible to interact with.
process_events :: proc() {
	s.keys_went_up = {}
	s.keys_went_down = {}

	msg: win32.MSG

	for win32.PeekMessageW(&msg, nil, 0, 0, win32.PM_REMOVE) {
		win32.TranslateMessage(&msg)
		win32.DispatchMessageW(&msg)			
	}
}

/* Flushes the current batch. This sends off everything to the GPU that has been queued in the
current batch. Normally, you do not need to do this manually. It is done automatically when these
procedures run:
	present
	set_camera
	set_shader

TODO: complete this list and motivate why it needs to happen on those procs (or do that in the
docs for those procs).
*/   
draw_current_batch :: proc() {
	s.rb.draw_current_batch()
}

// Can be used to restore the internal state using the pointer returned by `init`. Useful after
// reloading the library (for example, when doing code hot reload).
set_internal_state :: proc(state: ^State) {
	s = state
	s.rb.set_internal_state(s.rb_state)
}

get_screen_width :: proc() -> int {
	return s.rb.get_swapchain_width()
}

get_screen_height :: proc() -> int  {
	return s.rb.get_swapchain_height()
}

key_went_down :: proc(key: Keyboard_Key) -> bool {
	return s.keys_went_down[key]
}

key_went_up :: proc(key: Keyboard_Key) -> bool {
	return s.keys_went_up[key]
}

key_is_held :: proc(key: Keyboard_Key) -> bool {
	return s.keys_is_held[key]
}

// Returns true if the user has tried to close the window.
window_should_close :: proc() -> bool {
	return !s.run
}

set_window_position :: proc(x: int, y: int) {
	// TODO: Does x, y respect monitor DPI?

	win32.SetWindowPos(
		s.window,
		{},
		i32(x),
		i32(y),
		0,
		0,
		win32.SWP_NOACTIVATE | win32.SWP_NOZORDER | win32.SWP_NOSIZE,
	)
}

set_window_size :: proc(width: int, height: int) {
	panic("Not implemented")
}

set_camera :: proc(camera: Maybe(Camera)) {
	if camera == s.batch_camera {
		return
	}

	s.rb.draw_current_batch()
	s.batch_camera = camera
	s.proj_matrix = make_default_projection(s.width, s.height)

	if c, c_ok := camera.?; c_ok {
		origin_trans := linalg.matrix4_translate(vec3_from_vec2(-c.origin))
		translate := linalg.matrix4_translate(vec3_from_vec2(c.target))
		rot := linalg.matrix4_rotate_f32(c.rotation * math.RAD_PER_DEG, {0, 0, 1})
		camera_matrix := translate * rot * origin_trans
		s.view_matrix = linalg.inverse(camera_matrix)
		
		s.proj_matrix[0, 0] *= c.zoom
		s.proj_matrix[1, 1] *= c.zoom
	} else {
		s.view_matrix = 1
	}

	s.rb.set_view_projection_matrix(s.proj_matrix * s.view_matrix)
}

load_texture_from_file :: proc(filename: string) -> Texture {
	img, img_err := image.load_from_file(filename, options = {.alpha_add_if_missing}, allocator = context.temp_allocator)

	if img_err != nil {
		log.errorf("Error loading texture %v: %v", filename, img_err)
		return {}
	}

	backend_tex := s.rb.load_texture(img.pixels.buf[:], img.width, img.height)

	return {
		handle = backend_tex,
		width = img.width,
		height = img.height,
	}
}

destroy_texture :: proc(tex: Texture) {
	s.rb.destroy_texture(tex.handle)
}

draw_rect :: proc(r: Rect, c: Color) {
	if s.batch_texture != TEXTURE_NONE && s.batch_texture != s.shape_drawing_texture {
		s.rb.draw_current_batch()
	}

	s.batch_texture = s.shape_drawing_texture
	_tmp_set_batch_texture(s.batch_texture)

	s.rb.batch_vertex({r.x, r.y}, {0, 0}, c)
	s.rb.batch_vertex({r.x + r.w, r.y}, {1, 0}, c)
	s.rb.batch_vertex({r.x + r.w, r.y + r.h}, {1, 1}, c)
	s.rb.batch_vertex({r.x, r.y}, {0, 0}, c)
	s.rb.batch_vertex({r.x + r.w, r.y + r.h}, {1, 1}, c)
	s.rb.batch_vertex({r.x, r.y + r.h}, {0, 1}, c)
}

draw_rect_outline :: proc(r: Rect, thickness: f32, color: Color) {
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

	draw_rect(top, color)
	draw_rect(bottom, color)
	draw_rect(left, color)
	draw_rect(right, color)
}

draw_texture :: proc(tex: Texture, pos: Vec2, tint := WHITE) {
	draw_texture_ex(
		tex,
		{0, 0, f32(tex.width), f32(tex.height)},
		{pos.x, pos.y, f32(tex.width), f32(tex.height)},
		{},
		0,
		tint,
	)
}

draw_texture_rect :: proc(tex: Texture, rect: Rect, pos: Vec2, tint := WHITE) {
	draw_texture_ex(
		tex,
		rect,
		{pos.x, pos.y, rect.w, rect.h},
		{},
		0,
		tint,
	)
}

draw_texture_ex :: proc(tex: Texture, src: Rect, dst: Rect, origin: Vec2, rotation: f32, tint := WHITE) {
	if tex.width == 0 || tex.height == 0 {
		return
	}

	if s.batch_texture != TEXTURE_NONE && s.batch_texture != tex.handle {
		s.rb.draw_current_batch()
	}

	r := dst

	r.x -= origin.x
	r.y -= origin.y

	s.batch_texture = tex.handle
	_tmp_set_batch_texture(tex.handle)
	tl, tr, bl, br: Vec2

	// Rotation adapted from Raylib's "DrawTexturePro"
	if rotation == 0 {
		x := dst.x - origin.x
		y := dst.y - origin.y
		tl = { x,         y }
		tr = { x + dst.w, y }
		bl = { x,         y + dst.h }
		br = { x + dst.w, y + dst.h }
	} else {
		sin_rot := math.sin(rotation * math.RAD_PER_DEG)
		cos_rot := math.cos(rotation * math.RAD_PER_DEG)
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

	s.rb.batch_vertex(tl, up, c)
	s.rb.batch_vertex(tr, up + {us.x, 0}, c)
	s.rb.batch_vertex(br, up + us, c)
	s.rb.batch_vertex(tl, up, c)
	s.rb.batch_vertex(br, up + us, c)
	s.rb.batch_vertex(bl, up + {0, us.y}, c)
}

Rendering_Backend :: struct {
	state_size: proc() -> int,
	init: proc(state: rawptr, window_handle: uintptr, swapchain_width, swapchain_height: int,
		allocator := context.allocator, loc := #caller_location),
	shutdown: proc(),
	clear: proc(color: Color),
	present: proc(),
	draw_current_batch: proc(),
	set_internal_state: proc(state: rawptr),

	load_texture: proc(data: []u8, width: int, height: int) -> Texture_Handle,
	destroy_texture: proc(handle: Texture_Handle),

	get_swapchain_width: proc() -> int,
	get_swapchain_height: proc() -> int,

	set_view_projection_matrix: proc(m: Mat4),

	batch_vertex: proc(v: Vec2, uv: Vec2, color: Color),
}

State :: struct {
	allocator: runtime.Allocator,
	custom_context: runtime.Context,
	rb: Rendering_Backend,
	rb_state: rawptr,
	
	keys_went_down: #sparse [Keyboard_Key]bool,
	keys_went_up: #sparse [Keyboard_Key]bool,
	keys_is_held: #sparse [Keyboard_Key]bool,

	window: win32.HWND,
	width: int,
	height: int,

	run: bool,

	shape_drawing_texture: Texture_Handle,
	batch_camera: Maybe(Camera),
	batch_texture: Texture_Handle,

	view_matrix: Mat4,
	proj_matrix: Mat4,
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

@(private="file")
s: ^State

// --------------------------------
// old, non migrated API below








get_default_shader: proc() -> Shader_Handle : _get_default_shader



set_scissor_rect: proc(scissor_rect: Maybe(Rect)) : _set_scissor_rect
set_shader: proc(shader: Shader_Handle) : _set_shader

//set_vertex_value :: _set_vertex_value

draw_circle: proc(center: Vec2, radius: f32, color: Color) : _draw_circle
draw_line: proc(start: Vec2, end: Vec2, thickness: f32, color: Color) : _draw_line

load_shader: proc(shader_source: string, layout_formats: []Shader_Input_Format = {}) -> Shader_Handle : _load_shader
destroy_shader: proc(shader: Shader_Handle) : _destroy_shader

get_shader_constant_location: proc(shader: Shader_Handle, name: string) -> Shader_Constant_Location : _get_shader_constant_location
set_shader_constant :: _set_shader_constant
set_shader_constant_mat4: proc(shader: Shader_Handle, loc: Shader_Constant_Location, val: matrix[4,4]f32) : _set_shader_constant_mat4
set_shader_constant_f32: proc(shader: Shader_Handle, loc: Shader_Constant_Location, val: f32) : _set_shader_constant_f32
set_shader_constant_vec2: proc(shader: Shader_Handle, loc: Shader_Constant_Location, val: Vec2) : _set_shader_constant_vec2

Shader_Input_Format :: enum {
	Unknown,
	RGBA32_Float,
	RGBA8_Norm,
	RGBA8_Norm_SRGB,
	RG32_Float,
	R32_Float,
}


// WARNING: Not proper text rendering yet... No font support etc
draw_text: proc(text: string, pos: Vec2, font_size: f32, color: Color) : _draw_text

screen_to_world: proc(pos: Vec2, camera: Camera) -> Vec2 : _screen_to_world


mouse_button_went_down: proc(button: Mouse_Button) -> bool : _mouse_button_pressed
mouse_button_went_up: proc(button: Mouse_Button) -> bool : _mouse_button_released
mouse_button_is_held: proc(button: Mouse_Button) -> bool : _mouse_button_held
get_mouse_wheel_delta: proc() -> f32 : _mouse_wheel_delta
get_mouse_position: proc() -> Vec2 : _mouse_position

Color :: [4]u8

Vec2 :: [2]f32

Mat4 :: matrix[4,4]f32

Vec2i :: [2]int

Rect :: struct {
	x, y: f32,
	w, h: f32,
}

Texture :: struct {
	handle: Texture_Handle,
	width: int,
	height: int,
}

Camera :: struct {
	target: Vec2,
	origin: Vec2,
	rotation: f32,
	zoom: f32,
}

// Support for up to 255 mouse buttons. Cast an int to type `Mouse_Button` to use things outside the
// options presented here.
Mouse_Button :: enum {
	Left,
	Right,
	Middle,
	Max = 255,
}

// TODO: These are just copied from raylib, we probably want a list of our own "default colors"
WHITE :: Color { 255, 255, 255, 255 }
BLACK :: Color { 0, 0, 0, 255 }
GRAY :: Color{ 130, 130, 130, 255 }
RED :: Color { 230, 41, 55, 255 }
YELLOW :: Color { 253, 249, 0, 255 }
BLUE :: Color { 0, 121, 241, 255 }
MAGENTA :: Color { 255, 0, 255, 255 }
DARKGRAY :: Color{ 80, 80, 80, 255 }
GREEN :: Color{ 0, 228, 48, 255 }

Shader_Handle :: distinct Handle
SHADER_NONE :: Shader_Handle {}

// Based on Raylib / GLFW
Keyboard_Key :: enum {
	None            = 0,

	// Alphanumeric keys
	Apostrophe      = 39,
	Comma           = 44,
	Minus           = 45,
	Period          = 46,
	Slash           = 47,
	Zero            = 48,
	One             = 49,
	Two             = 50,
	Three           = 51,
	Four            = 52,
	Five            = 53,
	Six             = 54,
	Seven           = 55,
	Eight           = 56,
	Nine            = 57,
	Semicolon       = 59,
	Equal           = 61,
	A               = 65,
	B               = 66,
	C               = 67,
	D               = 68,
	E               = 69,
	F               = 70,
	G               = 71,
	H               = 72,
	I               = 73,
	J               = 74,
	K               = 75,
	L               = 76,
	M               = 77,
	N               = 78,
	O               = 79,
	P               = 80,
	Q               = 81,
	R               = 82,
	S               = 83,
	T               = 84,
	U               = 85,
	V               = 86,
	W               = 87,
	X               = 88,
	Y               = 89,
	Z               = 90,
	Left_Bracket    = 91,
	Backslash       = 92,
	Right_Bracket   = 93,
	Grave           = 96,

	// Function keys
	Space           = 32,
	Escape          = 256,
	Enter           = 257,
	Tab             = 258,
	Backspace       = 259,
	Insert          = 260,
	Delete          = 261,
	Right           = 262,
	Left            = 263,
	Down            = 264,
	Up              = 265,
	Page_Up         = 266,
	Page_Down       = 267,
	Home            = 268,
	End             = 269,
	Caps_Lock       = 280,
	Scroll_Lock     = 281,
	Num_Lock        = 282,
	Print_Screen    = 283,
	Pause           = 284,
	F1              = 290,
	F2              = 291,
	F3              = 292,
	F4              = 293,
	F5              = 294,
	F6              = 295,
	F7              = 296,
	F8              = 297,
	F9              = 298,
	F10             = 299,
	F11             = 300,
	F12             = 301,
	Left_Shift      = 340,
	Left_Control    = 341,
	Left_Alt        = 342,
	Left_Super      = 343,
	Right_Shift     = 344,
	Right_Control   = 345,
	Right_Alt       = 346,
	Right_Super     = 347,
	Menu            = 348,

	// Keypad keys
	KP_0            = 320,
	KP_1            = 321,
	KP_2            = 322,
	KP_3            = 323,
	KP_4            = 324,
	KP_5            = 325,
	KP_6            = 326,
	KP_7            = 327,
	KP_8            = 328,
	KP_9            = 329,
	KP_Decimal      = 330,
	KP_Divide       = 331,
	KP_Multiply     = 332,
	KP_Subtract     = 333,
	KP_Add          = 334,
	KP_Enter        = 335,
	KP_Equal        = 336,
}