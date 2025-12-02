#+vet explicit-allocators

package karl2d

import "base:runtime"
import "core:mem"
import "core:log"
import "core:math"
import "core:math/linalg"
import "core:slice"
import "core:strings"
import "core:reflect"
import "core:os"

import fs "vendor:fontstash"

import "core:image"
import "core:image/jpeg"
import "core:image/bmp"
import "core:image/png"
import "core:image/tga"

import hm "handle_map"

//-----------------------------------------------//
// SETUP, WINDOW MANAGEMENT AND FRAME MANAGEMENT //
//-----------------------------------------------//

// Opens a window and initializes some internal state. The internal state will use `allocator` for
// all dynamically allocated memory. The return value can be ignored unless you need to later call
// `set_internal_state`.
init :: proc(window_width: int, window_height: int, window_title: string,
            window_creation_flags := Window_Flags {},
            allocator := context.allocator, loc := #caller_location) -> ^State {
	assert(s == nil, "Don't call 'init' twice.")
	context.allocator = allocator

	s = new(State, allocator, loc)

	// This is the same type of arena as the default temp allocator. This arena is for allocations
	// that have a lifetime of "one frame". They are valid until you call `present()`, at which
	// point the frame allocator is cleared.
	s.frame_allocator = runtime.arena_allocator(&s.frame_arena)
	frame_allocator = s.frame_allocator

	s.allocator = allocator

	s.win = WINDOW_INTERFACE_WIN32
	win = s.win

	// We alloc memory for the windowing backend and pass the blob of memory to it.
	window_state_alloc_error: runtime.Allocator_Error
	s.window_state, window_state_alloc_error = mem.alloc(win.state_size(), allocator = allocator)
	log.assertf(window_state_alloc_error == nil, "Failed allocating memory for window state: %v", window_state_alloc_error)

	win.init(s.window_state, window_width, window_height, window_title, window_creation_flags, allocator)

	// This is a OS-independent handle that we can pass to any rendering backend.
	s.window = win.window_handle()

	// See `config.odin` for how this is picked.
	s.rb = RENDER_BACKEND

	// Depending on backend the depth is counted in one of two ways. It can be counted from `1` and
	// to lower numbers. Or from `-1` and to higher numbers.
	s.depth_start = DEPTH_START
	s.depth_increment = DEPTH_INCREMENT

	if s.rb.flip_z() {
		s.depth_start = -DEPTH_START
		s.depth_increment = -DEPTH_INCREMENT
	}

	s.depth = s.depth_start
	rb = s.rb
	rb_alloc_error: runtime.Allocator_Error
	s.rb_state, rb_alloc_error = mem.alloc(rb.state_size(), allocator = allocator)
	log.assertf(rb_alloc_error == nil, "Failed allocating memory for rendering backend: %v", rb_alloc_error)
	s.proj_matrix = make_default_projection(window_width, window_height)
	s.view_matrix = 1

	// Boot up the render backend. It will render into our previously created window.
	rb.init(s.rb_state, s.window, window_width, window_height, allocator)

	// The vertex buffer is created in a render backend-independent way. It is passed to the
	// render backend each frame as part of `draw_current_batch()`
	s.vertex_buffer_cpu = make([]u8, VERTEX_BUFFER_MAX, allocator, loc)

	// The shapes drawing texture is sampled when any shape is drawn. This way we can use the same
	// shader for textured drawing and shape drawing. It's just a white box.
	white_rect: [16*16*4]u8
	slice.fill(white_rect[:], 255)
	s.shape_drawing_texture = rb.load_texture(white_rect[:], 16, 16, .RGBA_8_Norm)

	// The default shader will arrive in a different format depending on backend. GLSL for GL,
	// HLSL for d3d etc.
	s.default_shader = load_shader(rb.default_shader_vertex_source(), rb.default_shader_fragment_source())
	s.batch_shader = s.default_shader

	// FontStash enables us to bake fonts from TTF files on-the-fly.
	fs.Init(&s.fs, FONT_DEFAULT_ATLAS_SIZE, FONT_DEFAULT_ATLAS_SIZE, .TOPLEFT)

	DEFAULT_FONT_DATA :: #load("roboto.ttf")

	// Dummy element so font with index 0 means 'no font'.
	append_nothing(&s.fonts)

	s.default_font = load_font_from_bytes(DEFAULT_FONT_DATA)
	set_font(s.default_font)

	return s
}

// Returns true if the program wants to shut down. This happens when for example pressing the close
// button on the window. The application can decide if it wants to shut down or if it wants to show
// some kind of confirmation dialogue and shut down later.
//
// Commonly used for creating the "main loop" of a game.
shutdown_wanted :: proc() -> bool {
	return s.shutdown_wanted
}

// Closes the window and cleans up the internal state.
shutdown :: proc() {
	assert(s != nil, "You've called 'shutdown' without calling 'init' first")
	context.allocator = s.allocator

	destroy_font(s.default_font)
	rb.destroy_texture(s.shape_drawing_texture)
	destroy_shader(s.default_shader)
	rb.shutdown()
	delete(s.vertex_buffer_cpu, s.allocator)

	win.shutdown()

	fs.Destroy(&s.fs)
	delete(s.fonts)

	a := s.allocator
	free(s.window_state, a)
	free(s.rb_state, a)
	free(s, a)
	s = nil
}

// Clear the backbuffer with supplied color.
clear :: proc(color: Color) {
	rb.clear(s.batch_render_target, color)
	s.depth = s.depth_start
}

// Present the backbuffer. Call at end of frame to make everything you've drawn appear on the
// screen. Also clears the frame_allocator that Karl2D uses for allocations that have the lifetime
// of a single frame.
present :: proc() {
	draw_current_batch()
	rb.present()
	free_all(s.frame_allocator)
}

