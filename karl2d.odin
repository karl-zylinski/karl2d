#+vet explicit-allocators

package karl2d

import "base:runtime"
import "core:mem"
import "log"
import "core:math"
import "core:math/linalg"
import "core:slice"
import "core:strings"
import "core:reflect"
import "core:os"
import "core:time"

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
//
// `screen_width` and `screen_height` refer to the the resolution of the drawable area of the
// window. The window might be slightly larger due borders and headers.
init :: proc(
	screen_width: int,
	screen_height: int,
	window_title: string,
	options := Init_Options {},
	allocator := context.allocator,
	loc := #caller_location
) -> ^State {
	assert(s == nil, "Don't call 'init' twice.")
	context.allocator = allocator

	s = new(State, allocator, loc)

	// This is the same type of arena as the default temp allocator. This arena is for allocations
	// that have a lifetime of "one frame". They are valid until you call `present()`, at which
	// point the frame allocator is cleared.
	s.frame_allocator = runtime.arena_allocator(&s.frame_arena)
	frame_allocator = s.frame_allocator

	s.allocator = allocator

	s.win = WINDOW_INTERFACE
	win = s.win

	// We alloc memory for the windowing backend and pass the blob of memory to it.
	window_state_alloc_error: runtime.Allocator_Error
	s.window_state, window_state_alloc_error = mem.alloc(win.state_size(), allocator = allocator)
	log.assertf(window_state_alloc_error == nil, "Failed allocating memory for window state: %v", window_state_alloc_error)

	win.init(s.window_state, screen_width, screen_height, window_title, options, allocator)

	// This is a OS-independent handle that we can pass to any rendering backend.
	s.window = win.window_handle()

	// See `config.odin` for how this is picked.
	s.rb = RENDER_BACKEND

	// Depending on backend the depth starts at `0` or `-1` and is counted in different directions.
	s.depth_increment = DEPTH_INCREMENT * f32(math.sign(s.rb.depth_increment_sign()))
	s.depth_start = s.rb.depth_start() + s.depth_increment

	s.depth = s.depth_start
	rb = s.rb
	rb_alloc_error: runtime.Allocator_Error
	s.rb_state, rb_alloc_error = mem.alloc(rb.state_size(), allocator = allocator)
	log.assertf(rb_alloc_error == nil, "Failed allocating memory for rendering backend: %v", rb_alloc_error)
	s.proj_matrix = make_default_projection(win.get_width(), win.get_height())
	s.view_matrix = 1

	// Boot up the render backend. It will render into our previously created window.
	rb.init(s.rb_state, s.window, win.get_width(), win.get_height(), allocator)

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
	s.default_shader = load_shader_from_bytes(rb.default_shader_vertex_source(), rb.default_shader_fragment_source())
	s.batch_shader = s.default_shader

	// FontStash enables us to bake fonts from TTF files on-the-fly.
	fs.Init(&s.fs, FONT_DEFAULT_ATLAS_SIZE, FONT_DEFAULT_ATLAS_SIZE, .TOPLEFT)
	fs.SetAlignVertical(&s.fs, .TOP)

	DEFAULT_FONT_DATA :: #load("roboto.ttf")

	// Dummy element so font with index 0 means 'no font'.
	append_nothing(&s.fonts)

	s.default_font = load_font_from_bytes(DEFAULT_FONT_DATA)
	_set_font(s.default_font)

	return s
}

// Updates the internal state of the library. Call this early in the frame to make sure inputs and
// frame times are up-to-date.
//
// Returns a bool that says if the player has attempted to close the window. It's up to the
// application to decide if it wants to shut down or if it (for example) wants to show a 
// confirmation dialogue.
//
// Commonly used for creating the "main loop" of a game: `for k2.update() {}`
//
// To get more control over how the frame is set up, you can skip calling this proc and instead use
// the procs it calls directly:
//
//// for {
////     k2.reset_frame_allocator()
////     k2.calculate_frame_time()
////     k2.process_events()
////     
////     k2.clear(k2.BLUE)
////     k2.present()
////     
////     if k2.close_window_requested() {
////         break
////     }
//// }
update :: proc() -> bool {
	reset_frame_allocator()
	calculate_frame_time()
	process_events()
	return !close_window_requested()
}

// Returns true the user has pressed the close button on the window, or used a key stroke such as
// ALT+F4 on Windows. The application can decide if it wants to shut down or if it wants to show
// some kind of confirmation dialogue.
//
// Called by `update`, but can be called manually if you need more control.
close_window_requested :: proc() -> bool {
	return s.close_window_requested
}

// Closes the window and cleans up Karl2D's internal state.
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

