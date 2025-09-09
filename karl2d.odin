package karl2d

import "base:runtime"
import "core:mem"
import "core:log"
import "core:math"
import "core:math/linalg"
import "core:slice"
import "core:strings"
import "core:reflect"

import "core:image"
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
             allocator := context.allocator, loc := #caller_location) -> ^State {
	assert(s == nil, "Don't call 'init' twice.")

	s = new(State, allocator, loc)
	s.allocator = allocator
	s.custom_context = context

	s.width = window_width
	s.height = window_height

	s.win = WINDOW_INTERFACE_WIN32
	win = s.win

	window_state_alloc_error: runtime.Allocator_Error
	s.window_state, window_state_alloc_error = mem.alloc(win.state_size())
	log.assertf(window_state_alloc_error == nil, "Failed allocating memory for window state: %v", window_state_alloc_error)

	win.init(s.window_state, window_width, window_height, window_title, allocator)
	s.window = win.window_handle()

	s.rb = BACKEND_D3D11
	rb = s.rb
	rb_alloc_error: runtime.Allocator_Error
	s.rb_state, rb_alloc_error = mem.alloc(rb.state_size())
	log.assertf(rb_alloc_error == nil, "Failed allocating memory for rendering backend: %v", rb_alloc_error)
	s.proj_matrix = make_default_projection(window_width, window_height)
	s.view_matrix = 1
	rb.init(s.rb_state, s.window, window_width, window_height, allocator)
	s.vertex_buffer_cpu = make([]u8, VERTEX_BUFFER_MAX, allocator, loc)
	white_rect: [16*16*4]u8
	slice.fill(white_rect[:], 255)
	s.shape_drawing_texture = rb.load_texture(white_rect[:], 16, 16)

	s.default_shader = load_shader(string(DEFAULT_SHADER_SOURCE))

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

	rb.destroy_texture(s.shape_drawing_texture)
	destroy_shader(s.default_shader)
	rb.shutdown()
	delete(s.vertex_buffer_cpu, s.allocator)

	win.shutdown()

	a := s.allocator
	free(s.window_state, a)
	free(s.rb_state, a)
	free(s, a)
	s = nil
}

// Clear the backbuffer with supplied color.
clear :: proc(color: Color) {
	rb.clear(color)
}

// Present the backbuffer. Call at end of frame to make everything you've drawn appear on the screen.
present :: proc() {
	draw_current_batch()
	rb.present()
}

// Call at start or end of frame to process all events that have arrived to the window.
//
// WARNING: Not calling this will make your program impossible to interact with.
process_events :: proc() {
	s.keys_went_up = {}
	s.keys_went_down = {}
	s.mouse_delta = {}
	s.mouse_wheel_delta = 0

	win.process_events()

	events := win.get_events()

	for &event in events {
		switch &e in event {
		case Window_Event_Close_Wanted:
			s.shutdown_wanted = true

		case Window_Event_Key_Went_Down:
			s.keys_went_down[e.key] = true
			s.keys_is_held[e.key] = true

		case Window_Event_Key_Went_Up:
			s.keys_is_held[e.key] = false
			s.keys_went_up[e.key] = true

		case Window_Event_Mouse_Move:
			prev_pos := s.mouse_position
			s.mouse_position = e.position
			s.mouse_delta = prev_pos - s.mouse_position

		case Window_Event_Mouse_Wheel:
			s.mouse_wheel_delta = e.delta
		}
	}

	win.clear_events()
}

get_screen_width :: proc() -> int {
	return rb.get_swapchain_width()
}

get_screen_height :: proc() -> int  {
	return rb.get_swapchain_height()
}

set_window_position :: proc(x: int, y: int) {
	win.set_position(x, y)
}

set_window_size :: proc(width: int, height: int) {
	panic("Not implemented")
}

// Flushes the current batch. This sends off everything to the GPU that has been queued in the
// current batch. Normally, you do not need to do this manually. It is done automatically when these
// procedures run:
// 
// - present
// - set_camera
// - set_shader
// - set_shader_constant
// - draw_texture_* IF previous draw did not use the same texture (1)
// - draw_rect_*, draw_circle_* IF previous draw did not use the shapes drawing texture (2)
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
// TODO: Name of this proc? submit_current_batch, flush_current_batch, draw_current_batch
draw_current_batch :: proc() {
	shader := s.batch_shader.? or_else s.default_shader
	rb.draw(shader, s.batch_texture, s.proj_matrix * s.view_matrix, s.vertex_buffer_cpu[:s.vertex_buffer_cpu_used])
	s.vertex_buffer_cpu_used = 0
}

//-------//
// INPUT //
//-------//

// Returns true if a keyboard key went down between the current and the previous frame. Set when
// 'process_events' runs (probably once per frame).
key_went_down :: proc(key: Keyboard_Key) -> bool {
	return s.keys_went_down[key]
}