// Call at start or end of frame to process all events that have arrived to the window. This
// includes keyboard, mouse, gamepad and window events.
//
// WARNING: Not calling this will make your program impossible to interact with.
process_events :: proc() {
	s.key_went_up = {}
	s.key_went_down = {}
	s.mouse_button_went_up = {}
	s.mouse_button_went_down = {}
	s.gamepad_button_went_up = {}
	s.gamepad_button_went_down = {}
	s.mouse_delta = {}
	s.mouse_wheel_delta = 0

	win.process_events()

	events := win.get_events()

	for &event in events {
		switch &e in event {
		case Window_Event_Close_Wanted:
			s.shutdown_wanted = true

		case Window_Event_Key_Went_Down:
			s.key_went_down[e.key] = true
			s.key_is_held[e.key] = true

		case Window_Event_Key_Went_Up:
			s.key_went_up[e.key] = true
			s.key_is_held[e.key] = false

		case Window_Event_Mouse_Button_Went_Down:
			s.mouse_button_went_down[e.button] = true
			s.mouse_button_is_held[e.button] = true

		case Window_Event_Mouse_Button_Went_Up:
			s.mouse_button_went_up[e.button] = true
			s.mouse_button_is_held[e.button] = false

		case Window_Event_Mouse_Move:
			prev_pos := s.mouse_position
			s.mouse_position = e.position
			s.mouse_delta = s.mouse_position - prev_pos

		case Window_Event_Mouse_Wheel:
			s.mouse_wheel_delta = e.delta

		case Window_Event_Gamepad_Button_Went_Down:
			if e.gamepad < MAX_GAMEPADS {
				s.gamepad_button_went_down[e.gamepad][e.button] = true
				s.gamepad_button_is_held[e.gamepad][e.button] = true
			}

		case Window_Event_Gamepad_Button_Went_Up:
			if e.gamepad < MAX_GAMEPADS {
				s.gamepad_button_went_up[e.gamepad][e.button] = true
				s.gamepad_button_is_held[e.gamepad][e.button] = false
			}

		case Window_Event_Resize:
			rb.resize_swapchain(e.width, e.height)
			s.proj_matrix = make_default_projection(e.width, e.height)
		}
	}

	win.clear_events()
}

get_screen_width :: proc() -> int {
	return win.get_width()
}

get_screen_height :: proc() -> int  {
	return win.get_height()
}

set_window_position :: proc(x: int, y: int) {
	win.set_position(x, y)
}

set_window_size :: proc(width: int, height: int) {
	// TODO not sure if we should resize swapchain here. On windows the WM_SIZE event fires and
	// it all works out. But perhaps not on all platforms?
	win.set_size(width, height)
}

// Fetch the scale of the window. This usually comes from some DPI scaling setting in the OS.
// 1 means 100% scale, 1.5 means 150% etc.
get_window_scale :: proc() -> f32 {
	return win.get_window_scale()
}

set_window_flags :: proc(flags: Window_Flags) {
	win.set_flags(flags)
}

// Flushes the current batch. This sends off everything to the GPU that has been queued in the
// current batch. Normally, you do not need to do this manually. It is done automatically when these
// procedures run:
// 
// - present
// - set_camera
// - set_shader
// - set_shader_constant
// - set_scissor_rect
// - draw_texture_* IF previous draw did not use the same texture (1)
// - draw_rect_*, draw_circle_*, draw_line IF previous draw did not use the shapes drawing texture (2)
// 
// (1) When drawing textures, the current texture is fed into the active shader. Everything within
//     the same batch must use the same texture. So drawing with a new texture will draw the current
//     batch. You can combine several textures into an atlas to get bigger batches.
//
// (2) In order to use the same shader for shapes drawing and textured drawing, the shapes drawing
//     uses a blank, white texture. For the same reasons as (1), drawing something else than shapes
//     before drawing a shape will break up the batches. TODO: Add possibility to customize shape
//     drawing texture so that you can put it into an atlas.
//
// The batch has maximum size of VERTEX_BUFFER_MAX bytes. The shader dictates how big a vertex is
// so the maximum number of vertices that can be drawn in each batch is
// VERTEX_BUFFER_MAX / shader.vertex_size
draw_current_batch :: proc() {
	update_font(s.batch_font)

	if s.vertex_buffer_cpu_used == 0 {
		return
	}

	shader := s.batch_shader

	mvp := s.proj_matrix * s.view_matrix
	for mloc, builtin in shader.constant_builtin_locations {
		constant, constant_ok := mloc.?

		if !constant_ok {
			continue
		}

		switch builtin {
		case .MVP:
			if constant.size == size_of(mvp) {
				dst := (^matrix[4,4]f32)(&shader.constants_data[constant.offset])
				dst^ = mvp
			} 
		}
	}

	if def_tex_idx, has_def_tex_idx := shader.default_texture_index.?; has_def_tex_idx {
		shader.texture_bindpoints[def_tex_idx] = s.batch_texture
	}

	rb.draw(shader, s.batch_render_target, shader.texture_bindpoints, s.batch_scissor, s.batch_blend_mode, s.vertex_buffer_cpu[:s.vertex_buffer_cpu_used])
	s.vertex_buffer_cpu_used = 0
}

//-------//
// INPUT //
//-------//

// Returns true if a keyboard key went down between the current and the previous frame. Set when
// 'process_events' runs (probably once per frame).
key_went_down :: proc(key: Keyboard_Key) -> bool {
	return s.key_went_down[key]
}

// Returns true if a keyboard key went up (was released) between the current and the previous frame.
// Set when 'process_events' runs (probably once per frame).
key_went_up :: proc(key: Keyboard_Key) -> bool {
	return s.key_went_up[key]
}

// Returns true if a keyboard is currently being held down. Set when 'process_events' runs (probably
// once per frame).
key_is_held :: proc(key: Keyboard_Key) -> bool {
	return s.key_is_held[key]
}

mouse_button_went_down :: proc(button: Mouse_Button) -> bool {
	return s.mouse_button_went_down[button]
}

mouse_button_went_up :: proc(button: Mouse_Button) -> bool {
	return s.mouse_button_went_up[button]
}

mouse_button_is_held :: proc(button: Mouse_Button) -> bool {
	return s.mouse_button_is_held[button]
}

get_mouse_wheel_delta :: proc() -> f32 {
	return s.mouse_wheel_delta
}

get_mouse_position :: proc() -> Vec2 {
	return s.mouse_position
}

get_mouse_delta :: proc() -> Vec2 {
	return s.mouse_delta
}

is_gamepad_active :: proc(gamepad: Gamepad_Index) -> bool {
	return win.is_gamepad_active(gamepad)
}

gamepad_button_went_down :: proc(gamepad: Gamepad_Index, button: Gamepad_Button) -> bool {
	if gamepad < 0 || gamepad >= MAX_GAMEPADS {
		return false
	}

	return s.gamepad_button_went_down[gamepad][button]
}

gamepad_button_went_up :: proc(gamepad: Gamepad_Index, button: Gamepad_Button) -> bool {
	if gamepad < 0 || gamepad >= MAX_GAMEPADS {
		return false
	}

	return s.gamepad_button_went_up[gamepad][button]
}

gamepad_button_is_held :: proc(gamepad: Gamepad_Index, button: Gamepad_Button) -> bool {
	if gamepad < 0 || gamepad >= MAX_GAMEPADS {
		return false
	}

	return s.gamepad_button_is_held[gamepad][button]
}