// Clear the "screen" with the supplied color. By default this will clear your window. But if you
// have set a Render Texture using the `set_render_texture` procedure, then that Render Texture will
// be cleared instead.
clear :: proc(color: Color) {
	draw_current_batch()
	rb.clear(s.batch_render_target, color)

	// This is problematic -- if you switch from backbuffer drawing to a render texture and back
	// again, then the depth will be messed with. Should we rethink our depth usage and always use
	// "painter's algorithm" instead?
	s.depth = s.depth_start
}

// The library may do some internal allocations that have the lifetime of a single frame. This
// procedure empties that Frame Allocator.
//
// Called as part of `update`, but can be called manually if you need more control.
reset_frame_allocator :: proc() {
	free_all(s.frame_allocator)
}

// Calculates how long the previous frame took and how it has been since the application started.
// You can fetch the calculated values using `get_frame_time` and `get_time`.
//
// Called as part of `update`, but can be called manually if you need more control.
calculate_frame_time :: proc() {
	now := time.now()

	if s.prev_frame_time != {} {
		since := time.diff(s.prev_frame_time, now)
		s.frame_time = f32(time.duration_seconds(since))
	}

	s.prev_frame_time = now

	if s.start_time == {} {
		s.start_time = time.now()
	}

	s.time = time.duration_seconds(time.since(s.start_time))
}

// Present the drawn stuff to the player. Also known as "flipping the backbuffer": Call at end of
// frame to make everything you've drawn appear on the screen.
//
// When you draw using for example `draw_texture`, then that stuff is drawn to an invisible texture
// called a "backbuffer". This makes sure that we don't see half-drawn frames. So when you are happy
// with a frame and want to show it to the player, call this procedure.
//
// WebGL note: WebGL does the backbuffer flipping automatically. But you should still call this to
// make sure that all rendering has been sent off to the GPU (as it calls `draw_current_batch()`).
present :: proc() {
	draw_current_batch()
	rb.present()
}

// Process all events that have arrived from the platform APIs. This includes keyboard, mouse,
// gamepad and window events. This procedure processes and stores the information that procs like
// `key_went_down` need.
//
// Called by `update`, but can be called manually if you need more control.
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
			s.close_window_requested = true

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

			s.mouse_position.x = e.position.x
			s.mouse_position.y = e.position.y

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

		case Window_Event_Focused:			

		case Window_Event_Unfocused:
			for k in Keyboard_Key {
				if s.key_is_held[k] {
					s.key_is_held[k] = false
					s.key_went_up[k] = true
				}
			}

			for b in Mouse_Button {
				if s.mouse_button_is_held[b] {
					s.mouse_button_is_held[b] = false
					s.mouse_button_went_up[b] = true
				}
			}

			for gp in 0..<MAX_GAMEPADS {
				for b in Gamepad_Button {
					if s.gamepad_button_is_held[gp][b] {
						s.gamepad_button_is_held[gp][b] = false
						s.gamepad_button_went_up[gp][b] = true
					}
				}
			}
		}
	}

	win.clear_events()
}

// Returns how many seconds the previous frame took. Often a tiny number such as 0.016 s.
//
// This value is updated when `calculate_frame_time()` runs (which is also called by `update()`).
get_frame_time :: proc() -> f32 {
	return s.frame_time
}

// Returns how many seconds has elapsed since the game started. This is a `f64` number, giving good
// precision when the application runs for a long time.
//
// This value is updated when `calculate_frame_time()` runs (which is also called by `update()`).
get_time :: proc() -> f64 {
	return s.time
}

// Gets the width of the drawing area within the window.
get_screen_width :: proc() -> int {
	return win.get_width()
}

// Gets the height of the drawing area within the window.
get_screen_height :: proc() -> int  {
	return win.get_height()
}

// Moves the window.
//
// This does nothing for web builds.
set_window_position :: proc(x: int, y: int) {
	win.set_position(x, y)
}

// Resize the window to a new size. While the user cannot resize windows with 
// `window_mode == .Windowed_Resizable`, this procedure will resize them.
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