// Returns true if a keyboard key went up (was released) between the current and the previous frame.
// Set when 'process_events' runs (probably once per frame).
key_went_up :: proc(key: Keyboard_Key) -> bool {
	return s.keys_went_up[key]
}

// Returns true if a keyboard is currently being held down. Set when 'process_events' runs (probably
// once per frame).
key_is_held :: proc(key: Keyboard_Key) -> bool {
	return s.keys_is_held[key]
}

mouse_button_went_down :: proc(button: Mouse_Button) -> bool {
	panic("not implemented")
}

mouse_button_went_up :: proc(button: Mouse_Button) -> bool {
	panic("not implemented")
}

mouse_button_is_held :: proc(button: Mouse_Button) -> bool {
	panic("not implemented")
}

get_mouse_wheel_delta :: proc() -> f32 {
	return s.mouse_wheel_delta
}

get_mouse_position :: proc() -> Vec2 {
	return s.mouse_position
}

//---------//
// DRAWING //
//---------//

draw_rect :: proc(r: Rect, c: Color) {
	if s.batch_texture != TEXTURE_NONE && s.batch_texture != s.shape_drawing_texture {
		draw_current_batch()
	}

	s.batch_texture = s.shape_drawing_texture

	batch_vertex({r.x, r.y}, {0, 0}, c)
	batch_vertex({r.x + r.w, r.y}, {1, 0}, c)
	batch_vertex({r.x + r.w, r.y + r.h}, {1, 1}, c)
	batch_vertex({r.x, r.y}, {0, 0}, c)
	batch_vertex({r.x + r.w, r.y + r.h}, {1, 1}, c)
	batch_vertex({r.x, r.y + r.h}, {0, 1}, c)
}