get_gamepad_axis :: proc(gamepad: Gamepad_Index, axis: Gamepad_Axis) -> f32 {
	return win.get_gamepad_axis(gamepad, axis)
}

// Set the left and right vibration motor speed. The range of left and right is 0 to 1. Note that on
// most gamepads, the left motor is "low frequency" and the right motor is "high frequency". They do
// not vibrate with the same speed.
set_gamepad_vibration :: proc(gamepad: Gamepad_Index, left: f32, right: f32) {
	win.set_gamepad_vibration(gamepad, left, right)
}

//---------//
// DRAWING //
//---------//

draw_rect :: proc(r: Rect, c: Color) {
	if s.vertex_buffer_cpu_used + s.batch_shader.vertex_size * 6 > len(s.vertex_buffer_cpu) {
		draw_current_batch()
	}

	if s.batch_texture != s.shape_drawing_texture {
		draw_current_batch()
	}

	s.batch_texture = s.shape_drawing_texture

	z := get_next_depth()

	batch_vertex({r.x, r.y, z}, {0, 0}, c)
	batch_vertex({r.x + r.w, r.y, z}, {1, 0}, c)
	batch_vertex({r.x + r.w, r.y + r.h, z}, {1, 1}, c)
	batch_vertex({r.x, r.y, z}, {0, 0}, c)
	batch_vertex({r.x + r.w, r.y + r.h, z}, {1, 1}, c)
	batch_vertex({r.x, r.y + r.h, z}, {0, 1}, c)
}

draw_rect_vec :: proc(pos: Vec2, size: Vec2, c: Color) {
	draw_rect({pos.x, pos.y, size.x, size.y}, c)
}

