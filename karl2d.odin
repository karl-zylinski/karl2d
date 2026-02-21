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
import "core:time"
import "core:encoding/endian"

import fs "vendor:fontstash"

import "core:image"
import "core:image/jpeg"
import "core:image/bmp"
import "core:image/png"
import "core:image/tga"

import hm "core:container/handle_map"

import stbv "vendor:stb/vorbis"

//-----------------------------------------------//
// SETUP, WINDOW MANAGEMENT AND FRAME MANAGEMENT //
//-----------------------------------------------//

// Opens a window and initializes some internal state. The internal state will use `allocator` for
// all dynamically allocated memory. The return value can be ignored unless you need to later call
// `set_internal_state`.
//
// `screen_width` and `screen_height` refer to the resolution of the drawable area of the window.
// The window might be slightly larger due to borders and headers.
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

	when ODIN_OS == .Windows {
		s.platform = PLATFORM_WINDOWS
	} else when ODIN_OS == .JS {
		s.platform = PLATFORM_WEB
	} else when ODIN_OS == .Linux {
		s.platform = PLATFORM_LINUX
	} else when ODIN_OS == .Darwin {
		s.platform = PLATFORM_MAC
	} else {
		#panic("Unsupported platform")
	}

	pf = s.platform

	// We allocate memory for the windowing backend and pass the blob of memory to it.
	platform_state_alloc_error: runtime.Allocator_Error
	
	s.platform_state, platform_state_alloc_error = mem.alloc(
		pf.state_size(),
		allocator = allocator,
	)

	log.assertf(
		platform_state_alloc_error == nil,
		"Failed allocating memory for platform state: %v",
		platform_state_alloc_error,
	)

	pf.init(s.platform_state, screen_width, screen_height, window_title, options, allocator)

	// This is an OS-independent handle that we can pass to any rendering backend.
	window_render_glue := pf.get_window_render_glue()

	// See `render_backend_chooser.odin` for how this is picked.
	s.render_backend = RENDER_BACKEND

	rb = s.render_backend
	rb_alloc_error: runtime.Allocator_Error
	s.render_backend_state, rb_alloc_error = mem.alloc(rb.state_size(), allocator = allocator)
	log.assertf(rb_alloc_error == nil, "Failed allocating memory for rendering backend: %v", rb_alloc_error)
	s.proj_matrix = make_default_projection(pf.get_screen_width(), pf.get_screen_height())
	s.view_matrix = 1

	// Boot up the render backend. It will render into our previously created window.
	rb.init(s.render_backend_state, window_render_glue, pf.get_screen_width(), pf.get_screen_height(), allocator)

	// The vertex buffer is created in a render backend-independent way. It is passed to the
	// render backend each frame as part of `draw_current_batch()`.
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

	DEFAULT_FONT_DATA :: #load("default_fonts/roboto.ttf")

	// Dummy element so font with index 0 means 'no font'.
	append_nothing(&s.fonts)

	s.default_font = load_font_from_bytes(DEFAULT_FONT_DATA)
	_set_font(s.default_font)

	// Audio
	{
		VORBIS_STATE_SIZE :: 500 * mem.Kilobyte
		s.vorbis_alloc = {
			alloc_buffer = make([^]u8, VORBIS_STATE_SIZE, s.allocator),
			alloc_buffer_length_in_bytes = VORBIS_STATE_SIZE,
		}

		s.audio_backend = AUDIO_BACKEND
		ab = s.audio_backend

		audio_alloc_error: runtime.Allocator_Error
		s.audio_backend_state, audio_alloc_error = mem.alloc(ab.state_size(), allocator = s.allocator)
		log.assertf(audio_alloc_error == nil, "Failed allocating memory for audio backend: %v", audio_alloc_error)
		ab.init(s.audio_backend_state, s.allocator)
		s.playing_sounds = make([dynamic]Playing_Sound, s.allocator)
	}

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
////     k2.update_audio_mixer()
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
	update_audio_mixer()
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

	// Audio
	{
		ab.shutdown()
		delete(s.playing_sounds)
		hm.dynamic_destroy(&s.sound_instances)
		hm.dynamic_destroy(&s.sound_data)
		free(s.audio_backend_state, s.allocator)
	}

	delete(s.events)
	destroy_font(s.default_font)
	rb.destroy_texture(s.shape_drawing_texture)
	destroy_shader(s.default_shader)
	rb.shutdown()
	delete(s.vertex_buffer_cpu, s.allocator)

	pf.shutdown()

	fs.Destroy(&s.fs)
	delete(s.fonts)

	a := s.allocator
	free(s.platform_state, a)
	free(s.render_backend_state, a)
	free(s, a)
	s = nil
}