draw_rect_ex :: proc(r: Rect, origin: Vec2, rot: f32, c: Color) {
	if s.batch_texture != TEXTURE_NONE && s.batch_texture != s.shape_drawing_texture {
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
	
	batch_vertex(tl, {0, 0}, c)
	batch_vertex(tr, {1, 0}, c)
	batch_vertex(br, {1, 1}, c)
	batch_vertex(tl, {0, 0}, c)
	batch_vertex(br, {1, 1}, c)
	batch_vertex(bl, {0, 1}, c)
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
	if s.batch_texture != TEXTURE_NONE && s.batch_texture != s.shape_drawing_texture {
		draw_current_batch()
	}

	s.batch_texture = s.shape_drawing_texture

	prev := center + {radius, 0}
	for s in 1..=segments {
		sr := (f32(s)/f32(segments)) * 2*math.PI
		rot := linalg.matrix2_rotate(sr)
		p := center + rot * Vec2{radius, 0}
			

		batch_vertex(prev, {0, 0}, color)
		batch_vertex(p, {1, 0}, color)
		batch_vertex(center, {1, 1}, color)

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

	if s.batch_texture != TEXTURE_NONE && s.batch_texture != tex.handle {
		draw_current_batch()
	}

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

	s.batch_texture = tex.handle
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

	batch_vertex(tl, uv0, c)
	batch_vertex(tr, uv1, c)
	batch_vertex(br, uv2, c)
	batch_vertex(tl, uv3, c)
	batch_vertex(br, uv4, c)
	batch_vertex(bl, uv5, c)
}

draw_text :: proc(text: string, pos: Vec2, font_size: f32, color: Color) {
	
}

//--------------------//
// TEXTURE MANAGEMENT //
//--------------------//

load_texture_from_file :: proc(filename: string) -> Texture {
	img, img_err := image.load_from_file(filename, options = {.alpha_add_if_missing}, allocator = context.temp_allocator)

	if img_err != nil {
		log.errorf("Error loading texture %v: %v", filename, img_err)
		return {}
	}

	backend_tex := rb.load_texture(img.pixels.buf[:], img.width, img.height)

	return {
		handle = backend_tex,
		width = img.width,
		height = img.height,
	}
}

destroy_texture :: proc(tex: Texture) {
	rb.destroy_texture(tex.handle)
}


//---------//
// SHADERS //
//---------//

load_shader :: proc(shader_source: string, layout_formats: []Shader_Input_Format = {}) -> Shader {
	handle, desc := rb.load_shader(shader_source, context.temp_allocator, layout_formats)

	if handle == SHADER_NONE {
		log.error("Failed loading shader")
		return {}
	}

	shd := Shader {
		handle = handle,
		constant_buffers = make([]Shader_Constant_Buffer, len(desc.constant_buffers), s.allocator),
		constant_lookup = make(map[string]Shader_Constant_Location, s.allocator),
		inputs = slice.clone(desc.inputs, s.allocator),
		input_overrides = make([]Shader_Input_Value_Override, len(desc.inputs), s.allocator),
	}

	for &input in shd.inputs {
		input.name = strings.clone(input.name, s.allocator)
	}

	for cb_idx in 0..<len(desc.constant_buffers) {
		cb_desc := &desc.constant_buffers[cb_idx]

		shd.constant_buffers[cb_idx] = {
			cpu_data = make([]u8, desc.constant_buffers[cb_idx].size, s.allocator),
		}

		for &v in cb_desc.variables {
			if v.name == "" {
				continue
			}

			shd.constant_lookup[strings.clone(v.name, s.allocator)] = v.loc

			switch v.name {
			case "mvp":
				shd.constant_builtin_locations[.MVP] = v.loc
			}
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
		
		input_offset += shader_input_format_size(input.format)
	}

	shd.vertex_size = input_offset

	return shd
}

destroy_shader :: proc(shader: Shader) {
	rb.destroy_shader(shader.handle)

	for c in shader.constant_buffers {
		delete(c.cpu_data)
	}
	
	delete(shader.constant_buffers)

	for k, _ in shader.constant_lookup {
		delete(k)
	}

	delete(shader.constant_lookup)
	for i in shader.inputs {
		delete(i.name)
	}
	delete(shader.inputs)
	delete(shader.input_overrides)
}

get_default_shader :: proc() -> Shader {
	return s.default_shader
}

set_shader :: proc(shader: Maybe(Shader)) {
	if maybe_handle_equal(shader, s.batch_shader) {
		return
	}

	draw_current_batch()
	s.batch_shader = shader
}

set_shader_constant :: proc(shd: Shader, loc: Shader_Constant_Location, val: any) {
	draw_current_batch()

	if int(loc.buffer_idx) >= len(shd.constant_buffers) {
		log.warnf("Constant buffer idx %v is out of bounds", loc.buffer_idx)
		return
	}

	sz := reflect.size_of_typeid(val.id)
	b := &shd.constant_buffers[loc.buffer_idx]

	if int(loc.offset) + sz > len(b.cpu_data) {
		log.warnf("Constant buffer idx %v is trying to be written out of bounds by at offset %v with %v bytes", loc.buffer_idx, loc.offset, size_of(val))
		return
	}

	mem.copy(&b.cpu_data[loc.offset], val.data, sz)
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

shader_input_format_size :: proc(f: Shader_Input_Format) -> int {
	switch f {
	case .Unknown: return 0
	case .RGBA32_Float: return 32
	case .RGBA8_Norm: return 4
	case .RGBA8_Norm_SRGB: return 4
	case .RGB32_Float: return 12
	case .RG32_Float: return 8
	case .R32_Float: return 4
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
	s.proj_matrix = make_default_projection(s.width, s.height)

	if c, c_ok := camera.?; c_ok {
		origin_trans := linalg.matrix4_translate(vec3_from_vec2(-c.origin))
		translate := linalg.matrix4_translate(vec3_from_vec2(c.target))
		scale := linalg.matrix4_scale(Vec3{1/c.zoom, 1/c.zoom, 1})
		rot := linalg.matrix4_rotate_f32(c.rotation * math.RAD_PER_DEG, {0, 0, 1})
		camera_matrix := translate * scale * rot * origin_trans
		s.view_matrix = linalg.inverse(camera_matrix)
	} else {
		s.view_matrix = 1
	}
}

screen_to_world :: proc(pos: Vec2, camera: Camera) -> Vec2 {
	panic("not implemented")
}

//------//
// MISC //
//------//

set_scissor_rect :: proc(scissor_rect: Maybe(Rect)) {
	panic("not implemented")
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

// A two dimensinal vector.
Vec2 :: [2]f32

// A three dimensinal vector.
Vec3 :: [3]f32

// A 4x4 column-major matrix.
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
BLANK :: Color { 0, 0, 0, 0}

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

Camera :: struct {
	target: Vec2,
	origin: Vec2,
	rotation: f32,
	zoom: f32,
}

Shader_Handle :: distinct Handle

SHADER_NONE :: Shader_Handle {}

Shader :: struct {
	handle: Shader_Handle,
	constant_buffers: []Shader_Constant_Buffer,
	constant_lookup: map[string]Shader_Constant_Location,
	constant_builtin_locations: [Shader_Builtin_Constant]Maybe(Shader_Constant_Location),

	inputs: []Shader_Input,
	input_overrides: []Shader_Input_Value_Override,
	default_input_offsets: [Shader_Default_Inputs]int,
	vertex_size: int,
}

Shader_Constant_Buffer :: struct {
	cpu_data: []u8,
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
	format: Shader_Input_Format,
}

Shader_Constant_Location :: struct {
	buffer_idx: u32,
	offset: u32,
}

Shader_Input_Format :: enum {
	Unknown,
	RGBA32_Float,
	RGBA8_Norm,
	RGBA8_Norm_SRGB,
	RGB32_Float,
	RG32_Float,
	R32_Float,
}

Handle :: hm.Handle
Texture_Handle :: distinct Handle
TEXTURE_NONE :: Texture_Handle {}

// This keeps track of the internal state of the library. Usually, you do not need to poke at it.
// It is created and kept as a global variable when 'init' is called. However, 'init' also returns
// the pointer to it, so you can later use 'set_internal_state' to restore it (after for example hot
// reload).
State :: struct {
	allocator: runtime.Allocator,
	custom_context: runtime.Context,
	win: Window_Interface,
	window_state: rawptr,
	rb: Rendering_Backend_Interface,
	rb_state: rawptr,
	
	shutdown_wanted: bool,

	mouse_position: Vec2,
	mouse_delta: Vec2,
	mouse_wheel_delta: f32,

	keys_went_down: #sparse [Keyboard_Key]bool,
	keys_went_up: #sparse [Keyboard_Key]bool,
	keys_is_held: #sparse [Keyboard_Key]bool,

	window: Window_Handle,
	width: int,
	height: int,

	shape_drawing_texture: Texture_Handle,
	batch_camera: Maybe(Camera),
	batch_shader: Maybe(Shader),
	batch_texture: Texture_Handle,

	view_matrix: Mat4,
	proj_matrix: Mat4,

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

// Used by API builder. Everything after this constant will not be in karl2d.doc.odin
API_END :: true

batch_vertex :: proc(v: Vec2, uv: Vec2, color: Color) {
	v := v

	if s.vertex_buffer_cpu_used == len(s.vertex_buffer_cpu) {
		panic("Must dispatch here")
	}

	shd := s.batch_shader.? or_else s.default_shader

	base_offset := s.vertex_buffer_cpu_used
	pos_offset := shd.default_input_offsets[.Position]
	uv_offset := shd.default_input_offsets[.UV]
	color_offset := shd.default_input_offsets[.Color]
	
	mem.set(&s.vertex_buffer_cpu[base_offset], 0, shd.vertex_size)

	if pos_offset != -1 {
		(^Vec2)(&s.vertex_buffer_cpu[base_offset + pos_offset])^ = {v.x, v.y}
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
		sz := shader_input_format_size(input.format)

		if o.used != 0 {
			mem.copy(&s.vertex_buffer_cpu[base_offset + override_offset], raw_data(&o.val), o.used)
		}

		override_offset += sz
	}
	
	s.vertex_buffer_cpu_used += shd.vertex_size
}


VERTEX_BUFFER_MAX :: 1000000
DEFAULT_SHADER_SOURCE :: #load("shader.hlsl")

@(private="file")
s: ^State
win: Window_Interface
rb: Rendering_Backend_Interface

maybe_handle_equal :: proc(m1: Maybe($T), m2: Maybe(T)) -> bool {
	if m1 == nil && m2 == nil {
		return true
	}

	m1v, m1v_ok := m1.?
	m2v, m2v_ok := m2.?

	if !m1v_ok || !m2v_ok {
		return false
	}

	return m1v.handle == m2v.handle
}

get_shader_input_default_type :: proc(name: string, type: Shader_Input_Type) -> Shader_Default_Inputs {
	if name == "POS" && type == .Vec2 {
		return .Position
	} else if name == "UV" && type == .Vec2 {
		return .UV
	} else if name == "COL" && type == .Vec4 {
		return .Color
	}

	return .Unknown
}

get_shader_input_format :: proc(name: string, type: Shader_Input_Type) -> Shader_Input_Format {
	default_type := get_shader_input_default_type(name, type)

	if default_type != .Unknown {
		switch default_type {
		case .Position: return .RG32_Float
		case .UV: return .RG32_Float
		case .Color: return .RGBA8_Norm
		case .Unknown: unreachable()
		}
	}

	switch type {
	case .F32: return .R32_Float
	case .Vec2: return .RG32_Float
	case .Vec3: return .RGB32_Float
	case .Vec4: return .RGBA32_Float
	}

	return .Unknown
}

vec3_from_vec2 :: proc(v: Vec2) -> Vec3 {
	return {
		v.x, v.y, 0,
	}
}

temp_cstring :: proc(str: string, loc := #caller_location) -> cstring {
	return strings.clone_to_cstring(str, context.temp_allocator, loc)
}

make_default_projection :: proc(w, h: int) -> matrix[4,4]f32 {
	return linalg.matrix_ortho3d_f32(0, f32(w), f32(h), 0, 0.001, 2)
}

_ :: bmp
_ :: png
_ :: tga