draw_rect_ex :: proc(r: Rect, origin: Vec2, rot: f32, c: Color) {
	if s.vertex_buffer_cpu_used + s.batch_shader.vertex_size * 6 > len(s.vertex_buffer_cpu) {
		draw_current_batch()
	}

	if s.batch_texture != s.shape_drawing_texture {
		draw_current_batch()
	}

	s.batch_texture = s.shape_drawing_texture
	tl, tr, bl, br: Vec2

	// Rotation adapted from Raylib's "DrawTexturePro"
	if rot == 0 {
		x := r.x - origin.x
		y := r.y - origin.y
		tl = { x,         y }
		tr = { x + r.w, y }
		bl = { x,         y + r.h }
		br = { x + r.w, y + r.h }
	} else {
		sin_rot := math.sin(rot * math.RAD_PER_DEG)
		cos_rot := math.cos(rot * math.RAD_PER_DEG)
		x := r.x
		y := r.y
		dx := -origin.x
		dy := -origin.y

		tl = {
			x + dx * cos_rot - dy * sin_rot,
			y + dx * sin_rot + dy * cos_rot,
		}

		tr = {
			x + (dx + r.w) * cos_rot - dy * sin_rot,
			y + (dx + r.w) * sin_rot + dy * cos_rot,
		}

		bl = {
			x + dx * cos_rot - (dy + r.h) * sin_rot,
			y + dx * sin_rot + (dy + r.h) * cos_rot,
		}

		br = {
			x + (dx + r.w) * cos_rot - (dy + r.h) * sin_rot,
			y + (dx + r.w) * sin_rot + (dy + r.h) * cos_rot,
		}
	}

	z := get_next_depth()
	
	batch_vertex(vec3(tl, z), {0, 0}, c)
	batch_vertex(vec3(tr, z), {1, 0}, c)
	batch_vertex(vec3(br, z), {1, 1}, c)
	batch_vertex(vec3(tl, z), {0, 0}, c)
	batch_vertex(vec3(br, z), {1, 1}, c)
	batch_vertex(vec3(bl, z), {0, 1}, c)
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

draw_circle :: proc(center: Vec2, radius: f32, color: Color, segments := 16) {
	if s.vertex_buffer_cpu_used + s.batch_shader.vertex_size * 3 * segments > len(s.vertex_buffer_cpu) {
		draw_current_batch()
	}

	if s.batch_texture != s.shape_drawing_texture {
		draw_current_batch()
	}

	s.batch_texture = s.shape_drawing_texture

	z := get_next_depth()

	prev := center + {radius, 0}
	for s in 1..=segments {
		sr := (f32(s)/f32(segments)) * 2*math.PI
		rot := linalg.matrix2_rotate(sr)
		p := center + rot * Vec2{radius, 0}

		batch_vertex(vec3(prev, z), {0, 0}, color)
		batch_vertex(vec3(p, z), {1, 0}, color)
		batch_vertex(vec3(center, z), {1, 1}, color)

		prev = p
	}
}

draw_circle_outline :: proc(center: Vec2, radius: f32, thickness: f32, color: Color, segments := 16) {
	prev := center + {radius, 0}
	for s in 1..=segments {
		sr := (f32(s)/f32(segments)) * 2*math.PI
		rot := linalg.matrix2_rotate(sr)
		p := center + rot * Vec2{radius, 0}
		draw_line(prev, p, thickness, color)
		prev = p
	}
}

draw_line :: proc(start: Vec2, end: Vec2, thickness: f32, color: Color) {
	p := Vec2{start.x, start.y + thickness*0.5}
	s := Vec2{linalg.length(end - start), thickness}

	origin := Vec2 {0, thickness*0.5}
	r := Rect {p.x, p.y, s.x, s.y}

	rot := math.atan2(end.y - start.y, end.x - start.x)

	draw_rect_ex(r, origin, rot * math.DEG_PER_RAD, color)
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

	if s.vertex_buffer_cpu_used + s.batch_shader.vertex_size * 6 > len(s.vertex_buffer_cpu) {
		draw_current_batch()
	}

	if s.batch_texture != tex.handle {
		draw_current_batch()
	}
	
	s.batch_texture = tex.handle

	flip_x, flip_y: bool
	src := src
	dst := dst

	if src.w < 0 {
		flip_x = true
		src.w = -src.w
	}

	if src.h < 0 {
		flip_y = true
		src.h = -src.h
	}

	if dst.w < 0 {
		dst.w *= -1
	}

	if dst.h < 0 {
		dst.h *= -1
	}

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

	uv0 := up
	uv1 := up + {us.x, 0}
	uv2 := up + us
	uv3 := up
	uv4 := up + us
	uv5 := up + {0, us.y}

	if flip_x {
		uv0.x += us.x
		uv1.x -= us.x
		uv2.x -= us.x
		uv3.x += us.x
		uv4.x -= us.x
		uv5.x += us.x		
	}

	if flip_y {
		uv0.y += us.y
		uv1.y += us.y
		uv2.y -= us.y
		uv3.y += us.y
		uv4.y -= us.y
		uv5.y -= us.y		
	}

	z := get_next_depth()

	batch_vertex(vec3(tl, z), uv0, c)
	batch_vertex(vec3(tr, z), uv1, c)
	batch_vertex(vec3(br, z), uv2, c)
	batch_vertex(vec3(tl, z), uv3, c)
	batch_vertex(vec3(br, z), uv4, c)
	batch_vertex(vec3(bl, z), uv5, c)
}

measure_text :: proc(text: string, font_size: f32) -> Vec2 {
	fs.SetSize(&s.fs, font_size)
	b: [4]f32
	fs.TextBounds(&s.fs, text, bounds = &b)
	return {b[2] - b[0], b[3] - b[1]}
}

draw_text :: proc(text: string, pos: Vec2, font_size: f32, color: Color) {
	draw_text_ex(s.default_font, text, pos, font_size, color)
}

draw_text_ex :: proc(font: Font_Handle, text: string, pos: Vec2, font_size: f32, color: Color) {
	if int(font) >= len(s.fonts) {
		return
	}

	set_font(font)
	font := &s.fonts[font]
	fs.SetSize(&s.fs, font_size)
	iter := fs.TextIterInit(&s.fs, pos.x, pos.y+font_size/2, text)

	q: fs.Quad
	for fs.TextIterNext(&s.fs, &iter, &q) {
		src := Rect {
			q.s0, q.t0,
			q.s1 - q.s0, q.t1 - q.t0,
		}

		w := f32(FONT_DEFAULT_ATLAS_SIZE)
		h := f32(FONT_DEFAULT_ATLAS_SIZE)

		src.x *= w
		src.y *= h
		src.w *= w
		src.h *= h

		dst := Rect {
			q.x0, q.y0,
			q.x1 - q.x0, q.y1 - q.y0,
		}

		draw_texture_ex(font.atlas, src, dst, {}, 0, color)
	}
}

set_blend_mode :: proc(mode: Blend_Mode) {
	if s.batch_blend_mode == mode {
		return
	}

	draw_current_batch()
	s.batch_blend_mode = mode
}

//--------------------//
// TEXTURE MANAGEMENT //
//--------------------//

create_texture :: proc(width: int, height: int, format: Pixel_Format) -> Texture {
	h := rb.create_texture(width, height, format)

	return {
		handle = h,
		width = width,
		height = height,
	}
}

load_texture_from_file :: proc(filename: string, options: Load_Texture_Options = {}) -> Texture {
	load_options := image.Options {
		.alpha_add_if_missing,
	}

	if .Premultiply_Alpha in options {
		load_options += { .alpha_premultiply }
	}

	img, img_err := image.load_from_file(filename, options = load_options, allocator = s.frame_allocator)

	if img_err != nil {
		log.errorf("Error loading texture %v: %v", filename, img_err)
		return {}
	}

	return load_texture_from_bytes(img.pixels.buf[:], img.width, img.height, .RGBA_8_Norm)
}

// TODO should we have an error here or rely on check the handle of the texture?
load_texture_from_bytes :: proc(bytes: []u8, width: int, height: int, format: Pixel_Format) -> Texture {
	backend_tex := rb.load_texture(bytes[:], width, height, format)

	if backend_tex == TEXTURE_NONE {
		return {}
	}

	return {
		handle = backend_tex,
		width = width,
		height = height,
	}
}

// Get a rectangle that spans the whole texture. Coordinates will be (x, y) = (0, 0) and size
// (w, h) = (texture_width, texture_height)
get_texture_rect :: proc(t: Texture) -> Rect {
	return {
		0, 0,
		f32(t.width), f32(t.height),
	}
}

// Update a texture with new pixels. `bytes` is the new pixel data. `rect` is the rectangle in
// `tex` where the new pixels should end up.
update_texture :: proc(tex: Texture, bytes: []u8, rect: Rect) -> bool {
	return rb.update_texture(tex.handle, bytes, rect)
}

destroy_texture :: proc(tex: Texture) {
	rb.destroy_texture(tex.handle)
}

// Controls how a texture should be filtered. You can choose "point" or "linear" filtering. Which
// means "pixly" or "smooth". This filter will be used for up and down-scaling as well as for
// mipmap sampling. Use `set_texture_filter_ex` if you need to control these settings separately.
set_texture_filter :: proc(t: Texture, filter: Texture_Filter) {
	set_texture_filter_ex(t, filter, filter, filter)
}

// Controls how a texture should be filtered. `scale_down_filter` and `scale_up_filter` controls how
// the texture is filtered when we render the texture at a smaller or larger size.
// `mip_filter` controls how the texture is filtered when it is sampled using _mipmapping_.
//
// TODO: Add mipmapping generation controls for texture and refer to it from here.
set_texture_filter_ex :: proc(
	t: Texture,
	scale_down_filter: Texture_Filter,
	scale_up_filter: Texture_Filter,
	mip_filter: Texture_Filter,
) {
	rb.set_texture_filter(t.handle, scale_down_filter, scale_up_filter, mip_filter)
}

//-----------------//
// RENDER TEXTURES //
//-----------------//

create_render_texture :: proc(width: int, height: int) -> Render_Texture {
	texture, render_target := rb.create_render_texture(width, height)

	return {
		texture = { 
			handle = texture,
			width = width,
			height = height,	
		},
		render_target = render_target,
	}
}

destroy_render_texture :: proc(render_texture: Render_Texture) {
	rb.destroy_texture(render_texture.texture.handle)
	rb.destroy_render_target(render_texture.render_target)
}

set_render_texture :: proc(render_texture: Maybe(Render_Texture)) {
	if rt, rt_ok := render_texture.?; rt_ok {
		if s.batch_render_target == rt.render_target {
			return
		}

		draw_current_batch()
		s.batch_render_target = rt.render_target
	} else {
		if s.batch_render_target == RENDER_TARGET_NONE {
			return
		}

		draw_current_batch()
		s.batch_render_target = RENDER_TARGET_NONE
	}
}

//-------//
// FONTS //
//-------//

load_font_from_file :: proc(filename: string) -> Font_Handle {
	if data, data_ok := os.read_entire_file(filename, frame_allocator); data_ok {
		return load_font_from_bytes(data)
	}

	return FONT_NONE
}

load_font_from_bytes :: proc(data: []u8) -> Font_Handle {
	font := fs.AddFontMem(&s.fs, "", data, false)
	h := Font_Handle(len(s.fonts))

	append(&s.fonts, Font {
		fontstash_handle = font,
		atlas = {
			handle = rb.create_texture(FONT_DEFAULT_ATLAS_SIZE, FONT_DEFAULT_ATLAS_SIZE, .RGBA_8_Norm),
			width = FONT_DEFAULT_ATLAS_SIZE,
			height = FONT_DEFAULT_ATLAS_SIZE,
		},
	})

	return h
}

destroy_font :: proc(font: Font_Handle) {
	if int(font) >= len(s.fonts) {
		return
	}

	f := &s.fonts[font]
	rb.destroy_texture(f.atlas.handle)	

	// TODO fontstash has no "destroy font" proc... I should make my own version of fontstash
	delete(s.fs.fonts[f.fontstash_handle].glyphs)
	s.fs.fonts[f.fontstash_handle].glyphs = {}
}

get_default_font :: proc() -> Font_Handle {
	return s.default_font
}


//---------//
// SHADERS //
//---------//

load_shader :: proc(
	vertex_shader_source: string,
	fragment_shader_source: string,
	layout_formats: []Pixel_Format = {},
) -> Shader {
	handle, desc := rb.load_shader(
		vertex_shader_source,
		fragment_shader_source,
		s.frame_allocator,
		layout_formats,
	)

	if handle == SHADER_NONE {
		log.error("Failed loading shader")
		return {}
	}

	constants_size: int

	for c in desc.constants {
		constants_size += c.size
	}

	shd := Shader {
		handle = handle,
		constants_data = make([]u8, constants_size, s.allocator),
		constants = make([]Shader_Constant_Location, len(desc.constants), s.allocator),
		constant_lookup = make(map[string]Shader_Constant_Location, s.allocator),
		inputs = slice.clone(desc.inputs, s.allocator),
		input_overrides = make([]Shader_Input_Value_Override, len(desc.inputs), s.allocator),
		texture_bindpoints = make([]Texture_Handle, len(desc.texture_bindpoints), s.allocator),
		texture_lookup = make(map[string]int, s.allocator),
	}

	for &input in shd.inputs {
		input.name = strings.clone(input.name, s.allocator)
	}

	constant_offset: int

	for cidx in 0..<len(desc.constants) {
		constant_desc := &desc.constants[cidx]

		loc := Shader_Constant_Location {
			offset = constant_offset,
			size = constant_desc.size,
		}

		shd.constants[cidx] = loc 
		constant_offset += constant_desc.size

		if constant_desc.name != "" {
			shd.constant_lookup[strings.clone(constant_desc.name, s.allocator)] = loc

			switch constant_desc.name {
			case "mvp":
				shd.constant_builtin_locations[.MVP] = loc
			}
		}
	}

	for tbp, tbp_idx in desc.texture_bindpoints {
		shd.texture_lookup[tbp.name] = tbp_idx

		if tbp.name == "tex" {
			shd.default_texture_index = tbp_idx
		}
	}

	for &d in shd.default_input_offsets {
		d = -1
	}

	input_offset: int

	for &input in shd.inputs {
		default_format := get_shader_input_default_type(input.name, input.type)

		if default_format != .Unknown {
			shd.default_input_offsets[default_format] = input_offset
		}
		
		input_offset += pixel_format_size(input.format)
	}

	shd.vertex_size = input_offset
 	return shd
}

destroy_shader :: proc(shader: Shader) {
	rb.destroy_shader(shader.handle)

	a := s.allocator

	delete(shader.constants_data, a)
	delete(shader.constants, a)
	delete(shader.texture_lookup)
	delete(shader.texture_bindpoints, a)

	for k, _ in shader.constant_lookup {
		delete(k, a)
	}

	delete(shader.constant_lookup)
	for i in shader.inputs {
		delete(i.name, a)
	}
	delete(shader.inputs, a)
	delete(shader.input_overrides, a)
}

get_default_shader :: proc() -> Shader {
	return s.default_shader
}

set_shader :: proc(shader: Maybe(Shader)) {
	if shd, shd_ok := shader.?; shd_ok {
		if shd.handle == s.batch_shader.handle {
			return
		}
	} else {
		if s.batch_shader.handle == s.default_shader.handle {
			return
		}
	}

	draw_current_batch()
	s.batch_shader = shader.? or_else s.default_shader
}

set_shader_constant :: proc(shd: Shader, loc: Shader_Constant_Location, val: any) {
	if shd.handle == SHADER_NONE {
		log.error("Invalid shader")
		return
	}

	if loc.size == 0 {
		log.error("Could not find shader constant")
		return
	}

	draw_current_batch()

	if loc.offset + loc.size > len(shd.constants_data) {
		log.errorf("Constant with offset %v and size %v is out of bounds. Buffer ends at %v", loc.offset, loc.size, len(shd.constants_data))
		return
	}

	sz := reflect.size_of_typeid(val.id)

	if sz != loc.size {
		log.errorf("Trying to set constant of type %v, but it is not of correct size %v", val.id, loc.size)
		return
	}

	mem.copy(&shd.constants_data[loc.offset], val.data, sz)
}

override_shader_input :: proc(shader: Shader, input: int, val: any) {
	sz := reflect.size_of_typeid(val.id)
	assert(sz < SHADER_INPUT_VALUE_MAX_SIZE)
	if input >= len(shader.input_overrides) {
		log.errorf("Input override out of range. Wanted to override input %v, but shader only has %v inputs", input, len(shader.input_overrides))
		return
	}

	o := &shader.input_overrides[input]

	o.val = {}

	if sz > 0 {
		mem.copy(raw_data(&o.val), val.data, sz)
	}

	o.used = sz
}

pixel_format_size :: proc(f: Pixel_Format) -> int {
	switch f {
	case .Unknown: return 0

	case .RGBA_32_Float: return 32
	case .RGB_32_Float: return 12
	case .RG_32_Float: return 8
	case .R_32_Float: return 4

	case .RGBA_8_Norm: return 4
	case .RG_8_Norm: return 2
	case .R_8_Norm: return 1

	case .R_8_UInt: return 1
	}

	return 0
}

//-------------------------------//
// CAMERA AND COORDINATE SYSTEMS //
//-------------------------------//

set_camera :: proc(camera: Maybe(Camera)) {
	if camera == s.batch_camera {
		return
	}

	draw_current_batch()
	s.batch_camera = camera
	s.proj_matrix = make_default_projection(win.get_width(), win.get_height())

	if c, c_ok := camera.?; c_ok {
		s.view_matrix = get_camera_view_matrix(c)
	} else {
		s.view_matrix = 1
	}
}

screen_to_world :: proc(pos: Vec2, camera: Camera) -> Vec2 {
	return (get_camera_world_matrix(camera) * Vec4 { pos.x, pos.y, 0, 1 }).xy
}

world_to_screen :: proc(pos: Vec2, camera: Camera) -> Vec2 {
	return (get_camera_view_matrix(camera) * Vec4 { pos.x, pos.y, 0, 1 }).xy
}

get_camera_view_matrix :: proc(c: Camera) -> Mat4 {
	inv_target_translate := linalg.matrix4_translate(vec3_from_vec2(-c.target))
	inv_rot := linalg.matrix4_rotate_f32(c.rotation * math.RAD_PER_DEG, {0, 0, 1})
	inv_scale := linalg.matrix4_scale(Vec3{c.zoom, c.zoom, 1})
	inv_offset_translate := linalg.matrix4_translate(vec3_from_vec2(c.offset))

	// A view matrix is essentially the world transform matrix of the camera, but inverted. We
	// bring everything in the world "in front of the camera".
	//
	// Instead of constructing the camera matrix and doing a matrix inverse, here we just do the
	// maths in "backwards order". I.e. a camera transform matrix would be:
	//
	//    target_translate * rot * scale * offset_translate

	return inv_offset_translate * inv_scale * inv_rot * inv_target_translate
}

get_camera_world_matrix :: proc(c: Camera) -> Mat4 {
	offset_translate := linalg.matrix4_translate(vec3_from_vec2(-c.offset))
	rot := linalg.matrix4_rotate_f32(-c.rotation * math.RAD_PER_DEG, {0, 0, 1})
	scale := linalg.matrix4_scale(Vec3{1/c.zoom, 1/c.zoom, 1})
	target_translate := linalg.matrix4_translate(vec3_from_vec2(c.target))

	return target_translate * rot * scale * offset_translate
}

//------//
// MISC //
//------//

set_scissor_rect :: proc(scissor_rect: Maybe(Rect)) {
	draw_current_batch()
	s.batch_scissor = scissor_rect
}

// Restore the internal state using the pointer returned by `init`. Useful after reloading the
// library (for example, when doing code hot reload).
set_internal_state :: proc(state: ^State) {
	s = state
	rb = s.rb
	win = s.win
	rb.set_internal_state(s.rb_state)
	win.set_internal_state(s.window_state)
}

//---------------------//
// TYPES AND CONSTANTS //
//---------------------//

Vec2 :: [2]f32

Vec3 :: [3]f32

Vec4 :: [4]f32

Mat4 :: matrix[4,4]f32

// A two dimensional vector of integer numeric type.
Vec2i :: [2]int

// A rectangle that sits at position (x, y) and has size (w, h).
Rect :: struct {
	x, y: f32,
	w, h: f32,
}

// An RGBA (Red, Green, Blue, Alpha) color. Each channel can have a value between 0 and 255.
Color :: [4]u8

WHITE :: Color { 255, 255, 255, 255 }
BLACK :: Color { 0, 0, 0, 255 }
GRAY  :: Color { 127, 127, 127, 255 }
RED   :: Color { 198, 40, 90, 255 }
GREEN :: Color { 30, 240, 30, 255 }
BLANK :: Color { 0, 0, 0, 0 }
BLUE  :: Color { 30, 116, 240, 255 }

// These are from Raylib. They are here so you can easily port a Raylib program to Karl2D.
RL_LIGHTGRAY  :: Color { 200, 200, 200, 255 }
RL_GRAY       :: Color { 130, 130, 130, 255 }
RL_DARKGRAY   :: Color { 80, 80, 80, 255 }
RL_YELLOW     :: Color { 253, 249, 0, 255 }
RL_GOLD       :: Color { 255, 203, 0, 255 }
RL_ORANGE     :: Color { 255, 161, 0, 255 }
RL_PINK       :: Color { 255, 109, 194, 255 }
RL_RED        :: Color { 230, 41, 55, 255 }
RL_MAROON     :: Color { 190, 33, 55, 255 }
RL_GREEN      :: Color { 0, 228, 48, 255 }
RL_LIME       :: Color { 0, 158, 47, 255 }
RL_DARKGREEN  :: Color { 0, 117, 44, 255 }
RL_SKYBLUE    :: Color { 102, 191, 255, 255 }
RL_BLUE       :: Color { 0, 121, 241, 255 }
RL_DARKBLUE   :: Color { 0, 82, 172, 255 }
RL_PURPLE     :: Color { 200, 122, 255, 255 }
RL_VIOLET     :: Color { 135, 60, 190, 255 }
RL_DARKPURPLE :: Color { 112, 31, 126, 255 }
RL_BEIGE      :: Color { 211, 176, 131, 255 }
RL_BROWN      :: Color { 127, 106, 79, 255 }
RL_DARKBROWN  :: Color { 76, 63, 47, 255 }
RL_WHITE      :: WHITE
RL_BLACK      :: BLACK
RL_BLANK      :: BLANK
RL_MAGENTA    :: Color { 255, 0, 255, 255 }
RL_RAYWHITE   :: Color { 245, 245, 245, 255 }

Texture :: struct {
	handle: Texture_Handle,
	width: int,
	height: int,
}

Load_Texture_Option :: enum {
	Premultiply_Alpha,
}

Load_Texture_Options :: bit_set[Load_Texture_Option]

Blend_Mode :: enum {
	Alpha,
	Premultiplied_Alpha, // Needs the alpha-channel to be multiplie into any texture's color channels.
}

Render_Texture :: struct {
	texture: Texture,
	render_target: Render_Target_Handle,
}

Texture_Filter :: enum {
	Point,  // Similar to "nearest neighbor". Pixly texture scaling.
	Linear, // Smoothed texture scaling.
}

Camera :: struct {
	target: Vec2,
	offset: Vec2,
	rotation: f32,
	zoom: f32,
}

Window_Flag :: enum {
	Resizable,
}

Window_Flags :: bit_set[Window_Flag]

Shader_Handle :: distinct Handle

SHADER_NONE :: Shader_Handle {}

Shader_Constant_Location :: struct {
	offset: int,
	size: int,
}

Shader :: struct {
	handle: Shader_Handle,

	// We store the CPU-side value of all constants in a single buffer to have less allocations.
	// The 'constants' array says where in this buffer each constant is, and 'constant_lookup'
	// maps a name to a constant location.
	constants_data: []u8,
	constants: []Shader_Constant_Location,
	constant_lookup: map[string]Shader_Constant_Location,

	// Maps built in constant types such as "model view projection matrix" to a location.
	constant_builtin_locations: [Shader_Builtin_Constant]Maybe(Shader_Constant_Location),

	texture_bindpoints: []Texture_Handle,
	texture_lookup: map[string]int,
	default_texture_index: Maybe(int),

	inputs: []Shader_Input,
	input_overrides: []Shader_Input_Value_Override,
	default_input_offsets: [Shader_Default_Inputs]int,
	vertex_size: int,
}

SHADER_INPUT_VALUE_MAX_SIZE :: 256

Shader_Input_Value_Override :: struct {
	val: [SHADER_INPUT_VALUE_MAX_SIZE]u8,
	used: int,
}

Shader_Input_Type :: enum {
	F32,
	Vec2,
	Vec3,
	Vec4,
}

Shader_Builtin_Constant :: enum {
	MVP,
}

Shader_Default_Inputs :: enum {
	Unknown,
	Position,
	UV,
	Color,
}

Shader_Input :: struct {
	name: string,
	register: int,
	type: Shader_Input_Type,
	format: Pixel_Format,
}

Pixel_Format :: enum {
	Unknown,
	
	RGBA_32_Float,
	RGB_32_Float,
	RG_32_Float,
	R_32_Float,

	RGBA_8_Norm,
	RG_8_Norm,
	R_8_Norm,

	R_8_UInt,
}

Font :: struct {
	atlas: Texture,

	// internal
	fontstash_handle: int,
}

Handle :: hm.Handle
Texture_Handle :: distinct Handle
Render_Target_Handle :: distinct Handle
Font_Handle :: distinct int

FONT_NONE :: Font_Handle {}
TEXTURE_NONE :: Texture_Handle {}
RENDER_TARGET_NONE :: Render_Target_Handle {}

// This keeps track of the internal state of the library. Usually, you do not need to poke at it.
// It is created and kept as a global variable when 'init' is called. However, 'init' also returns
// the pointer to it, so you can later use 'set_internal_state' to restore it (after for example hot
// reload).
State :: struct {
	allocator: runtime.Allocator,
	frame_arena: runtime.Arena,
	frame_allocator: runtime.Allocator,
	win: Window_Interface,
	window_state: rawptr,
	rb: Render_Backend_Interface,
	rb_state: rawptr,

	fs: fs.FontContext,
	
	shutdown_wanted: bool,

	mouse_position: Vec2,
	mouse_delta: Vec2,
	mouse_wheel_delta: f32,

	key_went_down: #sparse [Keyboard_Key]bool,
	key_went_up: #sparse [Keyboard_Key]bool,
	key_is_held: #sparse [Keyboard_Key]bool,

	mouse_button_went_down: #sparse [Mouse_Button]bool,
	mouse_button_went_up: #sparse [Mouse_Button]bool,
	mouse_button_is_held: #sparse [Mouse_Button]bool,

	gamepad_button_went_down: [MAX_GAMEPADS]#sparse [Gamepad_Button]bool,
	gamepad_button_went_up: [MAX_GAMEPADS]#sparse [Gamepad_Button]bool,
	gamepad_button_is_held: [MAX_GAMEPADS]#sparse [Gamepad_Button]bool,

	window: Window_Handle,

	default_font: Font_Handle,
	fonts: [dynamic]Font,
	shape_drawing_texture: Texture_Handle,
	batch_font: Font_Handle,
	batch_camera: Maybe(Camera),
	batch_shader: Shader,
	batch_scissor: Maybe(Rect),
	batch_texture: Texture_Handle,
	batch_render_target: Render_Target_Handle,
	batch_blend_mode: Blend_Mode,

	view_matrix: Mat4,
	proj_matrix: Mat4,

	depth: f32,
	depth_start: f32,
	depth_increment: f32,
	vertex_buffer_cpu: []u8,
	vertex_buffer_cpu_used: int,
	default_shader: Shader,
}

// Support for up to 255 mouse buttons. Cast an int to type `Mouse_Button` to use things outside the
// options presented here.
Mouse_Button :: enum {
	Left,
	Right,
	Middle,
	Max = 255,
}

// Based on Raylib / GLFW
Keyboard_Key :: enum {
	None            = 0,

	// Numeric keys (top row)
	N0              = 48,
	N1              = 49,
	N2              = 50,
	N3              = 51,
	N4              = 52,
	N5              = 53,
	N6              = 54,
	N7              = 55,
	N8              = 56,
	N9              = 57,

	// Letter keys
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

	// Special characters
	Apostrophe      = 39,
	Comma           = 44,
	Minus           = 45,
	Period          = 46,
	Slash           = 47,
	Semicolon       = 59,
	Equal           = 61,
	Left_Bracket    = 91,
	Backslash       = 92,
	Right_Bracket   = 93,
	Grave_Accent    = 96,

	// Function keys, modifiers, caret control etc
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

	// Numpad keys
	NP_0            = 320,
	NP_1            = 321,
	NP_2            = 322,
	NP_3            = 323,
	NP_4            = 324,
	NP_5            = 325,
	NP_6            = 326,
	NP_7            = 327,
	NP_8            = 328,
	NP_9            = 329,
	NP_Decimal      = 330,
	NP_Divide       = 331,
	NP_Multiply     = 332,
	NP_Subtract     = 333,
	NP_Add          = 334,
	NP_Enter        = 335,
	NP_Equal        = 336,
}

MAX_GAMEPADS :: 4

// A value between 0 and MAX_GAMEPADS - 1
Gamepad_Index :: int

Gamepad_Axis :: enum {
	Left_Stick_X,
	Left_Stick_Y,
	Right_Stick_X,
	Right_Stick_Y,
	Left_Trigger,
	Right_Trigger,
}

Gamepad_Button :: enum {
	// DPAD buttons
	Left_Face_Up,
	Left_Face_Down,
	Left_Face_Left,
	Left_Face_Right,

	Right_Face_Up, // XBOX: Y, PS: Triangle
	Right_Face_Down, // XBOX: A, PS: X
	Right_Face_Left, // XBOX: X, PS: Square
	Right_Face_Right, // XBOX: B, PS: Circle

	Left_Shoulder,
	Left_Trigger,

	Right_Shoulder,
	Right_Trigger,

	Left_Stick_Press, // Clicking the left analogue stick
	Right_Stick_Press, // Clicking the right analogue stick

	Middle_Face_Left, // Select / back / options button
	Middle_Face_Middle, // PS button (not available on XBox)
	Middle_Face_Right, // Start
}

// Used by API builder. Everything after this constant will not be in karl2d.doc.odin
API_END :: true

batch_vertex :: proc(v: Vec3, uv: Vec2, color: Color) {
	v := v

	if s.vertex_buffer_cpu_used == len(s.vertex_buffer_cpu) {
		draw_current_batch()
	}

	shd := s.batch_shader

	base_offset := s.vertex_buffer_cpu_used
	pos_offset := shd.default_input_offsets[.Position]
	uv_offset := shd.default_input_offsets[.UV]
	color_offset := shd.default_input_offsets[.Color]
	
	mem.set(&s.vertex_buffer_cpu[base_offset], 0, shd.vertex_size)

	if pos_offset != -1 {
		(^Vec3)(&s.vertex_buffer_cpu[base_offset + pos_offset])^ = v
	}

	if uv_offset != -1 {
		(^Vec2)(&s.vertex_buffer_cpu[base_offset + uv_offset])^ = uv
	}

	if color_offset != -1 {
		(^Color)(&s.vertex_buffer_cpu[base_offset + color_offset])^ = color
	}

	override_offset: int
	for &o, idx in shd.input_overrides {
		input := &shd.inputs[idx]
		sz := pixel_format_size(input.format)

		if o.used != 0 {
			mem.copy(&s.vertex_buffer_cpu[base_offset + override_offset], raw_data(&o.val), o.used)
		}

		override_offset += sz
	}
	
	s.vertex_buffer_cpu_used += shd.vertex_size
}


VERTEX_BUFFER_MAX :: 1000000

@(private="file")
s: ^State

// These globals are here for access from other files. The state struct above is private to make
// sure global state sharing doesn't become too messy.
frame_allocator: runtime.Allocator
win: Window_Interface
rb: Render_Backend_Interface

get_shader_input_default_type :: proc(name: string, type: Shader_Input_Type) -> Shader_Default_Inputs {
	if name == "position" && type == .Vec3 {
		return .Position
	} else if name == "texcoord" && type == .Vec2 {
		return .UV
	} else if name == "color" && type == .Vec4 {
		return .Color
	}

	return .Unknown
}

get_shader_format_num_components :: proc(format: Pixel_Format) -> int {
	switch format {
	case .Unknown: return 0 
	case .RGBA_32_Float: return 4
	case .RGB_32_Float: return 3
	case .RG_32_Float: return 2
	case .R_32_Float: return 1
	case .RGBA_8_Norm: return 4
	case .RG_8_Norm: return 2
	case .R_8_Norm: return 1
	case .R_8_UInt: return 1
	}

	return 0
}

get_shader_input_format :: proc(name: string, type: Shader_Input_Type) -> Pixel_Format {
	default_type := get_shader_input_default_type(name, type)

	if default_type != .Unknown {
		switch default_type {
		case .Position: return .RGB_32_Float
		case .UV: return .RG_32_Float
		case .Color: return .RGBA_8_Norm
		case .Unknown: unreachable()
		}
	}

	switch type {
	case .F32: return .R_32_Float
	case .Vec2: return .RG_32_Float
	case .Vec3: return .RGB_32_Float
	case .Vec4: return .RGBA_32_Float
	}

	return .Unknown
}

vec3_from_vec2 :: proc(v: Vec2) -> Vec3 {
	return {
		v.x, v.y, 0,
	}
}

frame_cstring :: proc(str: string, loc := #caller_location) -> cstring {
	return strings.clone_to_cstring(str, s.frame_allocator, loc)
}


@(require_results)
matrix_ortho3d_f32 :: proc "contextless" (left, right, bottom, top, near, far: f32) -> Mat4 #no_bounds_check {
	m: Mat4

	m[0, 0] = +2 / (right - left)
	m[1, 1] = +2 / (top - bottom)
	m[2, 2] = +1
	m[0, 3] = -(right + left)   / (right - left)
	m[1, 3] = -(top   + bottom) / (top - bottom)
	m[2, 3] = 0
	m[3, 3] = 1

	return m
}

