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
import stbv "vendor:stb/vorbis"

import "core:image"
import "core:image/jpeg"
import "core:image/bmp"
import "core:image/png"
import "core:image/tga"

import hm "core:container/handle_map"

//-----------------------------------------------//
// SETUP, WINDOW MANAGEMENT AND FRAME MANAGEMENT //
//-----------------------------------------------//

// Opens a window and initializes some internal state. The internal state will use `allocator` for
// all dynamically allocated memory.
//
// `screen_width` and `screen_height` refer to the resolution of the drawable area of the window.
// The window might be slightly larger due to borders and headers.
//
// The return value is a pointer to Karl2D's internal state. You can restore this state later using
// `set_internal_state()`. This is useful for example when doing game code reload, as the state may
// get reset when the library is reloaded. You can safely ignore the return value if you have no
// such needs.
init :: proc(
	screen_width: int,
	screen_height: int,
	window_title: string,
	options := Init_Options {},
	allocator := context.allocator,
	loc := #caller_location
) -> ^State {
	assert(s == nil, "Don't call 'init' twice.")
	s = new(State, allocator, loc)
	s.allocator = allocator

	// This is the same type of arena as the default temp allocator. This arena is for allocations
	// that have a lifetime of "one frame". They are valid until you call `present()`, at which
	// point the frame allocator is cleared.
	s.frame_allocator = runtime.arena_allocator(&s.frame_arena)
	frame_allocator = s.frame_allocator

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
		allocator = s.allocator,
	)

	log.assertf(
		platform_state_alloc_error == nil,
		"Failed allocating memory for platform state: %v",
		platform_state_alloc_error,
	)

	pf.init(s.platform_state, screen_width, screen_height, window_title, options, s.allocator)

	// This is an OS-independent handle that we can pass to any rendering backend.
	window_render_glue := pf.get_window_render_glue()

	// See `render_backend_chooser.odin` for how this is picked.
	s.render_backend = RENDER_BACKEND

	rb = s.render_backend
	rb_alloc_error: runtime.Allocator_Error
	s.render_backend_state, rb_alloc_error = mem.alloc(rb.state_size(), allocator = s.allocator)
	log.assertf(rb_alloc_error == nil, "Failed allocating memory for rendering backend: %v", rb_alloc_error)
	s.proj_matrix = make_default_projection(pf.get_screen_width(), pf.get_screen_height())
	s.view_matrix = 1

	// Boot up the render backend. It will render into our previously created window.
	rb.init(s.render_backend_state, window_render_glue, pf.get_screen_width(), pf.get_screen_height(), s.allocator)

	// The vertex buffer is created in a render backend-independent way. It is passed to the
	// render backend each frame as part of `draw_current_batch()`.
	s.vertex_buffer_cpu = make([]u8, VERTEX_BUFFER_MAX, s.allocator, loc)

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

	// Dummy element so font with index 0 means 'no font'.
	append_nothing(&s.fonts)

	default_font := load_font_from_bytes(DEFAULT_FONT_DATA)
	log.assertf(default_font == FONT_DEFAULT, "Default font must be at index %i", FONT_DEFAULT)
	_set_font(FONT_DEFAULT)

	// Audio
	{
		s.audio_backend = AUDIO_BACKEND
		ab = s.audio_backend

		audio_alloc_error: runtime.Allocator_Error
		s.audio_backend_state, audio_alloc_error = mem.alloc(ab.state_size(), allocator = s.allocator)
		log.assertf(audio_alloc_error == nil, "Failed allocating memory for audio backend: %v", audio_alloc_error)
		ab.init(s.audio_backend_state, s.allocator)
		hm.dynamic_init(&s.playing_audio_buffers, s.allocator)
		hm.dynamic_init(&s.audio_buffers, s.allocator)
		hm.dynamic_init(&s.sounds, s.allocator)

		VORBIS_STATE_SIZE :: 500 * mem.Kilobyte

		s.vorbis_alloc = {
			alloc_buffer = make([^]u8, VORBIS_STATE_SIZE, s.allocator),
			alloc_buffer_length_in_bytes = VORBIS_STATE_SIZE,
		}

		hm.dynamic_init(&s.audio_streams, s.allocator)
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
		hm.dynamic_destroy(&s.audio_streams)
		free(s.vorbis_alloc.alloc_buffer, s.allocator)
		ab.shutdown()
		hm.dynamic_destroy(&s.playing_audio_buffers)
		hm.dynamic_destroy(&s.sounds)
		hm.dynamic_destroy(&s.audio_buffers)
		free(s.audio_backend_state, s.allocator)
	}

	delete(s.events)
	destroy_font(FONT_DEFAULT)
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