// Clear the "screen" with the supplied color. By default this will clear your window. But if you
// have set a Render Texture using the `set_render_texture` procedure, then that Render Texture will
// be cleared instead.
clear :: proc(color: Color) {
	draw_current_batch()
	rb.clear(s.batch_render_target, color)
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

	runtime.clear(&s.events)
	pf.get_events(&s.events)

	for &event in s.events {
		switch &e in event {
		case Event_Close_Window_Requested:
			s.close_window_requested = true

		case Event_Key_Went_Down:
			s.key_went_down[e.key] = true
			s.key_is_held[e.key] = true

		case Event_Key_Went_Up:
			s.key_went_up[e.key] = true
			s.key_is_held[e.key] = false

		case Event_Mouse_Button_Went_Down:
			s.mouse_button_went_down[e.button] = true
			s.mouse_button_is_held[e.button] = true

		case Event_Mouse_Button_Went_Up:
			s.mouse_button_went_up[e.button] = true
			s.mouse_button_is_held[e.button] = false

		case Event_Mouse_Move:
			prev_pos := s.mouse_position

			s.mouse_position.x = e.position.x
			s.mouse_position.y = e.position.y

			s.mouse_delta = s.mouse_position - prev_pos

		case Event_Mouse_Wheel:
			s.mouse_wheel_delta = e.delta

		case Event_Gamepad_Button_Went_Down:
			if e.gamepad < MAX_GAMEPADS {
				s.gamepad_button_went_down[e.gamepad][e.button] = true
				s.gamepad_button_is_held[e.gamepad][e.button] = true
			}

		case Event_Gamepad_Button_Went_Up:
			if e.gamepad < MAX_GAMEPADS {
				s.gamepad_button_went_up[e.gamepad][e.button] = true
				s.gamepad_button_is_held[e.gamepad][e.button] = false
			}

		case Event_Screen_Resize:
			rb.resize_swapchain(e.width, e.height)
			s.proj_matrix = make_default_projection(e.width, e.height)

		case Event_Window_Focused:			

		case Event_Window_Unfocused:
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

		case Event_Window_Scale_Changed:
			// Doesn't do anything, only here so people can fetch it via `get_events()`.
		}
	}
}