// Use to change between windowed mode, resizable windowed mode and fullscreen
set_window_mode :: proc(window_mode: Window_Mode) {
	win.set_window_mode(window_mode)
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
// - set_blend_mode
// - set_render_texture
// - clear
// - draw_texture_* IF previous draw did not use the same texture (1)
// - draw_rect_*, draw_circle_*, draw_line IF previous draw did not use the shapes drawing texture (2)
// 
// (1) When drawing textures, the current texture is fed into the active shader. Everything within
//     the same batch must use the same texture. So drawing with a new texture forces the current to
//     be drawn. You can combine several textures into an atlas to get bigger batches.
//
// (2) In order to use the same shader for shapes drawing and textured drawing, the shapes drawing
//     uses a blank, white texture. For the same reasons as (1), drawing something else than shapes
//     before drawing a shape will break up the batches. In a future update I'll add so that you can
//     set your own shapes drawing texture, making it possible to combine it with a bigger atlas.
//
// The batch has maximum size of VERTEX_BUFFER_MAX bytes. The shader dictates how big a vertex is
// so the maximum number of vertices that can be drawn in each batch is
// VERTEX_BUFFER_MAX / shader.vertex_size
draw_current_batch :: proc() {
	if s.vertex_buffer_cpu_used == 0 {
		return
	}

	_update_font(s.batch_font)

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
// 'process_events' runs.
key_went_down :: proc(key: Keyboard_Key) -> bool {
	return s.key_went_down[key]
}

// Returns true if a keyboard key went up (was released) between the current and the previous frame.
// Set when 'process_events' runs.
key_went_up :: proc(key: Keyboard_Key) -> bool {
	return s.key_went_up[key]
}

// Returns true if a keyboard is currently being held down. Set when 'process_events' runs.
key_is_held :: proc(key: Keyboard_Key) -> bool {
	return s.key_is_held[key]
}

// Returns true if a mouse button went down between the current and the previous frame. Specify
// which mouse button using the `button` parameter.
//
// Set when 'process_events' runs.
mouse_button_went_down :: proc(button: Mouse_Button) -> bool {
	return s.mouse_button_went_down[button]
}

// Returns true if a mouse button went up (was released) between the current and the previous frame.
// Specify which mouse button using the `button` parameter.
//
// Set when 'process_events' runs.
mouse_button_went_up :: proc(button: Mouse_Button) -> bool {
	return s.mouse_button_went_up[button]
}

// Returns true if a mouse button is currently being held down. Specify which mouse button using the
// `button` parameter. Set when 'process_events' runs.
mouse_button_is_held :: proc(button: Mouse_Button) -> bool {
	return s.mouse_button_is_held[button]
}

// Returns how many clicks the mouse wheel has scrolled between the previous and current frame.
get_mouse_wheel_delta :: proc() -> f32 {
	return s.mouse_wheel_delta
}

// Returns the mouse position, measured from the top-left corner of the window.
get_mouse_position :: proc() -> Vec2 {
	return s.mouse_position
}

// Returns how many pixels the mouse moved between the previous and the current frame.
get_mouse_delta :: proc() -> Vec2 {
	return s.mouse_delta
}

// Returns true if a gamepad with the supplied index is connected. The parameter should be a value
// between 0 and MAX_GAMEPADS.
is_gamepad_active :: proc(gamepad: Gamepad_Index) -> bool {
	return win.is_gamepad_active(gamepad)
}

// Returns true if a gamepad button went down between the previous and the current frame.
gamepad_button_went_down :: proc(gamepad: Gamepad_Index, button: Gamepad_Button) -> bool {
	if gamepad < 0 || gamepad >= MAX_GAMEPADS {
		return false
	}

	return s.gamepad_button_went_down[gamepad][button]
}

// Returns true if a gamepad button went up (was released) between the previous and the current
// frame.
gamepad_button_went_up :: proc(gamepad: Gamepad_Index, button: Gamepad_Button) -> bool {
	if gamepad < 0 || gamepad >= MAX_GAMEPADS {
		return false
	}

	return s.gamepad_button_went_up[gamepad][button]
}

// Returns true if a gamepad button is currently held down.
//
// The "trigger buttons" on some gamepads also have an analogue "axis value" associated with them.
// Fetch that value using `get_gamepad_axis()`.
gamepad_button_is_held :: proc(gamepad: Gamepad_Index, button: Gamepad_Button) -> bool {
	if gamepad < 0 || gamepad >= MAX_GAMEPADS {
		return false
	}

	return s.gamepad_button_is_held[gamepad][button]
}

// Returns the value of analogue gamepad axes such as the thumbsticks and trigger buttons. The value
// is in the range -1 to 1 for sticks and 0 to 1 for trigger buttons.
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

// Draw a colored rectangle. The rectangles have their (x, y) position in the top-left corner of the
// rectangle.
draw_rect :: proc(r: Rect, c: Color) {
	if s.vertex_buffer_cpu_used + s.batch_shader.vertex_size * 6 > len(s.vertex_buffer_cpu) {
		draw_current_batch()
	}

	if s.batch_texture != s.shape_drawing_texture {
		draw_current_batch()
	}

	s.batch_texture = s.shape_drawing_texture

	z := f32(0)

	batch_vertex({r.x, r.y, z}, {0, 0}, c)
	batch_vertex({r.x + r.w, r.y, z}, {1, 0}, c)
	batch_vertex({r.x + r.w, r.y + r.h, z}, {1, 1}, c)
	batch_vertex({r.x, r.y, z}, {0, 0}, c)
	batch_vertex({r.x + r.w, r.y + r.h, z}, {1, 1}, c)
	batch_vertex({r.x, r.y + r.h, z}, {0, 1}, c)
}

// Creates a rectangle from a position and a size and draws it.
draw_rect_vec :: proc(pos: Vec2, size: Vec2, c: Color) {
	draw_rect({pos.x, pos.y, size.x, size.y}, c)
}

// Draw a rectangle with a custom origin and rotation.
//
// The origin says which point the rotation rotates around. If the origin is `(0, 0)`, then the
// rectangle rotates around the top-left corner of the rectangle. If it is `(rect.w/2, rect.h/2)`
// then the rectangle rotates around its center.
//
// Rotation unit: Radians.
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
		sin_rot := math.sin(rot)
		cos_rot := math.cos(rot)
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

// Draw the outline of a rectangle with a specific thickness. The outline is drawn using four
// rectangles.
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

// Draw a circle with a certain center and radius. Note the `segments` parameter: This circle is not
// perfect! It is drawn using a number of "cake segments".
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

// Like `draw_circle` but only draws the outer edge of the circle.
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

// Draws a line from `start` to `end` of a certain thickness.
draw_line :: proc(start: Vec2, end: Vec2, thickness: f32, color: Color) {
	p := Vec2{start.x, start.y}
	s := Vec2{linalg.length(end - start), thickness}

	origin := Vec2 {0, thickness*0.5}
	r := Rect {p.x, p.y, s.x, s.y}

	rot := math.atan2(end.y - start.y, end.x - start.x)

	draw_rect_ex(r, origin, rot, color)
}

// Draw a texture at a specific position. The texture will be drawn with its top-left corner at
// position `pos`.
//
// Load textures using `load_texture_from_file` or `load_texture_from_bytes`.
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

// Draw a section of a texture at a specific position. `rect` is a rectangle measured in pixels. It
// tells the procedure which part of the texture to display. The texture will be drawn with its
// top-left corner at position `pos`.
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

// Draw a texture by taking a section of the texture specified by `src` and draw it into the area of
// the screen specified by `dst`. You can also rotate the texture around an origin point of your
// choice.
//
// Tip: Use `k2.get_texture_rect(tex)` for `src` if you want to draw the whole texture.
//
// Rotation unit: Radians.
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
		sin_rot := math.sin(rotation)
		cos_rot := math.cos(rotation)
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

	// HACK: We ask the render backend if this texture needs flipping. The idea is that GL will
	// flip render textures, so we need to automatically unflip them.
	//
	// Could we do something with the projection matrix while drawing into those render textures
	// instead? I tried that, but couldn't get it to work.
	if rb.texture_needs_vertical_flip(tex.handle) {
		flip_y = !flip_y
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

// Tells you how much space some text of a certain size will use on the screen. The font used is the
// default font. The return value contains the width and height of the text.
measure_text :: proc(text: string, font_size: f32) -> Vec2 {
	fs.SetSize(&s.fs, font_size)
	b: [4]f32
	fs.TextBounds(&s.fs, text, bounds = &b)
	return {b[2] - b[0], b[3] - b[1]}
}

// Tells you how much space some text of a certain size will use on the screen, using a custom font.
// The return value contains the width and height of the text.
measure_text_ex :: proc(font_handle: Font, text: string, font_size: f32) -> Vec2 {
	_set_font(font_handle)
	fs.SetSize(&s.fs, font_size)
	b: [4]f32
	fs.TextBounds(&s.fs, text, bounds = &b)
	return {b[2] - b[0], b[3] - b[1]}
}

// Draw text at a position with a size. This uses the default font. `pos` will be equal to the 
// top-left position of the text.
draw_text :: proc(text: string, pos: Vec2, font_size: f32, color := BLACK) {
	draw_text_ex(s.default_font, text, pos, font_size, color)
}

// Draw text at a position with a size, using a custom font. `pos` will be equal to the  top-left
// position of the text.
draw_text_ex :: proc(font_handle: Font, text: string, pos: Vec2, font_size: f32, color := BLACK) {
	if int(font_handle) >= len(s.fonts) {
		return
	}

	_set_font(font_handle)
	font := &s.fonts[font_handle]
	fs.SetSize(&s.fs, font_size)
	iter := fs.TextIterInit(&s.fs, pos.x, pos.y, text)

	q: fs.Quad
	for fs.TextIterNext(&s.fs, &iter, &q) {
		if iter.codepoint == '\n' {
			iter.nexty += font_size
			iter.nextx = pos.x
			continue
		}

		if iter.codepoint == '\t' {
			// This is not really correct, but I'll replace it later when I redo the font stuff.
			iter.nextx += 2*font_size
			continue
		}

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

//--------------------//
// TEXTURE MANAGEMENT //
//--------------------//

// Create an empty texture.
create_texture :: proc(width: int, height: int, format: Pixel_Format) -> Texture {
	h := rb.create_texture(width, height, format)

	return {
		handle = h,
		width = width,
		height = height,
	}
}

// Load a texture from disk and upload it to the GPU so you can draw it to the screen.
// Supports PNG, BMP, TGA and baseline PNG. Note that progressive PNG files are not supported!
//
// The `options` parameter can be used to specify things things such as premultiplication of alpha.
load_texture_from_file :: proc(filename: string, options: Load_Texture_Options = {}) -> Texture {
	when FILESYSTEM_SUPPORTED {
		load_options := image.Options {
			.alpha_add_if_missing,
		}

		if .Premultiply_Alpha in options {
			load_options += { .alpha_premultiply }
		}

		img, img_err := image.load_from_file(filename, options = load_options, allocator = s.frame_allocator)

		if img_err != nil {
			log.errorf("Error loading texture '%v': %v", filename, img_err)
			return {}
		}

		return load_texture_from_bytes_raw(img.pixels.buf[:], img.width, img.height, .RGBA_8_Norm)
	} else {
		log.errorf("load_texture_from_file failed: OS %v has no filesystem support! Tip: Use load_texture_from_bytes(#load(\"the_texture.png\")) instead.", ODIN_OS)
		return {}
	}
}

// Load a texture from a byte slice and upload it to the GPU so you can draw it to the screen.
// Supports PNG, BMP, TGA and baseline PNG. Note that progressive PNG files are not supported!
//
// The `options` parameter can be used to specify things things such as premultiplication of alpha.
load_texture_from_bytes :: proc(bytes: []u8, options: Load_Texture_Options = {}) -> Texture {
	load_options := image.Options {
		.alpha_add_if_missing,
	}

	if .Premultiply_Alpha in options {
		load_options += { .alpha_premultiply }
	}

	img, img_err := image.load_from_bytes(bytes, options = load_options, allocator = s.frame_allocator)

	if img_err != nil {
		log.errorf("Error loading texture: %v", img_err)
		return {}
	}

	return load_texture_from_bytes_raw(img.pixels.buf[:], img.width, img.height, .RGBA_8_Norm)
}

// Load raw texture data. You need to specify the data, size and format of the texture yourself.
// This assumes that there is no header in the data. If your data has a header (you read the data
// from a file on disk), then please use `load_texture_from_bytes` instead.
load_texture_from_bytes_raw :: proc(bytes: []u8, width: int, height: int, format: Pixel_Format) -> Texture {
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

// Destroy a texture, freeing up any memory it has used on the GPU.
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

// Create a texture that you can render into. Meaning that you can draw into it instead of drawing
// onto the screen. Use `set_render_texture` to enable this Render Texture for drawing.
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

// Destroy a Render_Texture previously created using `create_render_texture`.
destroy_render_texture :: proc(render_texture: Render_Texture) {
	rb.destroy_texture(render_texture.texture.handle)
	rb.destroy_render_target(render_texture.render_target)
}

// Make all rendering go into a texture instead of onto the screen. Create the render texture using
// `create_render_texture`. Pass `nil` to resume drawing onto the screen.
set_render_texture :: proc(render_texture: Maybe(Render_Texture)) {
	if rt, rt_ok := render_texture.?; rt_ok {
		if s.batch_render_target == rt.render_target {
			return
		}

		draw_current_batch()
		s.batch_render_target = rt.render_target
		s.proj_matrix = make_default_projection(rt.texture.width, rt.texture.height)
	} else {
		if s.batch_render_target == RENDER_TARGET_NONE {
			return
		}

		draw_current_batch()
		s.batch_render_target = RENDER_TARGET_NONE
		s.proj_matrix = make_default_projection(win.get_width(), win.get_height())
	}
}

//-------//
// FONTS //
//-------//

// Loads a font from disk and returns a handle that represents it.
load_font_from_file :: proc(filename: string) -> Font {
	when !FILESYSTEM_SUPPORTED {
		log.errorf("load_font_from_file failed: OS %v has no filesystem support! Tip: Use load_font_from_bytes(#load(\"the_font.ttf\")) instead.", ODIN_OS)
		return {}
	}

	if data, data_ok := os.read_entire_file(filename, frame_allocator); data_ok {
		return load_font_from_bytes(data)
	}

	return FONT_NONE
}

// Loads a font from a block of memory and returns a handle that represents it.
load_font_from_bytes :: proc(data: []u8) -> Font {
	font := fs.AddFontMem(&s.fs, "", data, false)
	h := Font(len(s.fonts))

	append(&s.fonts, Font_Data {
		fontstash_handle = font,
		atlas = {
			handle = rb.create_texture(FONT_DEFAULT_ATLAS_SIZE, FONT_DEFAULT_ATLAS_SIZE, .RGBA_8_Norm),
			width = FONT_DEFAULT_ATLAS_SIZE,
			height = FONT_DEFAULT_ATLAS_SIZE,
		},
	})

	return h
}

// Destroy a font previously loaded using `load_font_from_file` or `load_font_from_bytes`.
destroy_font :: proc(font: Font) {
	if int(font) >= len(s.fonts) {
		return
	}

	f := &s.fonts[font]
	rb.destroy_texture(f.atlas.handle)	

	// TODO fontstash has no "destroy font" proc... I should make my own version of fontstash
	delete(s.fs.fonts[f.fontstash_handle].glyphs)
	s.fs.fonts[f.fontstash_handle].glyphs = {}
}

// Returns the built-in font of Karl2D (the font is known as "roboto")
get_default_font :: proc() -> Font {
	return s.default_font
}


//---------//
// SHADERS //
//---------//

// Load a shader from a vertex and fragment shader file. If the vertex and fragment shaders live in
// the same file, then pass it twice.
//
// `layout_formats` can in many cases be left default initialized. It is used to specify the format
// of the vertex shader inputs. By formats this means the format that you pass on the CPU side.
load_shader_from_file :: proc(
	vertex_filename: string,
	fragment_filename: string,
	layout_formats: []Pixel_Format = {}
) -> Shader {
	vertex_source, vertex_source_ok := os.read_entire_file(vertex_filename, frame_allocator)

	if !vertex_source_ok {
		log.errorf("Failed loading shader %s", vertex_filename)
		return {}
	}

	fragment_source: []byte
	
	if fragment_filename == vertex_filename {
		fragment_source = vertex_source
	} else {
		fragment_source_ok: bool
		fragment_source, fragment_source_ok = os.read_entire_file(fragment_filename, frame_allocator)

		if !fragment_source_ok {
			log.errorf("Failed loading shader %s", fragment_filename)
			return {}
		}
	}

	return load_shader_from_bytes(vertex_source, fragment_source, layout_formats)
}

// Load a vertex and fragment shader from a block of memory. See `load_shader_from_file` for what
// `layout_formats` means.
load_shader_from_bytes :: proc(
	vertex_shader_bytes: []byte,
	fragment_shader_bytes: []byte,
	layout_formats: []Pixel_Format = {},
) -> Shader {
	handle, desc := rb.load_shader(
		vertex_shader_bytes,
		fragment_shader_bytes,
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

// Destroy a shader previously loaded using `load_shader_from_file` or `load_shader_from_bytes`
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

// Fetches the shader that Karl2D uses by default.
get_default_shader :: proc() -> Shader {
	return s.default_shader
}

// The supplied shader will be used for subsequent drawing. Return to the default shader by calling
// `set_shader(nil)`.
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

// Set the value of a constant (also known as uniform in OpenGL). Look up shader constant locations
// (the kind of value needed for `loc`) by running `loc := shader.constant_lookup["constant_name"]`.
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

// Sets the value of a shader input (also known as a shader attribute). There are three default
// shader inputs known as position, texcoord and color. If you have shader with additional inputs,
// then you can use this procedure to set their values. This is a way to feed per-object data into
// your shader.
//
// `input` should be the index of the input and `val` should be a value of the correct size.
//
// You can modify which type that is expected for `val` by passing a custom `layout_formats` when
// you load the shader.
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

// Returns the number of bytes that a pixel in a texture uses.
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

// Make Karl2D use a camera. Return to the "default camera" by passing `nil`. All drawing operations
// will use this camera until you again change it.
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

// Transform a point `pos` that lives on the screen to a point in the world. This can be useful for
// bringing (for example) mouse positions (k2.get_mouse_position()) into world-space.
screen_to_world :: proc(pos: Vec2, camera: Camera) -> Vec2 {
	return (get_camera_world_matrix(camera) * Vec4 { pos.x, pos.y, 0, 1 }).xy
}

// Transform a point `pos` that lices in the world to a point on the screen. This can be useful when
// you need to take a position in the world and compare it to a screen-space point.
world_to_screen :: proc(pos: Vec2, camera: Camera) -> Vec2 {
	return (get_camera_view_matrix(camera) * Vec4 { pos.x, pos.y, 0, 1 }).xy
}

// Get the matrix that `screen_to_world` and `world_to_screen` uses to do their transformations.
//
// A view matrix is essentially the world transform matrix of the camera, but inverted. In other
// words, instead of bringing the camera in front of things in the world, we bring everything in the
// world "in front of the camera".
//
// Instead of constructing the camera matrix and doing a matrix inverse, here we just do the
// maths in "backwards order". I.e. a camera transform matrix would be:
//
//    target_translate * rot * scale * offset_translate
//
// but we do
//
//    inv_offset_translate * inv_scale * inv_rot * inv_target_translate
//
// This is faster, since matrix inverses are expensive.
get_camera_view_matrix :: proc(c: Camera) -> Mat4 {
	inv_target_translate := linalg.matrix4_translate(vec3_from_vec2(-c.target))
	inv_rot := linalg.matrix4_rotate_f32(c.rotation, {0, 0, 1})
	inv_scale := linalg.matrix4_scale(Vec3{c.zoom, c.zoom, 1})
	inv_offset_translate := linalg.matrix4_translate(vec3_from_vec2(c.offset))

	return inv_offset_translate * inv_scale * inv_rot * inv_target_translate
}

// Get the matrix that brings something in front of the camera.
get_camera_world_matrix :: proc(c: Camera) -> Mat4 {
	offset_translate := linalg.matrix4_translate(vec3_from_vec2(-c.offset))
	rot := linalg.matrix4_rotate_f32(-c.rotation, {0, 0, 1})
	scale := linalg.matrix4_scale(Vec3{1/c.zoom, 1/c.zoom, 1})
	target_translate := linalg.matrix4_translate(vec3_from_vec2(c.target))

	return target_translate * rot * scale * offset_translate
}

//------//
// MISC //
//------//

// Choose how the alpha channel is used when mixing half-transparent color with what is already
// drawn. The default is the .Alpha mode, but you also have the option of using .Premultiply_Alpha.
set_blend_mode :: proc(mode: Blend_Mode) {
	if s.batch_blend_mode == mode {
		return
	}

	draw_current_batch()
	s.batch_blend_mode = mode
}

// Make everything outside of the screen-space rectangle `scissor_rect` not render. Disable the
// scissor rectangle by running `set_scissor_rect(nil)`.
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

// A rectangle that sits at position (x, y) and has size (w, h).
Rect :: struct {
	x, y: f32,
	w, h: f32,
}

// An RGBA (Red, Green, Blue, Alpha) color. Each channel can have a value between 0 and 255.
Color :: [4]u8

// See the folder examples/palette for a demo that shows all colors
BLACK        :: Color { 0, 0, 0, 255 }
WHITE        :: Color { 255, 255, 255, 255 }
BLANK        :: Color { 0, 0, 0, 0 }
GRAY         :: Color { 183, 183, 183, 255 } 
DARK_GRAY    :: Color { 66, 66, 66, 255} 
BLUE         :: Color { 25, 198, 236, 255 }
DARK_BLUE    :: Color { 7, 47, 88, 255 }
LIGHT_BLUE   :: Color { 200, 230, 255, 255 }
GREEN        :: Color { 16, 130, 11, 255 }
DARK_GREEN   :: Color { 6, 53, 34, 255}
LIGHT_GREEN  :: Color { 175, 246, 184, 255 }
ORANGE       :: Color { 255, 114, 0, 255 }
RED          :: Color { 239, 53, 53, 255 }
DARK_RED     :: Color { 127, 10, 10, 255 }
LIGHT_RED    :: Color { 248, 183, 183, 255 }
BROWN        :: Color { 115, 78, 74, 255 }
DARK_BROWN   :: Color { 50, 36, 32, 255 }
LIGHT_BROWN  :: Color { 146, 119, 119, 255 }
PURPLE       :: Color { 155, 31, 232, 255 }
LIGHT_PURPLE :: Color { 217, 172, 248, 255 }
MAGENTA      :: Color { 209, 17, 209, 255 }
YELLOW       :: Color { 250, 250, 129, 255 }
LIGHT_YELLOW :: Color { 253, 250, 222, 255 }

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

color_alpha :: proc(c: Color, a: u8) -> Color {
	return {c.r, c.g, c.b, a}
}

Texture :: struct {
	// The render-backend specific texture identifier.
	handle: Texture_Handle,

	// The horizontal size of the texture, measured in pixels.
	width: int,

	// The vertical size of the texture, measure in pixels.
	height: int,
}

Load_Texture_Option :: enum {
	// Will multiply the alpha value of the each pixel into the its RGB values. Useful if you want
	// to use `set_blend_mode(.Premultiplied_Alpha)`
	Premultiply_Alpha,
}

Load_Texture_Options :: bit_set[Load_Texture_Option]

Blend_Mode :: enum {
	Alpha,

	// Requires the alpha-channel to be multiplied into texture RGB channels. You can automatically
	// do this using the `Premultiply_Alpha` option when loading a texture.
	Premultiplied_Alpha,
}

// A render texture is a texture that you can draw into, instead of drawing to the screen. Create
// one using `create_render_texture`.
Render_Texture :: struct {
	// The texture that the things will be drawn into. You can use this as a normal texture, for
	// example, you can pass it to `draw_texture`.
	texture: Texture,

	// The render backend's internal identifier. It describes how to use the texture as something
	// the render backend can draw into.
	render_target: Render_Target_Handle,
}

Texture_Filter :: enum {
	Point,  // Similar to "nearest neighbor". Pixly texture scaling.
	Linear, // Smoothed texture scaling.
}

Camera :: struct {
	// Where the camera looks.
	target: Vec2,

	// By default `target` will be the position of the upper-left corner of the camera. Use this
	// offset to change that. If you set the offset to half the size of the camera view, then the
	// target position will end up in the middle of the scren.
	offset: Vec2,

	// Rotate the camera (unit: radians)
	rotation: f32,

	// Zoom the camera. A bigger value means "more zoom".
	//
	// To make a certain amount of pixels always occupy the height of the camera, set the zoom to:
	//
	//     k2.get_screen_height()/wanted_pixel_height
	zoom: f32,
}

Window_Mode :: enum {
	Windowed,
	Windowed_Resizable,
	Borderless_Fullscreen,
}

Init_Options :: struct {
	window_mode: Window_Mode,
}

Shader_Handle :: distinct Handle

SHADER_NONE :: Shader_Handle {}

Shader_Constant_Location :: struct {
	offset: int,
	size: int,
}

Shader :: struct {
	// The render backend's internal identifier.
	handle: Shader_Handle,

	// We store the CPU-side value of all constants in a single buffer to have less allocations.
	// The 'constants' array says where in this buffer each constant is, and 'constant_lookup'
	// maps a name to a constant location.
	constants_data: []u8,
	constants: []Shader_Constant_Location,

	// Look up named constants. If you have a constant (uniform) in the shader called "bob", then
	// you can find its location by running `shader.constant_lookup["bob"]`. You can then use that
	// location in combination with `set_shader_constant`
	constant_lookup: map[string]Shader_Constant_Location,

	// Maps built in constant types such as "model view projection matrix" to a location.
	constant_builtin_locations: [Shader_Builtin_Constant]Maybe(Shader_Constant_Location),

	texture_bindpoints: []Texture_Handle,

	// Used to lookup bindpoints of textures. You can then set the texture by overriding
	// `shader.texture_bindpoints[shader.texture_lookup["some_tex"]] = some_texture.handle`
	texture_lookup: map[string]int,
	default_texture_index: Maybe(int),

	inputs: []Shader_Input,

	// Overrides the value of a specific vertex input.
	//
	// It's recommended you use `override_shader_input` to modify these overrides.
	input_overrides: []Shader_Input_Value_Override,
	default_input_offsets: [Shader_Default_Inputs]int,

	// How many bytes a vertex uses gives the input of the shader.
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

Font_Data :: struct {
	atlas: Texture,

	// internal
	fontstash_handle: int,
}

Handle :: hm.Handle
Texture_Handle :: distinct Handle
Render_Target_Handle :: distinct Handle
Font :: distinct int

FONT_NONE :: Font {}
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
	
	close_window_requested: bool,

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

	default_font: Font,
	fonts: [dynamic]Font_Data,
	shape_drawing_texture: Texture_Handle,
	batch_font: Font,
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

	// Time when the first call to `new_frame` happened
	start_time: time.Time,
	prev_frame_time: time.Time,

	// "dt"
	frame_time: f32,

	time: f64,
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
	Backtick        = 96,

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

_update_font :: proc(fh: Font) {
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

// Not for direct use. Specify font to `draw_text_ex`
_set_font :: proc(fh: Font) {
	fh := fh

	if s.batch_font == fh {
		return
	}

	draw_current_batch()

	s.batch_font = fh

	if s.batch_font != FONT_NONE {
		_update_font(s.batch_font)
	}

	if fh == 0 {
		fh = s.default_font
	}

	font := &s.fonts[fh]
	fs.SetFont(&s.fs, font.fontstash_handle)
}

DEPTH_INCREMENT :: (1.0/1000000.0)

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

FILESYSTEM_SUPPORTED :: ODIN_OS != .JS && ODIN_OS != .Freestanding