// Returns which modifiers are held. The possible values are `Control`, `Alt`, `Shift` and `Super`.
// You can check that an exact set of modifiers are held like so:
//
// `if k2.get_held_modifiers() == { .Control, Shift} {}`
//
// This will only be true if left/right control are held and left/right shift are held, but it also
// makes sure that no alt or super (windows) key are held.
//
// This is useful for checking for held modifiers for hotkeys in user interfaces. If you want to
// associate an in-game action with a specific key such as Left Control, then it's better to just do
// `if k2.key_is_held(.Left_Control) {}`
get_held_modifiers :: proc() -> bit_set[Modifier] {
	res: bit_set[Modifier]

	if s.key_is_held[.Left_Control] || s.key_is_held[.Right_Control] {
		res += { .Control }
	}

	if s.key_is_held[.Left_Alt] || s.key_is_held[.Right_Alt] {
		res += { .Alt }
	}

	if s.key_is_held[.Left_Shift] || s.key_is_held[.Right_Shift] {
		res += { .Shift }
	}

	if s.key_is_held[.Left_Super] || s.key_is_held[.Right_Super] {
		res +=  { .Super }
	}

	return res
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
//
// Optional parameters:
// - origin: The point to rotate around, also offsets the position of the rect. If the origin is
//   `(0, 0)`, then the rectangle rotates around the top-left corner of the rectangle. If it is
//   `(rect.w/2, rect.h/2)` then the rectangle rotates around its center.
// - rotation: The rotation to apply, in radians
draw_rect :: proc(rect: Rect, color: Color, origin: Vec2 = {}, rotation: f32 = 0) {
	if s.vertex_buffer_cpu_used + s.batch_shader.vertex_size * 6 > len(s.vertex_buffer_cpu) {
		draw_current_batch()
	}

	if s.batch_texture != s.shape_drawing_texture {
		draw_current_batch()
	}

	s.batch_texture = s.shape_drawing_texture
	tl, tr, bl, br: Vec2

	// Rotation adapted from Raylib's "DrawTexturePro"
	if rotation == 0 {
		x := rect.x - origin.x
		y := rect.y - origin.y
		tl = { x,          y }
		tr = { x + rect.w, y }
		bl = { x,          y + rect.h }
		br = { x + rect.w, y + rect.h }
	} else {
		sin_rot := math.sin(rotation)
		cos_rot := math.cos(rotation)
		x := rect.x
		y := rect.y
		dx := -origin.x
		dy := -origin.y

		tl = {
			x + dx * cos_rot - dy * sin_rot,
			y + dx * sin_rot + dy * cos_rot,
		}

		tr = {
			x + (dx + rect.w) * cos_rot - dy * sin_rot,
			y + (dx + rect.w) * sin_rot + dy * cos_rot,
		}

		bl = {
			x + dx * cos_rot - (dy + rect.h) * sin_rot,
			y + dx * sin_rot + (dy + rect.h) * cos_rot,
		}

		br = {
			x + (dx + rect.w) * cos_rot - (dy + rect.h) * sin_rot,
			y + (dx + rect.w) * sin_rot + (dy + rect.h) * cos_rot,
		}
	}

	batch_vertex(tl, {0, 0}, color)
	batch_vertex(tr, {1, 0}, color)
	batch_vertex(br, {1, 1}, color)
	batch_vertex(tl, {0, 0}, color)
	batch_vertex(br, {1, 1}, color)
	batch_vertex(bl, {0, 1}, color)
}

// Creates a rectangle from a position and a size and draws it using the specified color.
//
// Optional parameters:
// - origin: The point to rotate around, also offsets the position of the rect. If the origin is
//   `(0, 0)`, then the rectangle rotates around the top-left corner of the rectangle. If it is
//   `(rect.w/2, rect.h/2)` then the rectangle rotates around its center.
// - rotation: The rotation to apply, in radians
draw_rect_vec :: proc(
	position: Vec2,
	size: Vec2,
	color: Color,
	origin: Vec2 = {},
	rotation: f32 = 0
) {
	draw_rect(rect_from_pos_size(position, size), color, origin, rotation)
}

@(deprecated="Use draw_rect instead")
draw_rect_ex :: proc(r: Rect, origin: Vec2, rot: f32, c: Color) {
	draw_rect(r, c, origin, rot)
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

	draw_rect(r, color, origin, rot)
}

// Draws a triangle using three vertices. The order of the vertices does not matter: Clockwise and
// counter-clockwise triangles will give the same result.
draw_triangle :: proc(vertices: [3]Vec2, c: Color) {
	if s.vertex_buffer_cpu_used + s.batch_shader.vertex_size * 3 > len(s.vertex_buffer_cpu) {
		draw_current_batch()
	}

	if s.batch_texture != s.shape_drawing_texture {
		draw_current_batch()
	}

	s.batch_texture = s.shape_drawing_texture

	batch_vertex(vertices[0], {0, 0}, c)
	batch_vertex(vertices[1], {1, 1}, c)
	batch_vertex(vertices[2], {0, 1}, c)
}

// Draw a texture a specific position.
//
// Optional parameters:
// - crop: A rectangle that describes which part of `texture` to display. Note that it is a Maybe
//   type, which means that `nil` means "no cropping".
// - origin: The point which `rotation` rotates around. Effectively an offset of `position`.
// - rotation: Rotation around `origin`, measured in radians.
// - tint: A color to apply to the texture, in a multiplicative way. WHITE means no tinting.
//
// If you want to rotate around the middle of the texture, then try this:
// 
//// middle := k2.rect_middle(k2.get_texture_rect(tex))
//// draw_texture(tex, pos + middle, origin = middle, rot)
draw_texture :: proc(
	texture: Texture,
	position: Vec2,
	crop: Maybe(Rect) = nil,
	origin: Vec2 = {},
	rotation: f32 = 0,
	tint := WHITE
) {
	if texture.handle == TEXTURE_NONE || texture.width == 0 || texture.height == 0 {
		return
	}

	fit_into: Rect

	if crop_val, has_crop := crop.?; has_crop {
		fit_into = {
			position.x, position.y,
			crop_val.w, crop_val.h,
		}
	} else {
		fit_into = {
			position.x, position.y,
			f32(texture.width), f32(texture.height),
		}
	}

	draw_texture_fit(
		texture,
		fit_into,
		crop,
		origin,
		rotation,
		tint,
	)
}

// Draw a texture by fitting it into a rectangle.
//
// Optional parameters:
// - crop: A rectangle that describes which part of `texture` to display. Note that it is a Maybe
//   type, which means that `nil` means "no cropping".
// - origin: An offset of the `into` rectangle and also the point which `rotation` rotates around.
// - rotation: Rotation around `origin`, measured in radians.
// - tint: A color to apply to the texture, in a multiplicative way. WHITE means no tinting.
draw_texture_fit :: proc(
	texture: Texture,
	into: Rect,
	crop: Maybe(Rect) = nil,
	origin: Vec2 = {},
	rotation: f32 = 0,
	tint := WHITE,
) {
	if texture.handle == TEXTURE_NONE || texture.width == 0 || texture.height == 0 {
		return
	}

	if s.vertex_buffer_cpu_used + s.batch_shader.vertex_size * 6 > len(s.vertex_buffer_cpu) {
		draw_current_batch()
	}

	if s.batch_texture != texture.handle {
		draw_current_batch()
	}
	
	s.batch_texture = texture.handle

	flip_x, flip_y: bool

	src := crop.? or_else get_texture_rect(texture)
	dst := into

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
	
	ts := Vec2{f32(texture.width), f32(texture.height)}

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
	if rb.texture_needs_vertical_flip(texture.handle) {
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
// Tells you how much space some text of a certain size will use on the screen, using a custom font.
// The return value contains the width and height of the text.
measure_text :: proc(text: string, font_size: f32, font: Font = FONT_DEFAULT) -> Vec2 {
	if font < 0 || int(font) >= len(s.fonts) {
		return {}
	}

	font_object := s.fonts[font]

	// Temporary until I rewrite the font caching system.
	_set_font(font)

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

	return TextBounds(&s.fs, font_object.fontstash_handle, font_size, text)
}

// Draw text at a position with a size.
//
// Optional parameters:
// - color: The color of the text.
// - font: The font to use, uses a default font if none is specified.
draw_text :: proc(
	text: string,
	pos: Vec2,
	font_size: f32,
	font := FONT_DEFAULT,
	color := BLACK,
) {
	if int(font) >= len(s.fonts) {
		return
	}

	_set_font(font)
	font_object := &s.fonts[font]
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

		draw_texture_fit(font_object.atlas, dst, src, {}, 0, color)
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
	data, data_ok := read_entire_file(filename, frame_allocator)

	if !data_ok {
		log.errorf("Failed loading texture %s", filename)
		return {}
	}

	load_options := image.Options {
		.alpha_add_if_missing,
	}

	if .Premultiply_Alpha in options {
		load_options += { .alpha_premultiply }
	}

	img, img_err := image.load_from_bytes(data, options = load_options, allocator = s.frame_allocator)

	if img_err != nil {
		log.errorf("Error loading texture '%v': %v", filename, img_err)
		return {}
	}

	return load_texture_from_bytes_raw(img.pixels.buf[:], img.width, img.height, .RGBA_8_Norm)
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

// Play a sound previous created using `load_sound_from_xxx` or `create_sound_from_audio_buffer`.
// The sound will be mixed when `update_audio_mixer` runs, which happens as part of `update`.
play_sound :: proc(sound: Sound) {
	sound_object := hm.get(&s.sounds, sound)

	if sound_object == nil {
		log.error("Cannot play sound, sound does not exist.")
		return
	}

	if existing := hm.get(&s.playing_audio_buffers, sound_object.playing_buffer_handle); existing != nil {
		hm.remove(&s.playing_audio_buffers, sound_object.playing_buffer_handle)
	}

	playing_audio_buffer := Playing_Audio_Buffer {
		audio_buffer = sound_object.audio_buffer,
		target_settings = sound_object.playback_settings,
		current_settings = sound_object.playback_settings,
		loop = sound_object.loop,
	}

	add_err: runtime.Allocator_Error
	sound_object.playing_buffer_handle, add_err = hm.add(&s.playing_audio_buffers, playing_audio_buffer)

	if add_err != nil {
		log.errorf("Failed to play sound. Error: %v", add_err)
	}
}

// Stop a sound. Rewinds it to the start.
stop_sound :: proc(sound: Sound) {
	sound_object := hm.get(&s.sounds, sound)

	if sound_object == nil {
		log.error("Cannot stop sound, sound does not exist.")
		return
	}

	if existing := hm.get(&s.playing_audio_buffers, sound_object.playing_buffer_handle); existing != nil {
		hm.remove(&s.playing_audio_buffers, sound_object.playing_buffer_handle)
	}

	sound_object.playing_buffer_handle = PLAYING_AUDIO_BUFFER_NONE
}

// Returns true if the sound is currently playing.
sound_is_playing :: proc(sound: Sound) -> bool {
	sound_object := hm.get(&s.sounds, sound)

	if sound_object == nil {
		return false
	}

	return hm.is_valid(&s.playing_audio_buffers, sound_object.playing_buffer_handle)
}

// Set the volume of a sound. Range: 0 to 1, where 0 is silence and 1 is the original volume of the
// sound. The volume change will only affect this instance of the sound. Use `create_sound_instance`
// to create more instances without duplicating data.
set_sound_volume :: proc(sound: Sound, volume: f32) {
	sound_object := hm.get(&s.sounds, sound)
	
	if sound_object == nil {
		log.error("Cannot set volume, sound does not exist.")
		return
	}

	clamped_volume := clamp(volume, 0, 1)

	if playing := hm.get(&s.playing_audio_buffers, sound_object.playing_buffer_handle); playing != nil {
		playing.target_settings.volume = clamped_volume
	}
	
	sound_object.playback_settings.volume = clamped_volume
}

// Set the pan of a sound. Range: -1 to 1, where -1 is full left, 0 is center and 1 is full right.
// The pan change will only affect this instance of the sound. Use `create_sound_instance` to create
// more instances without duplicating data.
set_sound_pan :: proc(sound: Sound, pan: f32) {
	sound_object := hm.get(&s.sounds, sound)
	
	if sound_object == nil {
		log.error("Cannot set pan, sound does not exist.")
		return
	}

	clamped_pan := clamp(pan, -1, 1)

	if playing := hm.get(&s.playing_audio_buffers, sound_object.playing_buffer_handle); playing != nil {
		playing.target_settings.pan = clamped_pan
	}

	sound_object.playback_settings.pan = clamped_pan
}

// Set the pitch of a sound. Range: 0.01 to infinity, where 0.01 is the lowest pitch and higher
// values increase the pitch. The pitch change will only affect this instance of the sound. Use
// `create_sound_instance` to create more instances without duplicating data.
set_sound_pitch :: proc(sound: Sound, pitch: f32) {
	sound_object := hm.get(&s.sounds, sound)
	
	if sound_object == nil {
		log.error("Cannot set pitch, sound does not exist.")
		return
	}

	capped_pitch := max(pitch, 0.01)

	if playing := hm.get(&s.playing_audio_buffers, sound_object.playing_buffer_handle); playing != nil {
		playing.target_settings.pitch = capped_pitch
	}
	
	sound_object.playback_settings.pitch = capped_pitch
}

// Makes a sound loop when it reaches the end. You can set this before playing but also while
// playing the sound.
set_sound_loop :: proc(sound: Sound, loop: bool) {
	sound_object := hm.get(&s.sounds, sound)
	
	if sound_object == nil {
		log.errorf("Cannot set loop = %v, sound does not exist.", loop)
		return
	}

	if playing := hm.get(&s.playing_audio_buffers, sound_object.playing_buffer_handle); playing != nil {
		playing.loop = loop
	}
	
	sound_object.loop = loop
}

// Load a WAV file from disk. Returns a `Sound` which can be used with `play_sound`. If you need to
// play a sound multiple times simultaneously, then use `load_audio_buffer_from_file` followed by
// one or more calls to `create_sound_from_audio_buffer`.
//
// Sounds created using this procedure owns their internal audio buffer: Calling `destroy_sound`
// will also destroy the audio buffer. 
//
// Currently only supports 16 bit WAV files.
load_sound_from_file :: proc(filename: string) -> Sound {
	data, data_ok := read_entire_file(filename, frame_allocator)

	if !data_ok {
		log.errorf("Failed to load sound from file '%v'", filename)
		return SOUND_NONE
	}

	return load_sound_from_bytes(data)
}

// Load a sound some pre-loaded memory (for example using `#load("sound.wav")`). Returns a `Sound`
// which can be used with `play_sound`. If you need to play a sound multiple times simultaneously,
// then use `load_audio_buffer_from_bytes` followed by one or more calls to
// `create_sound_from_audio_buffer`.
//
// Sounds created using this procedure owns their internal audio buffer: Calling `destroy_sound`
// will also destroy the audio buffer.
//
// Currently only supports 16 bit WAV data. Note that the data should be the entire WAV file,
// including the header. If your data does not include the header, then please use
// `load_audio_buffer_from_bytes_raw` combined with `create_sound_from_audio_buffer`.
load_sound_from_bytes :: proc(bytes: []byte) -> Sound {
	audio_buffer := load_audio_buffer_from_bytes(bytes)

	if audio_buffer == AUDIO_BUFFER_NONE {
		return SOUND_NONE
	}

	sound_object := Sound_Object {
		playback_settings = DEFAULT_AUDIO_BUFFER_PLAYBACK_SETTINGS,
		audio_buffer = audio_buffer,
		owns_audio_buffer = true,
	}

	sound, sound_add_error := hm.add(&s.sounds, sound_object)

	if sound_add_error != nil {
		log.errorf("Failed adding sound. Error: %v", sound_add_error)
		return SOUND_NONE
	}

	return sound
}

// Load a sound from some raw audio data. You need to specify the data, format and sample rate of
// the audio data yourself. This assumes that there is no header in the data. If your data has a
// header (you read the data from a file on disk), then please use `load_sound_from_bytes` instead.
//
// The returned Sound owns its internal Audio_Buffer: Calling `destroy_sound` with it will destroy
// the audio buffer.
load_sound_from_bytes_raw :: proc(
	bytes: []u8,
	format: Raw_Sound_Format,
	sample_rate: int,
	channels: Audio_Channels,
) -> Sound {
	audio_buffer := load_audio_buffer_from_bytes_raw(bytes, format, sample_rate, channels)

	if audio_buffer == AUDIO_BUFFER_NONE {
		return SOUND_NONE
	}

	sound_object := Sound_Object {
		playback_settings = DEFAULT_AUDIO_BUFFER_PLAYBACK_SETTINGS,
		audio_buffer = audio_buffer,
		owns_audio_buffer = true,
	}

	sound, sound_add_error := hm.add(&s.sounds, sound_object)

	if sound_add_error != nil {
		log.errorf("Failed adding sound. Error: %v", sound_add_error)
		return SOUND_NONE
	}

	return sound
}

// Load a WAV file from disk. Returns an `Audio_Buffer` which can be used with
// `create_sound_from_audio_buffer` in order to play the audio buffer multiple times simultaneously.
//
// Currently only supports 16 bit WAV data.
load_audio_buffer_from_file :: proc(filename: string) -> Audio_Buffer {
	data, data_ok := read_entire_file(filename, frame_allocator)

	if !data_ok {
		log.errorf("Failed to load audio buffer from file '%v'", filename)
		return AUDIO_BUFFER_NONE
	}

	return load_audio_buffer_from_bytes(data)
}

// Load a WAV file from some pre-loaded memory (can be loaded using `#load("sound.wav")`). Returns
// an `Audio_Buffer` which can be used with `create_sound_from_audio_buffer` in order to play the
// audio buffer multiple times simultaneously.
//
// Currently only supports 16 bit WAV data. Note that the data should be the entire WAV file,
// including the header. If your data does not include the header, then please use
// `load_audio_buffer_from_bytes_raw`.
load_audio_buffer_from_bytes :: proc(bytes: []u8) -> Audio_Buffer {
	d := bytes

	if len(d) < 8 {
		log.error("Invalid WAV")
		return AUDIO_BUFFER_NONE
	}

	if string(d[:4]) != "RIFF" {
		log.error("Invalid wav file: No RIFF identifier")
		return AUDIO_BUFFER_NONE
	}

	d = d[4:]

	file_size, file_size_ok := endian.get_u32(d, .Little)

	if !file_size_ok {
		log.error("Invalid wav file: No size")
		return AUDIO_BUFFER_NONE
	}

	if int(file_size) != len(bytes) - 8 {
		log.error("File size mismiatch")
		return AUDIO_BUFFER_NONE
	}

	d = d[4:]

	if string(d[:4]) != "WAVE" {
		log.error("Invalid wav file: Not WAVE format")
		return AUDIO_BUFFER_NONE
	}

	d = d[4:]

	sample_rate: u32
	samples: []u8
	channels: Audio_Channels

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

			num_channels, num_channels_ok := endian.get_u16(d[2:4], .Little)

			if num_channels_ok {
				if num_channels == 1 {
					channels = .Mono
				} else if num_channels == 2 {
					channels = .Stereo
				} else {
					log.errorf("Unsupported number of channels in wav fmt block: %v", num_channels)
					continue
				}
			} else {
				log.error("Failed reading number of channels from wav fmt block")
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
	
	return load_audio_buffer_from_bytes_raw(samples, format, int(sample_rate), channels)
}

// Load an audio buffer from some raw audio data. You need to specify the data, format and sample
// rate of the sound yourself. This assumes that there is no header in the data. If your data has a
// header (you read the data from a file on disk), then please use `load_audio_buffer_from_bytes`
// instead.
load_audio_buffer_from_bytes_raw :: proc(
	bytes: []u8,
	format: Raw_Sound_Format,
	sample_rate: int,
	channels: Audio_Channels,
) -> Audio_Buffer {
	samples: []Audio_Sample

	switch format{
	case .Integer8:
		samples_u8 := bytes
		samples = make([]Audio_Sample, len(samples_u8), s.allocator)

		for idx in 0..<len(samples) {
			samples[idx] = (f32(samples_u8[idx]) - 128.0) / 128.0
		}

	case .Integer16:
		samples_i16 := slice.reinterpret([]i16, bytes)
		samples = make([]Audio_Sample, len(samples_i16), s.allocator)

		for idx in 0..<len(samples) {
			samples[idx] = f32(samples_i16[idx]) / f32(max(i16))
		}

	case .Integer32:
		samples_i32 := slice.reinterpret([]i32, bytes)
		samples = make([]Audio_Sample, len(samples_i32), s.allocator)

		for idx in 0..<len(samples) {
			samples[idx] = f32(samples_i32[idx]) / f32(max(i32))
		}

	case .Float:
		samples = slice.clone(slice.reinterpret([]Audio_Sample, bytes), s.allocator)
	}

	buffer_object := Audio_Buffer_Object {
		sample_rate = sample_rate,
		samples = samples,
		channels = channels,
	}

	buffer, buffer_add_error := hm.add(&s.audio_buffers, buffer_object)

	if buffer_add_error != nil {
		log.errorf("Failed to load sound. Error: %v", buffer_add_error)
		return AUDIO_BUFFER_NONE
	}

	return buffer
}

// Creates a sound that can be used to play the contents of an `Audio_Buffer`. This can be used to
// load an audio buffer once and have multiple sounds playing the contents of it, simultaneously.
// This makes all those sounds share the same audio data.
//
// Sounds created using this procedure do not own the buffer. This means that calling
// `destroy_sound` on the Sound will only remove the Sound from Karl2D's internal state, but it
// won't destroy the Audio_Buffer. Such auto-destroying of the `Audio_Buffer` only happen with
// sounds created using `load_sound_from_file` and `load_sound_from_bytes`.
create_sound_from_audio_buffer :: proc(buffer: Audio_Buffer) -> Sound {
	buffer_object := hm.get(&s.audio_buffers, buffer)

	if buffer_object == nil {
		log.error("Trying to create sound from invalid audio buffer")
		return SOUND_NONE
	}

	sound_object := Sound_Object {
		playback_settings = DEFAULT_AUDIO_BUFFER_PLAYBACK_SETTINGS,
		audio_buffer = buffer,
		owns_audio_buffer = false,
	}

	sound, sound_add_error := hm.add(&s.sounds, sound_object)

	if sound_add_error != nil {
		log.errorf("Failed to create sound from audio buffer. Error: %v", sound_add_error)
		return SOUND_NONE
	}

	return sound
}

// Destroy a sound, removing it from Karl2D's internal list of sounds.
//
// If the sound was created using `create_sound_from_audio_buffer`, then this procedure will not
// destroy the audio buffer. If the sound was created using `load_sound_from_file` or
// `load_sound_from_bytes`, then this procedure WILL destroy the audio buffer.
destroy_sound :: proc(sound: Sound) {
	sound_object := hm.get(&s.sounds, sound)

	if sound_object == nil {
		log.error("Trying to destroy invalid sound. It may already be destroyed, or the handle may be invalid.")
		return
	}

	if playing := hm.get(&s.playing_audio_buffers, sound_object.playing_buffer_handle); playing != nil {
		hm.remove(&s.playing_audio_buffers, sound_object.playing_buffer_handle)
	}
	
	if sound_object.owns_audio_buffer {
		destroy_audio_buffer(sound_object.audio_buffer)
	}

	hm.remove(&s.sounds, sound)
}

// Destroy an audio buffer previously loaded using `load_audio_buffer_from_xxx`. Before destroying
// this audio buffer, make sure it is not in use by any playing sounds. Destroy the sounds that
// reference it using `destroy_sound` first.
destroy_audio_buffer :: proc(audio_buffer: Audio_Buffer)  {
	audio_buffer_object := hm.get(&s.audio_buffers, audio_buffer)

	if audio_buffer_object == nil {
		log.debug("Tried to destroy non-existing audio buffer")
		return
	}

	delete(audio_buffer_object.samples, s.allocator)
	hm.remove(&s.audio_buffers, audio_buffer)
}

// Load an audio stream from a file on disk. This is often used for playing music. An audio stream
// only loads a small part of the file at a time. As the file is played, new parts are streamed into
// memory.
//
// Supported file formats: ogg
//
// Audio streams do not stream in data automatically from the disk. You need to call
// `update_audio_stream` every frame to stream in the new data.
load_audio_stream_from_file :: proc(filename: string) -> Audio_Stream {
	f, f_err := file_open(filename)

	if f_err != nil {
		log.errorf("Failed opening file %v. Error: %v", filename, f_err)
		return AUDIO_STREAM_NONE
	}

	buf := make([dynamic]u8, frame_allocator)
	read_buf: [256]u8
	nbytes_read, read_err := file_read(f, read_buf[:])

	if read_err != nil {
		log.errorf("Failed reading from audio stream file %v. Error: %v", filename, read_err)

		if close_err := file_close(f); close_err != nil {
			log.errorf("Failed closing file. Error: %v", close_err)
		}
		
		return AUDIO_STREAM_NONE
	}

	append(&buf, ..read_buf[:nbytes_read])
	vorbis_res: ^stbv.vorbis

	// This loop tries to read in just enough from the file so that it has enough info to play it.
	// `stbv.open_pushdata` returns an error if it needs more data, in which case the the loop
	// might continue.
	for {
		vorbis_err: stbv.Error
		consumed: i32
		vorbis := stbv.open_pushdata(
			raw_data(buf),
			i32(len(buf)),
			&consumed,
			&vorbis_err,
			&s.vorbis_alloc,
		)

		if vorbis_err == nil {
			// The file was properly loaded!
			vorbis_res = vorbis
			_, seek_err := file_seek(f, i64(consumed), .Start)

			if seek_err != nil {
				log.errorf("Failed seeking in audio stream file %v. Error: %v", filename, seek_err)
				file_close(f)
				return AUDIO_STREAM_NONE
			}

			break
		} else if vorbis_err == .need_more_data {
			// Read in more data from the file so that maybe `stbv.open_pushdata` succeeds next
			// iteration.
			nbytes_read, read_err = file_read(f, read_buf[:])

			if read_err != nil {
				log.errorf("Failed reading from audio stream file %v. Error: %v", filename, read_err)
				file_close(f)
				return AUDIO_STREAM_NONE
			}

			if nbytes_read == 0 {
				log.errorf("Failed to load audio stream. Reached end of file before stream could be loaded.")
				file_close(f)
				return AUDIO_STREAM_NONE
			}

			append(&buf, ..read_buf[:nbytes_read])
		} else {
			log.errorf("Failed to load audio stream. Error: %v", vorbis_err)
			file_close(f)
			return AUDIO_STREAM_NONE
		}
	}

	info := stbv.get_info(vorbis_res)
	channels: Audio_Channels

	if info.channels == 1 {
		channels = Audio_Channels.Mono
	} else if info.channels == 2 {
		channels = Audio_Channels.Stereo
	} else{
		log.errorf("Unsupported number of channels: %v", info.channels)

		if close_err := file_close(f); close_err != nil {
			log.errorf("Failed closing file. Error: %v", close_err)
		}
		
		return AUDIO_STREAM_NONE
	}

	buffer := Audio_Buffer_Object {
		sample_rate = int(info.sample_rate),
		samples = make([]Audio_Sample, AUDIO_STREAM_BUFFER_SIZE, s.allocator),
		channels = channels,
	}

	buffer_handle, buffer_handle_add_err := hm.add(&s.audio_buffers, buffer)

	if buffer_handle_add_err != nil {
		log.errorf("Failed to load audio stream. Error: %v", buffer_handle_add_err)
		
		if close_err := file_close(f); close_err != nil {
			log.errorf("Failed closing file. Error: %v", close_err)
		}

		delete(buffer.samples, s.allocator)
		return AUDIO_STREAM_NONE
	}

	asd := Audio_Stream_Data {
		mode = .From_File,
		file = f,
		vorbis = vorbis_res,
		buffer = buffer_handle,
		playback_settings = {
			pan = 0,
			volume = 1,
			pitch = 1,
		},
		file_read_buf = make([dynamic]u8, s.allocator),
	}

	stream, stream_add_err := hm.add(&s.audio_streams, asd)

	if stream_add_err != nil {
		log.errorf("Failed to create audio stream from file. Error: %v", stream_add_err)
		file_close(asd.file)
		delete(asd.file_read_buf)
		delete(buffer.samples, s.allocator)
		hm.remove(&s.audio_buffers, buffer_handle)
		return AUDIO_STREAM_NONE
	}

	return stream
}

// Load an audio stream from a byte slice that is completely in memory. This makes it possible to
// have an encoded audio file in memory and decode it, a small bit a time.
//
// The `bytes` parameter is NOT copied. Do not deallocate that memory while the stream is playing.
//
// Supported formats: ogg
//
// Audio streams do not stream in data automatically from the source. You need to call
// `update_audio_stream` every frame to stream in the new data.
//
// This procedure is useful in some specific cases. One such case is web builds. Web builds don't
// support `load_audio_stream_from_file` since they don't have a file system. Instead, you can do
// `k2.load_audio_stream_from_bytes(#load("some_music.ogg"))` to embed the whole ogg file in the
// `.wasm` file.
//
// Another use case is if you're making a desktop game and you want to embed all the assets in the
// executable (so the game is a single file). In that case you'd could also use `#load` to fetch the
// file and then send it into this procedure.
//
// Note that this procedure wants the encoded file, for example an ogg file just like it was on
// disk. For normal sounds there is a `load_sound_from_bytes_raw` procedure where you just send in
// the samples. There is no such procedure for audio streams since the whole idea is to stream an
// encoded file into memory without having to decode the whole thing first.  
load_audio_stream_from_bytes :: proc(bytes: []u8) -> Audio_Stream {
	vorbis_err: stbv.Error

	// This procedure is specifically made for our use case: Streaming from a file that is already
	// completely in memory.
	vorbis_res := stbv.open_memory(
		raw_data(bytes),
		i32(len(bytes)),
		&vorbis_err,
		&s.vorbis_alloc,
	)

	if vorbis_err != nil {
		log.errorf("Failed opening audio stream from bytes. Error: %v", vorbis_err)
		return AUDIO_STREAM_NONE
	}

	info := stbv.get_info(vorbis_res)
	channels: Audio_Channels

	if info.channels == 1 {
		channels = Audio_Channels.Mono
	} else if info.channels == 2 {
		channels = Audio_Channels.Stereo
	} else{
		log.errorf("Unsupported number of channels: %v", info.channels)
		return AUDIO_STREAM_NONE
	}

	buffer := Audio_Buffer_Object {
		sample_rate = int(info.sample_rate),
		samples = make([]Audio_Sample, AUDIO_STREAM_BUFFER_SIZE, s.allocator),
		channels = channels,
	}

	buffer_handle, buffer_handle_add_err := hm.add(&s.audio_buffers, buffer)

	if buffer_handle_add_err != nil {
		log.errorf("Failed to load audio stream. Error: %v", buffer_handle_add_err)
		delete(buffer.samples, s.allocator)
		return AUDIO_STREAM_NONE
	}

	asd := Audio_Stream_Data {
		mode = .From_Bytes,
		bytes = bytes,
		vorbis = vorbis_res,
		buffer = buffer_handle,
		playback_settings = {
			pan = 0,
			volume = 1,
			pitch = 1,
		},
	}

	stream, stream_add_err := hm.add(&s.audio_streams, asd)

	if stream_add_err != nil {
		log.errorf("Failed to create audio stream from bytes. Error: %v", stream_add_err)
		delete(buffer.samples, s.allocator)
		hm.remove(&s.audio_buffers, buffer_handle)
		return AUDIO_STREAM_NONE
	}

	return stream
}

// Destroy an audio stream previously loaded using `load_audio_stream_from_file` or
// `load_audio_stream_from_bytes`. This cleans up some internal state and closes file handles.
//
// If you created the stream using `load_audio_stream_from_bytes`, then this procedure will NOT
// deallocate the bytes that you sent into that procedure.
destroy_audio_stream :: proc(stream: Audio_Stream) {
	sd := hm.get(&s.audio_streams, stream)

	if sd == nil {
		log.error("Trying to destroy invalid audio stream. It may already be destroyed, or the handle may be invalid.")
		return
	}

	if playing := hm.get(&s.playing_audio_buffers, sd.playing_buffer_handle); playing != nil {
		hm.remove(&s.playing_audio_buffers, sd.playing_buffer_handle)
	}

	if ab := hm.get(&s.audio_buffers, sd.buffer); ab != nil {
		delete(ab.samples, s.allocator)
		hm.remove(&s.audio_buffers, sd.buffer)
	}

	switch sd.mode {
	case .From_File:
		file_close(sd.file)
		delete(sd.file_read_buf)
	case .From_Bytes:
		// don't free the bytes, they are owned by the game
	}

	hm.remove(&s.audio_streams, stream)
}

// Streams in new audio data from the audio stream. You need to call this once per frame in order
// for the streaming to actually happen. 
update_audio_stream :: proc(stream: Audio_Stream) {
	sd := hm.get(&s.audio_streams, stream)

	if sd == nil {
		log.error("Trying to update destroyed audio stream")
		return
	}

	pab := hm.get(&s.playing_audio_buffers, sd.playing_buffer_handle)

	if pab == nil {
		// Don't log an error here: Not playing the stream is a valid state. It just doesn't need
		// any updating.
		return
	}

	ab := hm.get(&s.audio_buffers, pab.audio_buffer)

	if ab == nil {
		hm.remove(&s.playing_audio_buffers, sd.playing_buffer_handle)
		log.error("Trying to update audio stream with destroyed buffer")
		return
	}

	audio_stream_remaining :: proc(as: ^Audio_Stream_Data, pab: ^Playing_Audio_Buffer, ab: ^Audio_Buffer_Object) -> int {
		remaining := as.buffer_write_pos - pab.offset 

		if remaining < 0 {
			remaining = len(ab.samples) - pab.offset + as.buffer_write_pos 
		}

		return remaining
	}

	switch sd.mode {
	case .From_File:
		for audio_stream_remaining(sd, pab, ab) < AUDIO_STREAM_BUFFER_SIZE / 2 {
			channels: i32
			samples: i32
			output: [^]^f32

			bytes_used := stbv.decode_frame_pushdata(
				sd.vorbis,
				raw_data(sd.file_read_buf[sd.file_read_buf_offset:]),
				i32(len(sd.file_read_buf) - sd.file_read_buf_offset),
				&channels,
				&output, 
				&samples,
			)

			if bytes_used == 0 && samples == 0 {
				read_buf_size := len(sd.file_read_buf)
				non_zero_resize(&sd.file_read_buf, read_buf_size + 256)
				read, read_err := file_read(sd.file, sd.file_read_buf[read_buf_size:read_buf_size+256])

				if read > 0 {
					shrink(&sd.file_read_buf, read_buf_size + read)
				}

				if read_err != nil {
					if read_err == .EOF {
						if sd.loop {
							_, seek_err := file_seek(sd.file, 0, .Start)

							if seek_err != nil {
								log.errorf("Failed seeking in audio stream file. Stopping it. Error: %v", seek_err)
								stop_audio_stream(stream)
								break
							}

							stbv.flush_pushdata(sd.vorbis)
							continue
						} else {
							stop_audio_stream(stream)
							break
						}
					} else {
						hm.remove(&s.playing_audio_buffers, sd.playing_buffer_handle)
						log.errorf("Failed reading from audio stream file. Error: %v", read_err)
						break
					}
				}
			} else if bytes_used > 0 && samples == 0 {
				sd.file_read_buf_offset += int(bytes_used)
			} else if bytes_used > 0 && samples > 0 {
				if channels == 1 {
					mono: [^]f32 = output[0]

					for samp_idx in 0..<samples {
						ab.samples[sd.buffer_write_pos] = mono[samp_idx]
						sd.buffer_write_pos = (sd.buffer_write_pos + 1) % len(ab.samples)
					}
				} else if channels == 2 {
					left: [^]f32 = output[0]
					right: [^]f32 = output[1]

					for samp_idx in 0..<samples {
						ab.samples[sd.buffer_write_pos] = left[samp_idx]
						ab.samples[sd.buffer_write_pos + 1] = right[samp_idx]
						sd.buffer_write_pos = (sd.buffer_write_pos + 2) % len(ab.samples)
					}
				} else {
					hm.remove(&s.playing_audio_buffers, sd.playing_buffer_handle)
					log.error("Invalid num channels")
					break
				}
				sd.file_read_buf_offset += int(bytes_used)
			} else {
				hm.remove(&s.playing_audio_buffers, sd.playing_buffer_handle)
				log.error("Invalid vorbis")
				break
			}
		}

		if len(sd.file_read_buf) > 0 {
			// We didn't consume all the data in the read buffer. Move the remaining data to the start
			// of the buffer so that it can be consumed in the next update.
			copy(sd.file_read_buf[:], sd.file_read_buf[sd.file_read_buf_offset:])
			shrink(&sd.file_read_buf, len(sd.file_read_buf) - sd.file_read_buf_offset)
			sd.file_read_buf_offset = 0
		}
	case .From_Bytes:
		channels: i32
		output: [^]^f32

		for audio_stream_remaining(sd, pab, ab) < AUDIO_STREAM_BUFFER_SIZE / 2 {
			samples := stbv.get_frame_float(sd.vorbis, &channels, &output)

			if samples == 0 {
				if sd.loop {
					stbv.seek_start(sd.vorbis)
					continue
				} else {
					// TODO: Stopping here is bad as the samples haven't been mixed in yet. Remove the
					// stream but push the final samples into the audio buffer and destroy that one
					// when it finishes playing (in the mixer).
					stop_audio_stream(stream)
					break
				}
			}

			if channels == 1 {
				mono: [^]f32 = output[0]

				for samp_idx in 0..<samples {
					ab.samples[sd.buffer_write_pos] = mono[samp_idx]
					sd.buffer_write_pos = (sd.buffer_write_pos + 1) % len(ab.samples)
				}
			} else if channels == 2 {
				left: [^]f32 = output[0]
				right: [^]f32 = output[1]

				for samp_idx in 0..<samples {
					ab.samples[sd.buffer_write_pos] = left[samp_idx]
					ab.samples[sd.buffer_write_pos + 1] = right[samp_idx]
					sd.buffer_write_pos = (sd.buffer_write_pos + 2) % len(ab.samples)
				}
			} else {
				hm.remove(&s.playing_audio_buffers, sd.playing_buffer_handle)
				log.error("Invalid num channels")
				break
			}
		}
	}
}

// Start playing an audio stream. Don't forget to call `update_audio_stream` every frame in order to
// stream in new data.
//
// Running this this while the stream is already playing will restart it from the beginning. Use
// `pause_audio_stream` if you just want to pause it.
play_audio_stream :: proc(stream: Audio_Stream) {
	sd := hm.get(&s.audio_streams, stream)

	if sd == nil {
		log.error("Cannot play audio stream, stream does not exist.")
		return
	}

	if existing := hm.get(&s.playing_audio_buffers, sd.playing_buffer_handle); existing != nil {
		stop_audio_stream(stream)
	}

	playing_audio_buffer := Playing_Audio_Buffer {
		audio_buffer = sd.buffer,
		target_settings = sd.playback_settings,
		current_settings = sd.playback_settings,

		// This means that we are looping the buffer itself. We will use this buffer as a circular
		// buffer, filling it with samples as we stream in more. Thus it needs to be looped to not
		// stop when the end of the circular buffer is reached.
		loop = true,
	}

	add_err: runtime.Allocator_Error
	sd.playing_buffer_handle, add_err = hm.add(&s.playing_audio_buffers, playing_audio_buffer)

	if add_err != nil {
		log.errorf("Failed playing the audio stream because the audio buffer could not be set up for playing. Error: %v", add_err)
	}
}

// Pause an audio stream. Run `play_audio_stream` to unpause it.
pause_audio_stream :: proc(stream: Audio_Stream) {
	sd := hm.get(&s.audio_streams, stream)

	if sd == nil {
		log.error("Cannot pause audio stream, stream does not exist.")
		return
	}

	if existing := hm.get(&s.playing_audio_buffers, sd.playing_buffer_handle); existing != nil {
		hm.remove(&s.playing_audio_buffers, sd.playing_buffer_handle)
	}

	sd.playing_buffer_handle = PLAYING_AUDIO_BUFFER_NONE
}

// Stop an audio stream. If `play_audio_stream` is called again, the stream will start over from the
// beginning.
stop_audio_stream :: proc(stream: Audio_Stream) {
	sd := hm.get(&s.audio_streams, stream)

	if sd == nil {
		log.error("Cannot stop audio stream, stream does not exist.")
		return
	}

	if existing := hm.get(&s.playing_audio_buffers, sd.playing_buffer_handle); existing != nil {
		hm.remove(&s.playing_audio_buffers, sd.playing_buffer_handle)
	}

	sd.playing_buffer_handle = PLAYING_AUDIO_BUFFER_NONE
	sd.buffer_write_pos = 0

	switch sd.mode {
	case .From_File:
		file_seek(sd.file, 0, .Start)
		runtime.clear(&sd.file_read_buf)
		sd.file_read_buf_offset = 0
		stbv.flush_pushdata(sd.vorbis)

	case .From_Bytes:
		stbv.seek_start(sd.vorbis)
	}
}

// Set the volume of the audio stream. Range: 0 to 1.
//
// You can use this both with a playing and non-playing stream. If its already playing, then this
// will affect the playing stream.
set_audio_stream_volume :: proc(stream: Audio_Stream, volume: f32) {
	sd := hm.get(&s.audio_streams, stream)
	
	if sd == nil {
		log.error("Cannot set audio stream volume, stream does not exist.")
		return
	}

	clamped_volume := clamp(volume, 0, 1)

	if playing := hm.get(&s.playing_audio_buffers, sd.playing_buffer_handle); playing != nil {
		playing.target_settings.volume = clamped_volume
	}
	
	sd.playback_settings.volume = clamped_volume
}

// Set the pan (balance between left and right) of the audio stream. Range: -1 to 1, where -1 is
// full left, 0 is center and 1 is full right.
//
// You can use this both with a playing and non-playing stream. If its already playing, then this
// will affect the playing stream.
set_audio_stream_pan :: proc(stream: Audio_Stream, pan: f32) {
	sd := hm.get(&s.audio_streams, stream)
	
	if sd == nil {
		log.error("Cannot set audio stream pan, stream does not exist.")
		return
	}

	clamped_pan := clamp(pan, -1, 1)

	if playing := hm.get(&s.playing_audio_buffers, sd.playing_buffer_handle); playing != nil {
		playing.target_settings.pan = clamped_pan
	}

	sd.playback_settings.pan = clamped_pan
}

// Set the pitch of the audio stream. Range: 0.01 to infinity. A higher value will make the audio
// play faster.
//
// You can use this both with a playing and non-playing stream. If its already playing, then this
// will affect the playing stream.
set_audio_stream_pitch :: proc(stream: Audio_Stream, pitch: f32) {
	sd := hm.get(&s.audio_streams, stream)
	
	if sd == nil {
		log.error("Cannot set audio stream pitch, stream does not exist.")
		return
	}

	capped_pitch := max(pitch, 0.01)

	if playing := hm.get(&s.playing_audio_buffers, sd.playing_buffer_handle); playing != nil {
		playing.target_settings.pitch = capped_pitch
	}
	
	sd.playback_settings.pitch = capped_pitch
}

// Set the audio stream to loop when it reaches the end of the stream. You can set this before
// playing the stream. You can also modify the loop state of an already playing stream.
set_audio_stream_loop :: proc(stream: Audio_Stream, loop: bool) {
	sd := hm.get(&s.audio_streams, stream)
	
	if sd == nil {
		log.errorf("Cannot set audio stream loop = %v, stream does not exist.", loop)
		return
	}

	// Note a difference from `set_sound_loop`: We don't set the looping state of the playing audio
	// buffer. That one should always loop for an audio stream. The stream is continuously writing
	// data into a small looping buffer. We just set the stream itself to not loop, so it will stop
	// feeding in data when it reaches the end.
	
	sd.loop = loop
}

// Update the audio mixer and feed more audio data into the audio backend. This is done
// automatically when `update` runs, so you normally don't need to call this manually.
//
// This procedure implements a custom software audio mixer. The audio backend is just fed the
// resulting mix. Therefore, you can see everything regarding how audio is processed in this
// procedure.
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

	audio_mix :: proc(
		dest: [][2]Audio_Sample,
		source: []Audio_Sample,
		source_channels: Audio_Channels,
		interpolate: bool,
		dest_source_ratio: f32,
		dest_to_write: int,
		source_fractional_offset: f32,
		volume_start: f32,
		volume_end: f32,
		pan_start: [2]f32,
		pan_end: [2]f32,
	) -> int {
		Audio_Mix_Kind :: enum {
			Mono,
			Stereo,
			Mono_Interpolate,
			Stereo_Interpolate,
		}

		kind: Audio_Mix_Kind

		if source_channels == .Mono && !interpolate {
			kind = .Mono
		} else if source_channels == .Stereo && !interpolate {
			kind = .Stereo
		} else if source_channels == .Mono && interpolate {
			kind = .Mono_Interpolate
		} else if source_channels == .Stereo && interpolate {
			kind = .Stereo_Interpolate
		} else {
			log.error("Invalid combination of source channels and interpolate in add procedure")
			return 0
		}

		switch kind {
		case .Mono:
			n := dest_to_write

			if n > len(source) {
				n = len(source)
			}

			for samp_idx in 0..<n {
				t := f32(samp_idx) / f32(n)
				volume := math.lerp(volume_start, volume_end, t)
				pan := linalg.lerp(pan_start, pan_end, t)

				dest[samp_idx].x += pan.x * source[samp_idx] * volume
				dest[samp_idx].y += pan.y * source[samp_idx] * volume
			}

			return n
		case .Stereo:
			source_stereo := slice.reinterpret([][2]Audio_Sample, source)
			n := dest_to_write

			if n > len(source_stereo) {
				n = len(source_stereo)
			}

			for samp_idx in 0..<n {
				t := f32(samp_idx) / f32(n)
				volume := math.lerp(volume_start, volume_end, t)
				pan := linalg.lerp(pan_start, pan_end, t)

				dest[samp_idx] += pan * source_stereo[samp_idx] * volume
			}

			return n

		case .Mono_Interpolate:
			dest_idx: int

			for ; dest_idx < dest_to_write; dest_idx += 1 {
				src_pos := source_fractional_offset + f32(dest_idx) * dest_source_ratio
				src_idx := int(src_pos)
				
				if src_idx >= len(source) {
					break
				}

				src_next := min(src_idx + 1, len(source) - 1)
				frac := src_pos - f32(src_idx)

				prev_val := source[src_idx]
				cur_val := source[src_next]

				t := f32(dest_idx) / f32(dest_to_write)
				volume := math.lerp(volume_start, volume_end, t)
				pan := linalg.lerp(pan_start, pan_end, t)

				dest[dest_idx].x += pan.x * linalg.lerp(prev_val, cur_val, frac) * volume
				dest[dest_idx].y += pan.y * linalg.lerp(prev_val, cur_val, frac) * volume
			}

			return dest_idx

		case .Stereo_Interpolate:
			source_stereo := slice.reinterpret([][2]Audio_Sample, source)
			dest_idx: int

			for ; dest_idx < dest_to_write; dest_idx += 1 {
				src_pos := source_fractional_offset + f32(dest_idx) * dest_source_ratio
				src_idx := int(src_pos)
				
				if src_idx >= len(source_stereo) {
					break
				}

				src_next := min(src_idx + 1, len(source_stereo) - 1)
				frac := src_pos - f32(src_idx)

				prev_val := source_stereo[src_idx]
				cur_val := source_stereo[src_next]

				t := f32(dest_idx) / f32(dest_to_write)
				volume := math.lerp(volume_start, volume_end, t)
				pan := linalg.lerp(pan_start, pan_end, t)

				dest[dest_idx] += pan * linalg.lerp(prev_val, cur_val, frac) * volume
			}

			return dest_idx
		}

		return 0
	}


	for ps_iter := hm.dynamic_iterator_make(&s.playing_audio_buffers); ps, ps_handle in hm.dynamic_iterate(&ps_iter) {
		data := hm.get(&s.audio_buffers, ps.audio_buffer)

		if data == nil {
			log.error("Trying to play sound with destroyed data")
			hm.remove(&s.playing_audio_buffers, ps_handle)
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

		settings := &ps.current_settings
		target_settings := &ps.target_settings

		// We get the delta twice because we first need to move the pitch towards its target.
		adjust_parameter_delta := calc_adjust_parameter_delta(data.sample_rate, max(settings.pitch, 0.01))
		settings.pitch = max(move_towards(settings.pitch, target_settings.pitch, adjust_parameter_delta), 0.01)
		pitch := settings.pitch
		adjust_parameter_delta = calc_adjust_parameter_delta(data.sample_rate, pitch)

		// We can't just use the `volume_end` value for the volume. We are going to mix in
		// `AUDIO_MIX_CHUNK_SIZE` number of samples. We'd still get clicks in the sound if we hopped
		// to the ending volume. Instead, we calculate what the first sample should use and what
		// the last one should use. Then we feed those into the `add`/`add_interpolate` procedures.
		// It will lerp across the range as it is mixing in the samples.

		volume_start := clamp(settings.volume, 0, 1)
		volume_end := clamp(move_towards(settings.volume, target_settings.volume, adjust_parameter_delta), 0, 1)
		settings.volume = volume_end

		if volume_start == volume_end && volume_end == 0 {
			continue
		}
		
		pan_start := clamp(settings.pan, -1, 1)
		pan_end := clamp(move_towards(settings.pan, target_settings.pan, adjust_parameter_delta), -1, 1)
		settings.pan = pan_end
		
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
		source_dest_ratio: f32 = 1
		
		if interpolate {
			source_dest_ratio = (pitch * f32(data.sample_rate)) / f32(AUDIO_MIX_SAMPLE_RATE)
		}

		source_channels := 1
		if data.channels == .Stereo {
			source_channels = 2
		}

		num_mixed := audio_mix(
			s.mix_buffer[s.mix_buffer_offset:],
			data.samples[ps.offset:],
			data.channels,
			interpolate,
			source_dest_ratio,
			AUDIO_MIX_CHUNK_SIZE,
			ps.offset_fraction,
			volume_start,
			volume_end,
			pan_stereo_start,
			pan_stereo_end,
		)
		
		if interpolate {
			num_mixed_f32 := f32(num_mixed) * source_dest_ratio
			fraction_advance := ps.offset_fraction + num_mixed_f32

			// The fraction advance may become larger than 1, in which case the offset needs to eat
			// the integer part.
			ps.offset += int(fraction_advance) * source_channels
			
			ps.offset_fraction = linalg.fract(fraction_advance)
		} else {
			ps.offset += num_mixed * source_channels
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

				num_mixed = audio_mix(
					s.mix_buffer[s.mix_buffer_offset + num_mixed:],
					data.samples[ps.offset:],
					data.channels,
					interpolate,
					source_dest_ratio,
					overflow,
					ps.offset_fraction,
					volume_start,
					volume_end,
					pan_stereo_start,
					pan_stereo_end,
				)
				
				if interpolate {
					num_mixed_f32 := f32(num_mixed) * source_dest_ratio
					fraction_advance := ps.offset_fraction + num_mixed_f32

					// The fraction advance may become larger than 1, in which case the offset needs to eat
					// the integer part.
					ps.offset += int(fraction_advance) * source_channels
					
					ps.offset_fraction = linalg.fract(fraction_advance)
				} else {
					ps.offset += num_mixed * source_channels
					ps.offset_fraction = 0
				}
			} else {
				hm.remove(&s.playing_audio_buffers, ps_handle)
				continue
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

//-------------//
// MATHEMATICS //
//-------------//

// Returns true if rectangles `a` and `b` are overlapping.
rect_overlapping :: proc(a: Rect, b: Rect) -> bool {
	return \
		a.x < b.x + b.w &&
		a.x + a.w > b.x &&
		a.y < b.y + b.h &&
		a.y + a.h > b.y
}

// Returns the overlap of rectangle `a` and `b`. The second return value is `false` if no overlap
// was found, `true` otherwise.
rect_overlap :: proc(a: Rect, b: Rect) -> (Rect, bool) {
	overlap_x := max(0, min(a.x + a.w, b.x + b.w) - max(a.x, b.x))
	overlap_y := max(0, min(a.y + a.h, b.y + b.h) - max(a.y, b.y))

	if overlap_x == 0 || overlap_y == 0 {
		return {}, false
	}

	return {
		x = max(a.x, b.x),
		y = max(a.y, b.y),
		w = overlap_x,
		h = overlap_y,
	}, true
}

// Return true if `point` is inside `rect`.
point_in_rect :: proc(point: Vec2, rect: Rect) -> bool {
	return \
		point.x >= rect.x &&
		point.x < rect.x + rect.w &&
		point.y >= rect.y &&
		point.y < rect.y + rect.h
}

// Returns the mid-point of a rectangle.
//
// Useful when for passing as `origin` to drawing procedures, especially when you want the
// drawn thing to rotate around its center.
rect_middle :: proc(r: Rect) -> Vec2 {
	return { r.x + r.w/2, r.y + r.h/2 }
}

rect_center :: rect_middle
rect_centre :: rect_middle

// Combine a position and a size into a rectangle.
rect_from_pos_size :: proc(pos: Vec2, size: Vec2) -> Rect {
	return {
		x = pos.x,
		y = pos.y,
		w = size.x,
		h = size.y,
	}
}

// Get the top left corner of a rectangle.
rect_top_left :: proc(r: Rect) -> Vec2 {
	return {r.x, r.y}
}

// Get the top middle point of a rectangle. That is, the mid-point between the top left and top
// right corners.
rect_top_middle :: proc(r: Rect) -> Vec2 {
	return {r.x + r.w / 2, r.y}
}

// Get the top right corner of a rectangle.
rect_top_right :: proc(r: Rect) -> Vec2 {
	return {r.x + r.w, r.y}
}

// Get the bottom left corner of a rectangle.
rect_bottom_left :: proc(r: Rect) -> Vec2 {
	return {r.x, r.y + r.h}
}

// Get the bottom middle point of a rectangle. That is, the mid-point between the bottom left and
// bottom right corners.
rect_bottom_middle :: proc(r: Rect) -> Vec2 {
	return {r.x + r.w / 2, r.y + r.h}
}

// Get the bottom right corner of a rectangle.
rect_bottom_right :: proc(r: Rect) -> Vec2 {
	return {r.x + r.w, r.y + r.h}
}

// Make a rectangle smaller by `x` pixels in the horizontal direction and `y` pixels in the vertical
rect_shrink :: proc(r: Rect, x: f32, y: f32) -> Rect {
	return {
		r.x + x,
		r.y + y,
		r.w - x * 2,
		r.h - y * 2,
	}
}

// Make a rectangle bigger by `x` pixels in the horizontal direction and `y` pixels in the vertical.
rect_expand :: proc(r: Rect, x: f32, y: f32) -> Rect {
	return {
		r.x - x,
		r.y - y,
		r.w + x * 2,
		r.h + y * 2,
	}
}

// Cut off `h` pixels from the top of `r`. `r` is modified. The cut off part is returned.
// `m` is the margin added above the cut part.
rect_cut_top :: proc(r: ^Rect, h: f32, m: f32) -> Rect {
	res := r^
	res.y += m
	res.h = h
	r.y += h + m
	r.h -= h + m
	return res
}

// Cut off `h` pixels from the bottom of `r`. `r` is modified. The cut off part is returned.
// `m` is the margin added below the cut part.
rect_cut_bottom :: proc(r: ^Rect, h: f32, m: f32) -> Rect {
	res := r^
	res.h = h
	res.y = r.y + r.h - h - m
	r.h -= h + m
	return res
}

// Cut off `w` pixels from the left of `r`. `r` is modified. The cut off part is returned.
// `m` is the margin added to the left of the cut part.
rect_cut_left :: proc(r: ^Rect, w: f32, m: f32) -> Rect {
	res := r^
	res.x += m
	res.w = w
	r.x += w + m
	r.w -= w + m
	return res
}

// Cut off `w` pixels from the right of `r`. `r` is modified. The cut off part is returned.
// `m` is the margin added to the right of the cut part.
rect_cut_right :: proc(r: ^Rect, w: f32, m: f32) -> Rect {
	res := r^
	res.w = w
	res.x = r.x + r.w - w - m
	r.w -= w + m
	return res
}

// Rotate 2D vector `v` by `angle_radians` radians around the origin (0, 0).
//
// If you need to rotate around a point that is not the origin, then you can first subtract the
// point from `v`, then rotate and then add the point back to the result.
rotate :: proc(v: Vec2, angle_radians: f32) -> Vec2 {
	cos := math.cos(angle_radians)
	sin := math.sin(angle_radians)

	return {
		v.x * cos - v.y * sin,
		v.x * sin + v.y * cos,
	}
}

//-------//
// FONTS //
//-------//

// Loads a font from disk and returns a handle that represents it.
load_font_from_file :: proc(filename: string, options: Font_Options = {}) -> Font {
	data, data_ok := read_entire_file(filename, s.frame_allocator)

	if !data_ok {
		log.errorf("Failed loading font %s", filename)
		return FONT_NONE
	}

	return load_font_from_bytes(data, options)
}

// Loads a font from a block of memory and returns a handle that represents it.
load_font_from_bytes :: proc(data: []u8, options: Font_Options = {}) -> Font {
	font := fs.AddFontMem(&s.fs, "", slice.clone(data, s.allocator), false)
	h := Font(len(s.fonts))

	data := Font_Data {
		fontstash_handle = font,
		atlas = {
			handle = rb.create_texture(FONT_DEFAULT_ATLAS_SIZE, FONT_DEFAULT_ATLAS_SIZE, .RGBA_8_Norm),
			width = FONT_DEFAULT_ATLAS_SIZE,
			height = FONT_DEFAULT_ATLAS_SIZE,
		},
		options = options,
	}

	set_texture_filter(data.atlas, options.filter)
	append(&s.fonts, data)
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
	delete(s.fs.fonts[f.fontstash_handle].loadedData, s.allocator)
	s.fs.fonts[f.fontstash_handle].glyphs = {}
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
		shd.texture_lookup[strings.clone(tbp.name, s.allocator)] = tbp_idx

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

	for k, _ in shader.texture_lookup {
		delete(k, a)
	}
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
		s.view_matrix = camera_view_matrix(c)
	} else {
		s.view_matrix = 1
	}
}

// Transform a point `pos` that lives on the screen to a point in the world. This can be useful for
// bringing (for example) mouse positions (k2.get_mouse_position()) into world-space.
screen_to_world :: proc(pos: Vec2, camera: Camera) -> Vec2 {
	return (camera_world_matrix(camera) * Vec4 { pos.x, pos.y, 0, 1 }).xy
}

// Transform a point `pos` that lives in the world to a point on the screen. This can be useful when
// you need to take a position in the world and compare it to a screen-space point.
world_to_screen :: proc(pos: Vec2, camera: Camera) -> Vec2 {
	return (camera_view_matrix(camera) * Vec4 { pos.x, pos.y, 0, 1 }).xy
}

// Calculate the matrix that `screen_to_world` and `world_to_screen` uses to do transformations.
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
camera_view_matrix :: proc(c: Camera) -> Mat4 {
	inv_target_translate := linalg.matrix4_translate(vec3_from_vec2(-c.target))
	inv_rot := linalg.matrix4_rotate_f32(c.rotation, {0, 0, 1})
	inv_scale := linalg.matrix4_scale(Vec3{c.zoom, c.zoom, 1})
	inv_offset_translate := linalg.matrix4_translate(vec3_from_vec2(c.offset))

	return inv_offset_translate * inv_scale * inv_rot * inv_target_translate
}

// Calculate the matrix that brings something in front of the camera.
camera_world_matrix :: proc(c: Camera) -> Mat4 {
	offset_translate := linalg.matrix4_translate(vec3_from_vec2(-c.offset))
	rot := linalg.matrix4_rotate_f32(-c.rotation, {0, 0, 1})
	scale := linalg.matrix4_scale(Vec3{1/c.zoom, 1/c.zoom, 1})
	target_translate := linalg.matrix4_translate(vec3_from_vec2(c.target))

	return target_translate * rot * scale * offset_translate
}

get_fullscreen_rect :: proc() -> Rect {
	return Rect {
		x = 0,
		y = 0,
		w = f32(pf.get_screen_width()),
		h = f32(pf.get_screen_height()),
	}
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
	ab.set_internal_state(s.audio_backend_state)
}

Open_URL_Error :: enum {
	None,

	// The URL does not start with https://, http:// or file:///, or contains a space
	Invalid_URL,

	// Platform-specific failure: Perhaps the OS-specific utility that opens URLs failed.
	Failed_To_Open,
}

// Open a URL in the default web browser, if possible.
//
// Requirements:
// - The URL must start with https://, http:// or file:///
// - The URL may not contain spaces
//
// Returns Open_URL_Error.None if the call was succesful.
open_url :: proc(url: string) -> Open_URL_Error {
	if (
		!strings.has_prefix(url, "https://") &&
		!strings.has_prefix(url, "http://") &&
		!strings.has_prefix(url, "file:///")
	) {
		return .Invalid_URL
	}

	// Shouldn't contain spaces in the middle.
	if strings.contains_space(strings.trim_space(url)) {
		return .Invalid_URL
	}

	platform_call_ok := pf.open_url(url)

	if !platform_call_ok {
		return .Failed_To_Open
	}

	return .None
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
LIGHT_GRAY   :: Color { 183, 183, 183, 255 } 
GRAY         :: Color { 100, 100, 100, 255} 
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

Font_Options :: struct {
	// When the font is loaded, the alpha value of each pixel will be multiplied into its RGB values.
	// This is useful if you want to use `set_blend_mode(.Premultiplied_Alpha)` when drawing text.
	premultiply_alpha: bool,

	// Passed on to font atlas creation.
	filter: Texture_Filter,
}

Font_Data :: struct {
	atlas: Texture,
	options: Font_Options,

	// internal
	fontstash_handle: int,
}

Handle :: hm.Handle64
Texture_Handle :: distinct Handle
Render_Target_Handle :: distinct Handle
Font :: distinct int
DEFAULT_FONT_DATA :: #load("default_fonts/roboto.ttf")

FONT_NONE :: Font(0)
FONT_DEFAULT :: Font(1) // There is always a default font at index 1, loaded in `init`

TEXTURE_NONE :: Texture_Handle {}
RENDER_TARGET_NONE :: Render_Target_Handle {}

AUDIO_MIX_SAMPLE_RATE :: 44100
AUDIO_MIX_CHUNK_SIZE :: 1400

// Single channel audio sample. Can have a value between -1 and 1. For stereo sound every other
// sample in an array of samples will be interpreted as left and right respectively.
Audio_Sample :: f32

// Represents a sound you can play using the `play_sound` procedure. Loaded using
// `load_sound_from_file` or `load_sound_from_bytes`. Create instances of an already loaded sound
// using `create_sound_instance`.
Sound :: distinct Handle

SOUND_NONE :: Sound {}

// A sound instance is what `Sound` handles are mapped to. They contain a handle to a an audio
// buffer, and the settings for use when playing that buffer. The audio buffer may be shared between
// multiple sound instances, which allows you to play the same sound multiple times at the same time
// without having to clone the data.
Sound_Object :: struct {
	handle: Sound,

	// The audio buffer may be used by multiple sound instances. This is the key idea of sound
	// instances: That you can use `create_sound_instance` to make it possible to play a sound
	// multiple times at the same time, without having to clone the data.
	audio_buffer: Audio_Buffer,

	// If true, then the audio buffer will be destroyed when this sound is destroyed. This is true
	// when the sound was loaded using the `load_sound_xxx` procedures. It's false when the sound
	// is created from `create_sound_from_audio_buffer`.
	owns_audio_buffer: bool,

	// If this sound is currently playing, then this identifies the state of the playing sound. It
	// is PLAYING_AUDIO_BUFFER_NONE (zero) when it is not playing.
	playing_buffer_handle: Playing_Audio_Buffer_Handle,

	// This exists both here and in the `Playing_Audio_Buffer`. That way we can store settings
	// even when the sound isn't playing. Set using `set_sound_volume/pan/pitch`.
	playback_settings: Audio_Buffer_Playback_Settings,

	// If true, then the playing sound will be set up as "looping" when `play_sound` is called. Set
	// using `set_sound_loop`.
	loop: bool,
}

Audio_Stream :: distinct Handle

AUDIO_STREAM_NONE :: Audio_Stream {}

AUDIO_STREAM_BUFFER_SIZE :: 3 * AUDIO_MIX_SAMPLE_RATE

Audio_Channels :: enum {
	Mono,
	Stereo,
}

Audio_Stream_Mode :: enum {
	From_File,
	From_Bytes,
}

Audio_Stream_Data :: struct {
	handle: Audio_Stream,
	
	vorbis: ^stbv.vorbis,
	playing_buffer_handle: Playing_Audio_Buffer_Handle,
	buffer: Audio_Buffer,
	
	// Where in the audio buffer referred to by `buffer_handle` that we have most recently written
	// samples. Together with the `offset` of the Playing_Audio_Buffer, this forms a circular
	// buffer.
	buffer_write_pos: int,

	playback_settings: Audio_Buffer_Playback_Settings,

	// Different from `loop` in `Playing_Audio_Buffer`. This says if the whole stream should loop
	// when it reaches end-of-file. The `loop` in `Playing_Audio_Buffer` just says to loop the
	// buffer itself. That's something you always want for a stream: We are continously writing
	// data from a file into a small buffer that is a few seconds long.
	loop: bool,

	mode: Audio_Stream_Mode,

	// use if mode = .From_File
	file: ^File,
	file_read_buf: [dynamic]u8,
	file_read_buf_offset: int,

	// use if mode == .From_Bytes
	bytes: []u8,
}

// The format used to describe that data passed to `load_sound_from_bytes_raw`.
Raw_Sound_Format :: enum {
	Integer8,
	Integer16,
	Integer32,
	Float,
}

Audio_Buffer :: distinct Handle

AUDIO_BUFFER_NONE :: Audio_Buffer{}

Audio_Buffer_Object :: struct {
	handle: Audio_Buffer,

	// All the samples of the audio buffer. In the case of stereo, the left and right samples are
	// interleaved.
	samples: []Audio_Sample,

	// The number of samples per second. Note that the mixer uses 44100 samples per second (as
	// defined by AUDIO_MIX_SAMPLE_RATE). When the sample rate of the buffer and the mixer do no
	// match, then interpolation will happen during mixing.
	sample_rate: int,

	// If this is Stereo, then the left and right samples are interleaved in `samples`.
	channels: Audio_Channels,
}

Audio_Buffer_Playback_Settings :: struct {
	volume: f32,
	pan: f32,
	pitch: f32,
}

DEFAULT_AUDIO_BUFFER_PLAYBACK_SETTINGS :: Audio_Buffer_Playback_Settings {
	volume = 1,
	pan = 0,
	pitch = 1,
}

PLAYING_AUDIO_BUFFER_NONE :: Playing_Audio_Buffer_Handle {}

Playing_Audio_Buffer_Handle :: distinct Handle

Playing_Audio_Buffer :: struct {
	handle: Playing_Audio_Buffer_Handle,
	audio_buffer: Audio_Buffer,
	target_settings: Audio_Buffer_Playback_Settings,
	current_settings: Audio_Buffer_Playback_Settings,

	// How many samples have played?
	offset: int,

	// Only used when playing sounds that have pitch != 1 or when the sound has a sample rate that
	// does not match the mixer's sample rate. In those cases we may get "fractional samples"
	// because we may be in samples that are inbetween two samples in the original sound.
	offset_fraction: f32,

	loop: bool,
}

// This keeps track of the internal state of the library. Usually, you do not need to poke at it.
// It is created and kept as a global variable when 'init' is called. 'init' also returns a pointer
// to it, so you can later use 'set_internal_state' to restore it (after for example hot reload).
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

	// Also see FONT_NONE and FONT_DEFAULT
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

	audio_buffers: hm.Dynamic_Handle_Map(Audio_Buffer_Object, Audio_Buffer),
	sounds: hm.Dynamic_Handle_Map(Sound_Object, Sound),

	playing_audio_buffers: hm.Dynamic_Handle_Map(Playing_Audio_Buffer, Playing_Audio_Buffer_Handle),

	audio_streams: hm.Dynamic_Handle_Map(Audio_Stream_Data, Audio_Stream),
	vorbis_alloc: stbv.vorbis_alloc,

	// Mixer will never mix in more than 1.5 * AUDIO_MIX_CHUNK_SIZE. So 10 times the chunk size is
	// ample.
	mix_buffer: [AUDIO_MIX_CHUNK_SIZE*10][2]Audio_Sample,

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

// Returned as a bit_set by `get_held_modifiers`
Modifier :: enum {
	Control,
	Alt,
	Shift,
	Super,
}

MODIFIERS_NONE :: bit_set[Modifier] {}

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

			if font.options.premultiply_alpha {
				a := f32(src) / 255
				expanded_pixels[dst_pixel_idx] = {
					u8(f32(src) * a),
					u8(f32(src) * a),
					u8(f32(src) * a),
					src,
				}
			} else {
				expanded_pixels[dst_pixel_idx] = {255,255,255, src}
			}
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
		fh = FONT_DEFAULT
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