make_default_projection :: proc(w, h: int) -> matrix[4,4]f32 {
	return matrix_ortho3d_f32(0, f32(w), f32(h), 0, 0.001, 2)
}

FONT_DEFAULT_ATLAS_SIZE :: 1024

update_font :: proc(fh: Font_Handle) {
	font := &s.fonts[fh]
	font_dirty_rect: [4]f32

	tw := FONT_DEFAULT_ATLAS_SIZE

	if fs.ValidateTexture(&s.fs, &font_dirty_rect) {
		fdr := font_dirty_rect

		r := Rect {
			fdr[0],
			fdr[1],
			fdr[2] - fdr[0],
			fdr[3] - fdr[1],
		}

		x := int(r.x)
		y := int(r.y)
		w := int(fdr[2]) - int(fdr[0])
		h := int(fdr[3]) - int(fdr[1])

		expanded_pixels := make([]Color, w * h, frame_allocator)
		start := x + tw * y

		for i in 0..<w*h {
			px := i%w
			py := i/w

			dst_pixel_idx := (px) + (py * w)
			src_pixel_idx := start + (px) + (py * tw)

			src := s.fs.textureData[src_pixel_idx]
			expanded_pixels[dst_pixel_idx] = {255,255,255, src}
		}

		rb.update_texture(font.atlas.handle, slice.reinterpret([]u8, expanded_pixels), r)
	}
}

set_font :: proc(fh: Font_Handle) {
	fh := fh

	if s.batch_font == fh {
		return
	}

	s.batch_font = fh

	if s.batch_font != FONT_NONE {
		update_font(s.batch_font)
	}

	if fh == 0 {
		fh = s.default_font
	}

	font := &s.fonts[fh]
	fs.SetFont(&s.fs, font.fontstash_handle)
}

DEPTH_START :: -1 + DEPTH_INCREMENT
DEPTH_INCREMENT :: (1.0/10000000.0)

_ :: jpeg
_ :: bmp
_ :: png
_ :: tga

Color_F32 :: [4]f32

f32_color_from_color :: proc(color: Color) -> Color_F32 {
	return {
		f32(color.r) / 255,
		f32(color.g) / 255,
		f32(color.b) / 255,
		f32(color.a) / 255,
	}
}

vec3 :: proc(v2: Vec2, z: f32) -> Vec3 {
	return {
		v2.x, v2.y, z,
	}
}

get_next_depth :: proc() -> f32 {
	d := s.depth
	s.depth += s.depth_increment
	return d
}