// Fetch a list of all events that happened this frame. Most games can use the `key_is_held`, 
// `mouse_button_went_down` etc procedures to check input state. But if you want a list of events
// instead, then you can use this. These events will also include things like "Window Focus" events
// and "Window Resize" events.
//
// Note: Gamepad axis movement (analogue sticks and analogue triggers) are _not_ events. Those can
// only be queried using `k2.get_gamepad_axis`.
//
// Warning: The returned slice is only valid during the current frame! You can make a clone of it
// using the `slice.clone` procedure (import `core:slice`).
get_events :: proc() -> []Event {
	return s.events[:]
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

// Resize the drawing area of the window (the screen) to a new size. While the user cannot resize
// windows with `window_mode == .Windowed_Resizable`, this procedure is able to resize such windows.
set_screen_size :: proc(width: int, height: int) {
	pf.set_screen_size(width, height)
	rb.resize_swapchain(width, height)
}

// Gets the width of the drawing area within the window.
get_screen_width :: proc() -> int {
	return pf.get_screen_width()
}

// Gets the height of the drawing area within the window.
get_screen_height :: proc() -> int  {
	return pf.get_screen_height()
}

// Moves the window.
//
// This does nothing for web builds.
set_window_position :: proc(x: int, y: int) {
	pf.set_window_position(x, y)
}

// Fetch the scale of the window. This usually comes from some DPI scaling setting in the OS.
// 1 means 100% scale, 1.5 means 150% etc.
//
// Karl2D does not do any automatic scaling. If you want a scaled resolution, then multiply the
// wanted resolution by the scale and send it into `set_screen_size`. You can use a camera and set
// the zoom to the window scale in order to make things the same percieved size.
get_window_scale :: proc() -> f32 {
	return pf.get_window_scale()
}

// Use to change between windowed mode, resizable windowed mode and fullscreen
set_window_mode :: proc(window_mode: Window_Mode) {
	pf.set_window_mode(window_mode)
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

	view_projection := s.proj_matrix * s.view_matrix
	for mloc, builtin in shader.constant_builtin_locations {
		constant, constant_ok := mloc.?

		if !constant_ok {
			continue
		}

		switch builtin {
		case .View_Projection_Matrix:
			if constant.size == size_of(view_projection) {
				dst := (^matrix[4,4]f32)(&shader.constants_data[constant.offset])
				dst^ = view_projection
			} 
		}
	}

	if def_tex_idx, has_def_tex_idx := shader.default_texture_index.?; has_def_tex_idx {
		shader.texture_bindpoints[def_tex_idx] = s.batch_texture
	}

	rb.draw(
		shader,
		s.batch_render_target,
		shader.texture_bindpoints,
		s.batch_scissor,
		s.batch_blend_mode,
		s.vertex_buffer_cpu[:s.vertex_buffer_cpu_used],
	)
	
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
	return pf.is_gamepad_active(gamepad)
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
	return pf.get_gamepad_axis(gamepad, axis)
}

// Set the left and right vibration motor speed. The range of left and right is 0 to 1. Note that on
// most gamepads, the left motor is "low frequency" and the right motor is "high frequency". They do
// not vibrate with the same speed.
set_gamepad_vibration :: proc(gamepad: Gamepad_Index, left: f32, right: f32) {
	pf.set_gamepad_vibration(gamepad, left, right)
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

	batch_vertex({r.x, r.y}, {0, 0}, c)
	batch_vertex({r.x + r.w, r.y}, {1, 0}, c)
	batch_vertex({r.x + r.w, r.y + r.h}, {1, 1}, c)
	batch_vertex({r.x, r.y}, {0, 0}, c)
	batch_vertex({r.x + r.w, r.y + r.h}, {1, 1}, c)
	batch_vertex({r.x, r.y + r.h}, {0, 1}, c)
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

	batch_vertex(tl, {0, 0}, c)
	batch_vertex(tr, {1, 0}, c)
	batch_vertex(br, {1, 1}, c)
	batch_vertex(tl, {0, 0}, c)
	batch_vertex(br, {1, 1}, c)
	batch_vertex(bl, {0, 1}, c)
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

	// Offset texcoords by half a texel (so they look at the center of the texel). This avoids
	// bleeding when sampling to the edge of a texture that is within a bigger atlas.
	up := (Vec2{src.x, src.y} + Vec2{0.5, 0.5}) / ts
	us := (Vec2{src.w, src.h} - Vec2{1.0, 1.0}) / ts
	
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

	batch_vertex(tl, uv0, c)
	batch_vertex(tr, uv1, c)
	batch_vertex(br, uv2, c)
	batch_vertex(tl, uv3, c)
	batch_vertex(br, uv4, c)
	batch_vertex(bl, uv5, c)
}

// Tells you how much space some text of a certain size will use on the screen. The font used is the
// default font. The return value contains the width and height of the text.
measure_text :: proc(text: string, font_size: f32) -> Vec2 {
	return measure_text_ex(s.default_font, text, font_size)
}

// Tells you how much space some text of a certain size will use on the screen, using a custom font.
// The return value contains the width and height of the text.
measure_text_ex :: proc(font_handle: Font, text: string, font_size: f32) -> Vec2 {
	if font_handle < 0 || int(font_handle) >= len(s.fonts) {
		return {}
	}

	font := s.fonts[font_handle]

	// Temporary until I rewrite the font caching system.
	_set_font(font_handle)

	// TextBounds from fontstash, but fixed and simplified for my purposes.
	// The version in there is broken.
	TextBounds :: proc(
		ctx:  ^fs.FontContext,
		font_idx: int,
		size: f32,
		text: string,
	) -> Vec2 {
		font  := fs.__getFont(ctx, font_idx)
		isize := i16(size * 10)

		x, y: f32
		max_x := x

		scale := fs.__getPixelHeightScale(font, f32(isize) / 10)
		previousGlyphIndex: fs.Glyph_Index = -1
		quad: fs.Quad
		lines := 1

		for codepoint in text {
			if codepoint == '\n' {
				x = 0
				lines += 1
				continue
			}

			if glyph, ok := fs.__getGlyph(ctx, font, codepoint, isize); ok {
				if glyph.xadvance > 0 {
					x += f32(int(f32(glyph.xadvance) / 10 + 0.5))
				} else {
					// updates x
					fs.__getQuad(ctx, font, previousGlyphIndex, glyph, scale, 0, &x, &y, &quad)
				}

				if x > max_x {
					max_x = x
				}

				previousGlyphIndex = glyph.index
			} else {
				previousGlyphIndex = -1
			}

		}
		return { max_x, f32(lines)*size }
	}

	return TextBounds(&s.fs, font.fontstash_handle, font_size, text)
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

//-------//
// AUDIO //
//-------//

// Play a sound previous created using `load_sound_from_file` or `load_sound_from_bytes` or
// `create_sound_instance`. The sound will be mixed when `update_audio_mixer` runs, which
// happens as part of `update`.
play_sound :: proc(snd: Sound, loop := false) {
	append(
		&s.playing_sounds,
		Playing_Sound {
			sound = snd,
			loop = loop,
		},
	)
}

// Set the volume of a sound. Range: 0 to 1, where 0 is silence and 1 is the original volume of the
// sound. The volume change will only affect this instance of the sound. Use `create_sound_instance`
// to create more instances without duplicating data.
set_sound_volume :: proc(snd: Sound, volume: f32) {
	d := hm.get(&s.sound_instances, snd)
	
	if d == nil {
		log.error("Cannot set volume, sound does not exist.")
		return
	}
	
	d.target_volume = clamp(volume, 0, 1)
}

// Set the pan of a sound. Range: -1 to 1, where -1 is full left, 0 is center and 1 is full right.
// The pan change will only affect this instance of the sound. Use `create_sound_instance` to create
// more instances without duplicating data.
set_sound_pan :: proc(snd: Sound, pan: f32) {
	d := hm.get(&s.sound_instances, snd)
	
	if d == nil {
		log.error("Cannot set pan, sound does not exist.")
		return
	}
	
	d.target_pan = clamp(pan, -1, 1)
}

// Set the pitch of a sound. Range: 0.01 to infinity, where 0.01 is the lowest pitch and higher
// values increase the pitch. The pitch change will only affect this instance of the sound. Use
// `create_sound_instance` to create more instances without duplicating data.
set_sound_pitch :: proc(snd: Sound, pitch: f32) {
	d := hm.get(&s.sound_instances, snd)
	
	if d == nil {
		log.error("Cannot set pitch, sound does not exist.")
		return
	}
	
	d.target_pitch = max(pitch, 0.01)
}

// Load a WAV file from disk. Returns a `Sound` which can be used with `play_sound`. Use 
// `create_sound_instance` to create more instances of the same sound without duplicating data.
//
// Currently only supports 16 bit WAV files.
load_sound_from_file :: proc(filename: string) -> Sound {
	when FILESYSTEM_SUPPORTED {
		data, data_ok := read_entire_file(filename, allocator = frame_allocator)

		if !data_ok {
			log.errorf("Failed loading sound %v", filename)
			return SOUND_NONE
		}

		return load_sound_from_bytes(data)
	} else {
		return SOUND_NONE
	}
}

// Load a sound some pre-loaded memory (for example using `#load("sound.wav")`). Returns a `Sound`
// which can be used with `play_sound`. Use `create_sound_instance` to create more instances of the
// same sound without duplicating data.
//
// Currently only supports 16 bit WAV data. Note that the data should be the entire WAV file,
// including the header. If your data does not include the header, then please use
// `load_sound_from_bytes_raw` instead.
load_sound_from_bytes :: proc(bytes: []byte) -> Sound {
	d := bytes

	if len(d) < 8 {
		log.error("Invalid WAV")
		return SOUND_NONE
	}

	if string(d[:4]) != "RIFF" {
		log.error("Invalid wav file: No RIFF identifier")
		return SOUND_NONE
	}

	d = d[4:]

	file_size, file_size_ok := endian.get_u32(d, .Little)

	if !file_size_ok {
		log.error("Invalid wav file: No size")
		return SOUND_NONE
	}

	if int(file_size) != len(bytes) - 8 {
		log.error("File size mismiatch")
		return SOUND_NONE
	}

	d = d[4:]

	if string(d[:4]) != "WAVE" {
		log.error("Invalid wav file: Not WAVE format")
		return SOUND_NONE
	}

	d = d[4:]

	sample_rate: u32
	samples: []u8

	format: Raw_Sound_Format

	for len(d) > 3 {
		blk_id := string(d[:4])

		d = d[4:]	

		if blk_id == "fmt " {
			blk_size, blk_size_ok := endian.get_u32(d, .Little)

			if !blk_size_ok {
				log.error("Invalid wav fmt block size")
				continue
			}

			d = d[4:]

			if int(blk_size) != 16 || len(d) < 16 {
				log.error("Invalid wav fmt block size")
				continue
			}

			sample_rate_ok: bool
			sample_rate, sample_rate_ok = endian.get_u32(d[4:8], .Little)

			if !sample_rate_ok {
				log.error("Failed reading sample rate from wav fmt block")
				sample_rate = 0
				continue
			}

			audio_format, audio_format_ok := endian.get_u16(d[0:2], .Little)

			if !audio_format_ok {
				log.error("Failed reading format from wav fmt block")
				continue
			}

			if audio_format == 1 {
				bits_per_sample, bits_per_sample_ok := endian.get_u16(d[14:16], .Little)

				if !bits_per_sample_ok {
					log.error("Failed reading bits per sample from wav fmt block")
					continue
				}

				switch bits_per_sample {
				case 8:
					format = .Integer8
				case 16:
					format = .Integer16
				case 32:
					format = .Integer32
				case:
					log.errorf("Unsupported bits per sample in wav fmt block: %v", bits_per_sample)
					continue
				}
			} else if audio_format == 3 {
				format = .Float
			} else {
				log.error("Invalid format in wav fmt block")
				continue
			}


			// Just need sample rate for now, so I disabled the rest...

			/*
			Wav_Fmt :: struct {
				audio_format:    u16,
				num_channels:    u16,
				sample_rate:     u32,
				byte_per_sec:    u32, // sample_rate * byte_per_bloc
				byte_per_bloc:   u16, // (num_channels * bits_per_sample) / 8
				bits_per_sample: u16,
			}

			audio_format, audio_format_ok := endian.get_u16(d[0:2], .Little)
			num_channels, num_channels_ok := endian.get_u16(d[2:4], .Little)
			sample_rate, sample_rate_ok := endian.get_u32(d[4:8], .Little)
			byte_per_sec, byte_per_sec_ok := endian.get_u32(d[8:12], .Little)
			byte_per_bloc, byte_per_bloc_ok := endian.get_u16(d[12:14], .Little)
			bits_per_sample, bits_per_sample_ok := endian.get_u16(d[14:16], .Little)

			if (
				!audio_format_ok ||
				!num_channels_ok ||
				!sample_rate_ok ||
				!byte_per_sec_ok ||
				!byte_per_bloc_ok ||
				!bits_per_sample_ok
			) {
				log.error("Failed reading wav fmt block")
				continue
			}

			fmt := Wav_Fmt {
				audio_format = audio_format,
				num_channels = num_channels,
				sample_rate = sample_rate,
				byte_per_sec = byte_per_sec,
				byte_per_bloc = byte_per_bloc,
				bits_per_sample = bits_per_sample,
			}

			sample_rate = int(fmt.sample_rate)
			*/
		} else if blk_id == "data" {
			data_size, data_size_ok := endian.get_u32(d, .Little)

			if !data_size_ok {
				log.error("Failed getting wav data size")
				continue
			}

			d = d[4:]

			if len(d) < int(data_size) {
				log.error("Data size larger than remaining wave buffer")
				continue
			}

			samples = d[:data_size]
		}
	}
	
	return load_sound_from_bytes_raw(samples, format, int(sample_rate))
}

// Load a sound from some raw audio data. You need to specify the data, format and sample rate of
// the sound yourself. This assumes that there is no header in the data. If your data has a header
// (you read the data from a file on disk), then please use `load_sound_from_bytes` instead.
load_sound_from_bytes_raw :: proc(bytes: []u8, format: Raw_Sound_Format, sample_rate: int) -> Sound {
	samples: []Audio_Sample

	switch format{
	case .Integer8:
		samples_u8 := slice.reinterpret([][2]u8, bytes)
		samples = make([]Audio_Sample, len(samples_u8), s.allocator)

		for idx in 0..<len(samples) {
			samples[idx] = {
				(f32(samples_u8[idx].x) - 128.0) / 128.0,
				(f32(samples_u8[idx].y) - 128.0) / 128.0,
			}
		}

	case .Integer16:
		samples_i16 := slice.reinterpret([][2]i16, bytes)
		samples = make([]Audio_Sample, len(samples_i16), s.allocator)

		for idx in 0..<len(samples) {
			samples[idx] = {
				f32(samples_i16[idx].x) / f32(max(i16)),
				f32(samples_i16[idx].y) / f32(max(i16)),
			}
		}

	case .Integer32:
		samples_i32 := slice.reinterpret([][2]i32, bytes)
		samples = make([]Audio_Sample, len(samples_i32), s.allocator)

		for idx in 0..<len(samples) {
			samples[idx] = {
				f32(samples_i32[idx].x) / f32(max(i32)),
				f32(samples_i32[idx].y) / f32(max(i32)),
			}
		}

	case .Float:
		samples = slice.clone(slice.reinterpret([]Audio_Sample, bytes), s.allocator)
	}

	snd_data := Sound_Data {
		sample_rate = sample_rate,
		samples = samples,
		instances = 1,
	}

	data_handle, data_handle_err := hm.add(&s.sound_data, snd_data)

	if data_handle_err != nil {
		log.errorf("Failed to load sound. Error: %v", data_handle_err)
		return SOUND_NONE
	}

	snd_inst := Sound_Instance {
		sound_data_handle = data_handle,
		volume = 1,
		target_volume = 1,
		pitch = 1,
		target_pitch = 1,
	}

	snd_handle, snd_handle_err := hm.add(&s.sound_instances, snd_inst)

	if snd_handle_err != nil {
		log.errorf("Failed to load sound. Error: %v", snd_handle_err)
		hm.remove(&s.sound_data, data_handle)
		return SOUND_NONE
	}

return snd_handle
}

// Makes a new sound that uses the same data as the original sound, but you can have different
// settings such as volume, pan and pitch. This makes it possible to play the same sound multiple
// times at once with different settings. The data is destroyed when all the instances (including
// the original instance) are destroyed.
create_sound_instance :: proc(snd: Sound) -> Sound {
	inst := hm.get(&s.sound_instances, snd)

	if inst == nil {
		log.error("Cannot create sound instance, sound does not exist.")
		return SOUND_NONE
	}

	data := hm.get(&s.sound_data, inst.sound_data_handle)

	if data == nil {
		log.error("Cannot create sound instance, sound data does not exist.")
		return SOUND_NONE
	}

	inst_copy := inst^
	snd_handle, snd_handle_err := hm.add(&s.sound_instances, inst_copy)

	if snd_handle_err != nil {
		log.errorf("Failed to create sound instance. Error: %v", snd_handle_err)
		return SOUND_NONE
	}

	data.instances += 1
	return snd_handle
}

// Destroy a sound instance. If this is the last instance that uses the same data, then the data
// will also be destroyed.
destroy_sound :: proc(snd: Sound) {
	inst := hm.get(&s.sound_instances, snd)

	if inst == nil {
		log.error("Trying to destroy invalid sound. It may already be destroyed, or the handle may be invalid.")
		return
	}

	data := hm.get(&s.sound_data, inst.sound_data_handle)

	if data == nil {
		log.error("Trying to destroy sound instance, but its data does not exist.")
		return
	}

	data.instances -= 1

	if data.instances == 0 {
		delete(data.samples, s.allocator)
		hm.remove(&s.sound_data, inst.sound_data_handle)
	}

	hm.remove(&s.sound_instances, snd)
}

load_audio_stream_from_file :: proc(filename: string) -> Audio_Stream {
	verr: stbv.Error
	v := stbv.open_filename(frame_cstring(filename), &verr, &s.vorbis_alloc)
	log.info(verr, v)
	return {}
}

// Update the audio mixer and feed more audio data into the audio backend. This is done
// automatically when `update` runs, so you normally don't need to call this manually.
//
// This procedure implements a custom software audio mixer. The backend is just fed the resulting
// mix. Therefore, you can see everything regarding how audio is processed in this procedure.
//
// Will only run if the audio backend is running low on audio data.
update_audio_mixer :: proc() {
	// If the sample rate of the backend is 44100 samples/second and AUDIO_MIX_CHUNK_SIZE is 1400
	// samples, then this procedure will only run roughly 44100/1400 = 31 times per second. This
	// gives a latency of up to (1.5 * (44100/1400)) = 47 milliseconds. Is it too big, or too small?
	// Perhaps we can use more low latency backends to push it down. Perhaps the backend should
	// control AUDIO_MIX_CHUNK_SIZE based on how low latency it can give us without stalling?
	if ab.remaining_samples() > (3 * AUDIO_MIX_CHUNK_SIZE)/2 {
		return
	}
	
	// We are going to go past the end of the mix_buffer, so just hop to the start instead. It's
	// 1 megabyte big, so hopping over a few bytes at the end is OK.
	if (s.mix_buffer_offset + AUDIO_MIX_CHUNK_SIZE) > len(s.mix_buffer) {
		s.mix_buffer_offset = 0
	}

	// A slice of the mixed samples we are going to output.
	out := s.mix_buffer[s.mix_buffer_offset:s.mix_buffer_offset + AUDIO_MIX_CHUNK_SIZE]
	
	// Zero out old mixed data from buffer (the buffer is "circular", there may be old stuff in
	// the `out` slice).
	slice.zero(out)

	// For usage when the sample rates of the playing sound and the mixer match.
	add :: proc(
		dest: []Audio_Sample,
		source: []Audio_Sample,
		num: int,
		volume_start: f32,
		volume_end: f32,
		pan_start: [2]f32,
		pan_end: [2]f32,
	) -> int {
		to_write := num

		if to_write > len(source) {
			to_write = len(source)
		}
		
		for samp_idx in 0..<to_write {
			t := f32(samp_idx) / f32(to_write)
			volume := math.lerp(volume_start, volume_end, t)
			pan := linalg.lerp(pan_start, pan_end, t)
			dest[samp_idx] += pan * source[samp_idx] * volume
		}

		return to_write
	}

	// For usage when the sample rates don't match. Needs a `dest_source_ratio` parameter that tells
	// us how the sample ratios relate. It's used for getting from indices from dest sample space
	// to source sample space.
	add_interpolate :: proc(
		dest: []Audio_Sample,
		source: []Audio_Sample,
		source_offset: f32,
		num_dest: int,
		dest_source_ratio: f32,
		volume_start: f32,
		volume_end: f32,
		pan_start: [2]f32,
		pan_end: [2]f32,
	) -> int {
		
		dest_idx: int
		for ; dest_idx < num_dest; dest_idx += 1 {
			src_pos := source_offset + f32(dest_idx) * dest_source_ratio
			src_idx := int(src_pos)
			
			if src_idx >= len(source) {
				break
			}

			src_next := min(src_idx + 1, len(source) - 1)
			frac := src_pos - f32(src_idx)

			prev_val := source[src_idx]
			cur_val := source[src_next]

			t := f32(dest_idx) / f32(num_dest)
			volume := math.lerp(volume_start, volume_end, t)
			pan := linalg.lerp(pan_start, pan_end, t)

			dest[dest_idx] += pan * linalg.lerp(prev_val, cur_val, frac) * volume
		}

		return dest_idx
	}

	for idx := 0; idx < len(s.playing_sounds); idx += 1 {
		ps := &s.playing_sounds[idx]
		inst := hm.get(&s.sound_instances, ps.sound)

		if inst == nil {
			log.error("Trying to play destroyed sound")
			unordered_remove(&s.playing_sounds, idx)
			idx -= 1
			continue
		}

		data := hm.get(&s.sound_data, inst.sound_data_handle)

		if data == nil {
			log.error("Trying to play sound with destroyed data")
			unordered_remove(&s.playing_sounds, idx)
			idx -= 1
			continue
		}

		// Before we get to the mixing we smoothly adjust pitch, volume and pan. We do this to avoid
		// clicks in the audio. The clicks happen because abrupt changes cause discontinuities in
		// the audio waveform. Understand: Sound does not happen because the waveform has a high
		// value, it happens because there is a sudden change in the waveform. Bigger change, bigger
		// sound.

		calc_adjust_parameter_delta :: proc(sample_rate: int, pitch: f32) -> f32 {
			RAMP_TIME :: 0.03
			ramp_samples := RAMP_TIME * f32(sample_rate) * pitch
			return AUDIO_MIX_CHUNK_SIZE / ramp_samples
		}

		move_towards :: proc(current: f32, target: f32, delta: f32) -> f32 {
			if abs(target - current) < delta {
				return target
			}

			dir := math.sign(target - current)
			return current + dir * delta
		}

		// We get the delta twice because we first need to move the pitch towards its target.
		adjust_parameter_delta := calc_adjust_parameter_delta(data.sample_rate, max(inst.pitch, 0.01))
		inst.pitch = max(move_towards(inst.pitch, inst.target_pitch, adjust_parameter_delta), 0.01)
		pitch := inst.pitch
		adjust_parameter_delta = calc_adjust_parameter_delta(data.sample_rate, pitch)

		// We can't just use the `volume_end` value for the volume. We are going to mix in
		// `AUDIO_MIX_CHUNK_SIZE` number of samples. We'd still get clicks in the sound if we hopped
		// to the ending volume. Instead, we calculate what the first sample should use and what
		// the last one should use. Then we feed those into the `add`/`add_interpolate` procedures.
		// It will lerp across the range as it is mixing in the samples.

		volume_start := clamp(inst.volume, 0, 1)
		volume_end := clamp(move_towards(inst.volume, inst.target_volume, adjust_parameter_delta), 0, 1)
		inst.volume = volume_end

		if volume_start == volume_end && volume_end == 0 {
			continue
		}
		
		pan_start := clamp(inst.pan, -1, 1)
		pan_end := clamp(move_towards(inst.pan, inst.target_pan, adjust_parameter_delta), -1, 1)
		inst.pan = pan_end
		
		// Use cos/sine to get a constant-power audio curve. This means that the sound won't get
		// quieter in the middle, but will instead just pan.
		pan_stereo_start := [2]f32 {
			math.cos((pan_start + 1) * math.PI / 4),
			math.sin((pan_start + 1) * math.PI / 4),
		}

		pan_stereo_end := [2]f32 {
			math.cos((pan_end + 1) * math.PI / 4),
			math.sin((pan_end + 1) * math.PI / 4),
		}

		interpolate := data.sample_rate != AUDIO_MIX_SAMPLE_RATE || pitch != 1
		num_mixed: int
		
		if interpolate {
			samples_per_mixer_sample := (pitch*f32(data.sample_rate))/f32(AUDIO_MIX_SAMPLE_RATE)

			num_mixed = add_interpolate(
				s.mix_buffer[s.mix_buffer_offset:],
				data.samples[ps.offset:],
				ps.offset_fraction,
				AUDIO_MIX_CHUNK_SIZE,
				samples_per_mixer_sample,
				volume_start,
				volume_end,
				pan_stereo_start,
				pan_stereo_end,
			)
			
			num_mixed_f32 := f32(num_mixed) * samples_per_mixer_sample
			fraction_advance := ps.offset_fraction + num_mixed_f32

			// The fraction advance may become larger than 1, in which case the offset needs to eat
			// the integer part.
			ps.offset += int(fraction_advance)
			
			ps.offset_fraction = linalg.fract(fraction_advance)
		} else {
			num_mixed = add(
				s.mix_buffer[s.mix_buffer_offset:],
				data.samples[ps.offset:],
				AUDIO_MIX_CHUNK_SIZE,
				volume_start,
				volume_end,
				pan_stereo_start,
				pan_stereo_end,
			)
			
			ps.offset += num_mixed
			ps.offset_fraction = 0
		}

		// We didn't mix all the samples! This means that we reached the end of the sound.
		if num_mixed < AUDIO_MIX_CHUNK_SIZE {
			if ps.loop {
				ps.offset = 0
				ps.offset_fraction = 0

				// The sound looped. Make sure to mix in the remaining samples from the start of the
				// sound!
				overflow := AUDIO_MIX_CHUNK_SIZE - num_mixed

				if interpolate {
					samples_per_mixer_sample := (pitch*f32(data.sample_rate))/f32(AUDIO_MIX_SAMPLE_RATE)

					num_mixed = add_interpolate(
						s.mix_buffer[s.mix_buffer_offset + num_mixed:],
						data.samples[ps.offset:],
						ps.offset_fraction,
						overflow,
						samples_per_mixer_sample,
						volume_start,
						volume_end,
						pan_stereo_start,
						pan_stereo_end,
					)

					num_mixed_f32 := f32(num_mixed) * samples_per_mixer_sample
					fraction_advance := ps.offset_fraction + num_mixed_f32
					ps.offset += int(fraction_advance)
					ps.offset_fraction = linalg.fract(fraction_advance)
				} else {
					num_mixed = add(
						s.mix_buffer[s.mix_buffer_offset + num_mixed:],
						data.samples[ps.offset:],
						overflow,
						volume_start,
						volume_end,
						pan_stereo_start,
						pan_stereo_end,
					)

					ps.offset += num_mixed
					ps.offset_fraction = 0
				}
			} else {
				unordered_remove(&s.playing_sounds, idx)
				idx -= 1
			}
		}
	}

	ab.feed(out)
	s.mix_buffer_offset += AUDIO_MIX_CHUNK_SIZE
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
		if rt.render_target == RENDER_TARGET_NONE {
			log.errorf("Invalid render texture: %v", rt)
			return
		}

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
		s.proj_matrix = make_default_projection(pf.get_screen_width(), pf.get_screen_height())
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

	if data, data_ok := read_entire_file(filename, frame_allocator); data_ok {
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
	vertex_source, vertex_source_ok := read_entire_file(vertex_filename, frame_allocator)

	if !vertex_source_ok {
		log.errorf("Failed loading shader %s", vertex_filename)
		return {}
	}

	fragment_source: []byte
	
	if fragment_filename == vertex_filename {
		fragment_source = vertex_source
	} else {
		fragment_source_ok: bool
		fragment_source, fragment_source_ok = read_entire_file(fragment_filename, frame_allocator)

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
			case "view_projection":
				shd.constant_builtin_locations[.View_Projection_Matrix] = loc
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
	s.proj_matrix = make_default_projection(pf.get_screen_width(), pf.get_screen_height())

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
//
// The view matrix is a Mat4 because its easier to upload a Mat4 to the GPU. But only the upper-left
// 3x3 matrix is actually used.
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
	frame_allocator = s.frame_allocator
	pf = s.platform
	rb = s.render_backend
	ab = s.audio_backend
	pf.set_internal_state(s.platform_state)
	rb.set_internal_state(s.render_backend_state)
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
	View_Projection_Matrix,
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

Handle :: hm.Handle64
Texture_Handle :: distinct Handle
Render_Target_Handle :: distinct Handle
Font :: distinct int

FONT_NONE :: Font {}
TEXTURE_NONE :: Texture_Handle {}
RENDER_TARGET_NONE :: Render_Target_Handle {}

AUDIO_MIX_SAMPLE_RATE :: 44100
AUDIO_MIX_CHUNK_SIZE :: 1400

Audio_Sample :: [2]f32

Sound :: distinct Handle

SOUND_NONE :: Sound {}

Sound_Data_Handle :: distinct Handle

Sound_Data :: struct {
	handle: Sound_Data_Handle,
	samples: []Audio_Sample,
	sample_rate: int,

	// When a Sound_Instance is destroyed, we check if this reaches zero. If it does, then the
	// Sound_Data and its samples slice are also destroyed/freed.
	instances: int,
}

Sound_Instance :: struct {
	handle: Sound,
	sound_data_handle: Sound_Data_Handle,
	volume: f32,
	target_volume: f32,
	pan: f32,
	target_pan: f32,
	pitch: f32,
	target_pitch: f32,
}

Playing_Sound :: struct {
	sound: Sound,

	// How many samples have played?
	offset: int,

	// Only used when playing sounds that have pitch != 1 or when the sound has a sample rate that
	// does not match the mixer's sample rate. In those cases we may get "fractional samples"
	// because we may be in samples that are inbetween two samples in the original sound.
	offset_fraction: f32,

	loop: bool,
}

Audio_Stream :: distinct Handle

Audio_Stream_Data :: struct {
	handle: Audio_Stream,
	vorbis: ^stbv.vorbis, 
}

// The format used to describe that data passed to `load_sound_from_bytes_raw`.
Raw_Sound_Format :: enum {
	Integer8,
	Integer16,
	Integer32,
	Float,
}

// This keeps track of the internal state of the library. Usually, you do not need to poke at it.
// It is created and kept as a global variable when 'init' is called. However, 'init' also returns
// the pointer to it, so you can later use 'set_internal_state' to restore it (after for example hot
// reload).
State :: struct {
	allocator: runtime.Allocator,
	frame_arena: runtime.Arena,
	frame_allocator: runtime.Allocator,
	platform: Platform_Interface,
	platform_state: rawptr,
	render_backend: Render_Backend_Interface,
	render_backend_state: rawptr,

	fs: fs.FontContext,
	
	close_window_requested: bool,

	// All events for this frame. Cleared when `process_events` run
	events: [dynamic]Event,

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

	vertex_buffer_cpu: []u8,
	vertex_buffer_cpu_used: int,
	default_shader: Shader,

	// Time when the first call to `new_frame` happened
	start_time: time.Time,
	prev_frame_time: time.Time,

	// "dt"
	frame_time: f32,

	time: f64,

	// -----
	// Audio
	audio_backend: Audio_Backend_Interface,
	audio_backend_state: rawptr,

	sound_data: hm.Dynamic_Handle_Map(Sound_Data, Sound_Data_Handle),
	sound_instances: hm.Dynamic_Handle_Map(Sound_Instance, Sound),

	// Sounds that have been started as because `play_sound` was called.
	playing_sounds: [dynamic]Playing_Sound,

	audio_streams: hm.Dynamic_Handle_Map(Audio_Stream_Data, Audio_Stream),
	vorbis_alloc: stbv.vorbis_alloc,

	// 1 megabyte is arbitrarily chosen.
	mix_buffer: [1*mem.Megabyte]Audio_Sample,

	// Where the mixer currently is in the mix buffer.
	mix_buffer_offset: int,
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
	None,
	
	Left_Stick_X,
	Left_Stick_Y,
	Right_Stick_X,
	Right_Stick_Y,
	Left_Trigger,
	Right_Trigger,
}

Gamepad_Button :: enum {
	None,
	
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

Event :: union {
	Event_Close_Window_Requested,
	Event_Key_Went_Down,
	Event_Key_Went_Up,
	Event_Mouse_Move,
	Event_Mouse_Wheel,
	Event_Mouse_Button_Went_Down,
	Event_Mouse_Button_Went_Up,
	Event_Gamepad_Button_Went_Down,
	Event_Gamepad_Button_Went_Up,
	Event_Screen_Resize,
	Event_Window_Focused,
	Event_Window_Unfocused,
	Event_Window_Scale_Changed,
}

Event_Key_Went_Down :: struct {
	key: Keyboard_Key,
}

Event_Key_Went_Up :: struct {
	key: Keyboard_Key,
}

Event_Mouse_Button_Went_Down :: struct {
	button: Mouse_Button,
}

Event_Mouse_Button_Went_Up :: struct {
	button: Mouse_Button,
}

Event_Gamepad_Button_Went_Down :: struct {
	gamepad: Gamepad_Index,
	button: Gamepad_Button,
}

Event_Gamepad_Button_Went_Up :: struct {
	gamepad: Gamepad_Index,
	button: Gamepad_Button,
}

Event_Close_Window_Requested :: struct {}

Event_Mouse_Move :: struct {
	position: Vec2,
}

Event_Mouse_Wheel :: struct {
	delta: f32,
}

// Reports the new size of the drawable game area
Event_Screen_Resize :: struct {
	width, height: int,
}

// You can also use `k2.get_window_scale()`
Event_Window_Scale_Changed :: struct {
	scale: f32,
}

Event_Window_Focused :: struct {}

Event_Window_Unfocused :: struct {}


// Used by API builder. Everything after this constant will not be in karl2d.doc.odin
API_END :: true

batch_vertex :: proc(v: Vec2, uv: Vec2, color: Color) {
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
		(^Vec2)(&s.vertex_buffer_cpu[base_offset + pos_offset])^ = v
	}

	if uv_offset != -1 {
		(^Vec2)(&s.vertex_buffer_cpu[base_offset + uv_offset])^ = uv
	}

	if color_offset != -1 {
		(^Color)(&s.vertex_buffer_cpu[base_offset + color_offset])^ = color
	}

	override_offset: int
	for &input in shd.inputs {
		o := &shd.input_overrides[input.register]
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

@(private="file")
pf: Platform_Interface

@(private="file")
rb: Render_Backend_Interface

@(private="file")
ab: Audio_Backend_Interface

// This is here so it can be used from other files in this directory (`s.frame_allocator` can't be
// reached outside this file).
frame_allocator: runtime.Allocator

get_shader_input_default_type :: proc(name: string, type: Shader_Input_Type) -> Shader_Default_Inputs {
	if name == "position" && type == .Vec2 {
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
		case .Position: return .RG_32_Float
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

FILESYSTEM_SUPPORTED :: ODIN_OS != .JS && ODIN_OS != .Freestanding


