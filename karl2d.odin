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
import stbtt "vendor:stb/truetype"
import stbrp "vendor:stb/rect_pack"

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
// The window might be slightly larger due to borders and headers. The true width and height will be
// scaled up by the scaling setting in the operating system.
//
// Call `init` before using Karl2D procedures that depend on runtime state, such as window,
// drawing, input, audio, texture, font and shader procedures. Pure helper procedures, types and
// constants can be used before `init`.
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

	s.depth_test = options.depth_test
	s.depth_range_min = options.depth_range_min
	s.depth_range_max = options.depth_range_max

	if !s.depth_test || (s.depth_range_min == 0 && s.depth_range_max == 0) {
		// The range only means something when depth testing is on. When it is off, every vertex
		// gets a z of 0, so we force the default range: a range that does not contain 0 would
		// make the GPU discard everything, showing nothing at all.
		s.depth_range_min = DEPTH_RANGE_DEFAULT_MIN
		s.depth_range_max = DEPTH_RANGE_DEFAULT_MAX
	} else if s.depth_range_min == s.depth_range_max {
		log.errorf(
			"depth_range_min and depth_range_max must differ, both were %v. Using the default range.",
			s.depth_range_min,
		)
		s.depth_range_min = DEPTH_RANGE_DEFAULT_MIN
		s.depth_range_max = DEPTH_RANGE_DEFAULT_MAX
	}

	s.proj_matrix = make_default_projection(
		pf.get_screen_width(),
		pf.get_screen_height(),
		_camera_flip_y(),
	)

	s.view_matrix = 1
	_update_view_projection()

	// Boot up the render backend. It will render into our previously created window.
	rb.init(
		s.render_backend_state,
		window_render_glue,
		pf.get_screen_width(),
		pf.get_screen_height(), 
		options,
		s.allocator,
	)

	// The vertex buffer is created in a render backend-independent way. It is passed to the
	// render backend each frame as part of `draw_current_batch()`.
	s.vertex_buffer_cpu = make([]u8, VERTEX_BUFFER_MAX, s.allocator, loc)

	// Draw calls are recorded here as you draw. `draw_current_batch` runs them. The arena holds the
	// values they point at. It is emptied at the same time.
	s.batch_draw_calls = make([dynamic]Draw_Call, s.allocator, loc)
	batch_arena_err := runtime.arena_init(&s.batch_arena, BATCH_ARENA_BLOCK_SIZE, s.allocator, loc)
	log.assertf(batch_arena_err == nil, "Failed allocating batch arena: %v", batch_arena_err)
	s.batch_allocator = runtime.arena_allocator(&s.batch_arena)

	// The shapes drawing texture is sampled when any shape is drawn. This way we can use the same
	// shader for textured drawing and shape drawing. It's just a white box.
	white_rect: [16*16*4]u8
	slice.fill(white_rect[:], 255)
	shape_drawing_texture, shape_drawing_texture_ok := rb.load_texture(
		white_rect[:],
		16,
		16,
		.RGBA_8_Norm,
	)
	log.assertf(shape_drawing_texture_ok, "Failed loading shape drawing texture")
	s.shape_drawing_texture = shape_drawing_texture

	// The default shader will arrive in a different format depending on backend. GLSL for GL,
	// HLSL for d3d etc.
	s.default_shader = load_shader_from_bytes(rb.default_shader_vertex_source(), rb.default_shader_fragment_source())
	s.current_shader = s.default_shader

	// FontStash enables us to bake fonts from TTF files on-the-fly.
	//
	// Note that FontStash is always set up top-down, regardless of the coordinate system. The text
	// drawing procedures lay glyphs out top-down and place the finished block themselves. That way
	// the layout is identical in both coordinate systems.
	fs.Init(&s.fs, FONT_DEFAULT_ATLAS_SIZE, FONT_DEFAULT_ATLAS_SIZE, .TOPLEFT)
	fs.SetAlignVertical(&s.fs, .TOP)

	// Dummy element so font with index 0 means 'no font'.
	s.fonts = make([dynamic]Font_Data, s.allocator)
	append_nothing(&s.fonts)
	default_font := load_dynamic_font_from_bytes(DEFAULT_FONT_DATA)
	log.assertf(default_font == FONT_DEFAULT, "Default font must be at index %i", FONT_DEFAULT)
	_set_font(FONT_DEFAULT)

	s.events = make([dynamic]Event, s.allocator)
	s.typed_runes = make([dynamic]rune, s.allocator)

	// Audio
	{
		s.audio_backend = AUDIO_BACKEND
		ab = s.audio_backend

		audio_alloc_error: runtime.Allocator_Error
		s.audio_backend_state, audio_alloc_error = mem.alloc(ab.state_size(), allocator = s.allocator)
		log.assertf(audio_alloc_error == nil, "Failed allocating memory for audio backend: %v", audio_alloc_error)
		ab.init(s.audio_backend_state, s.allocator)
		hm.dynamic_init(&s.sounds, s.allocator)
		hm.dynamic_init(&s.audio_clips, s.allocator)
		hm.dynamic_init(&s.audio_streams, s.allocator)
		hm.dynamic_init(&s.audio_buses, s.allocator)
		s.master_bus.target_settings = DEFAULT_AUDIO_BUS_SETTINGS
		s.master_bus.current_settings = DEFAULT_AUDIO_BUS_SETTINGS
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
	assert_initialized()
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
	assert_initialized()
	return s.close_window_requested
}

// Closes the window and cleans up Karl2D's internal state.
shutdown :: proc() {
	assert(s != nil, "You've called 'shutdown' without calling 'init' first")

	// Audio
	{
		hm.dynamic_destroy(&s.audio_streams)
		ab.shutdown()
		hm.dynamic_destroy(&s.sounds)
		hm.dynamic_destroy(&s.audio_clips)
		hm.dynamic_destroy(&s.audio_buses)
		free(s.audio_backend_state, s.allocator)
	}

	delete(s.events)
	destroy_font(FONT_DEFAULT)
	rb.destroy_texture(s.shape_drawing_texture)
	destroy_shader(s.default_shader)
	rb.shutdown()
	delete(s.vertex_buffer_cpu, s.allocator)
	delete(s.batch_draw_calls)
	runtime.arena_destroy(&s.batch_arena)

	pf.shutdown()

	fs.Destroy(&s.fs)
	delete(s.fonts)

	delete(s.typed_runes)

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
	assert_initialized()
	draw_current_batch()
	rb.clear(s.current_render_target, color)
}

// The library may do some internal allocations that have the lifetime of a single frame. This
// procedure empties that Frame Allocator.
//
// Called as part of `update`, but can be called manually if you need more control.
reset_frame_allocator :: proc() {
	assert_initialized()
	free_all(s.frame_allocator)
}

// Calculates how long the previous frame took and how it has been since the application started.
// You can fetch the calculated values using `get_frame_time` and `get_time`.
//
// Called as part of `update`, but can be called manually if you need more control.
calculate_frame_time :: proc() {
	assert_initialized()
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
	assert_initialized()
	draw_current_batch()
	rb.present()
}

// Process all events that have arrived from the platform APIs. This includes keyboard, mouse,
// gamepad and window events. This procedure processes and stores the information that procs like
// `key_went_down` need.
//
// Called by `update`, but can be called manually if you need more control.
process_events :: proc() {
	assert_initialized()
	s.key_went_up = {}
	s.key_went_down = {}
	s.key_repeat = {}
	s.mouse_button_went_up = {}
	s.mouse_button_went_down = {}
	s.gamepad_button_went_up = {}
	s.gamepad_button_went_down = {}
	s.mouse_delta = {}
	s.mouse_wheel_delta = 0
	s.mouse_wheel_delta_horizontal = 0

	runtime.clear(&s.events)
	runtime.clear(&s.typed_runes)
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

		case Event_Key_Repeat:
			s.key_repeat[e.key] = true

		case Event_Mouse_Button_Went_Down:
			s.mouse_button_went_down[e.button] = true
			s.mouse_button_is_held[e.button] = true

		case Event_Mouse_Button_Went_Up:
			s.mouse_button_went_up[e.button] = true
			s.mouse_button_is_held[e.button] = false

		case Event_Typed_Rune:
			append(&s.typed_runes, e.typed)

		case Event_Mouse_Move:
			prev_pos := s.mouse_position
			s.mouse_position.x = e.position.x
			s.mouse_position.y = e.position.y

			s.mouse_delta += s.mouse_position - prev_pos

		case Event_Mouse_Teleported:
			s.mouse_position.x = e.position.x
			s.mouse_position.y = e.position.y

		case Event_Mouse_Wheel:
			s.mouse_wheel_delta = e.delta

		case Event_Mouse_Wheel_Horizontal:
			s.mouse_wheel_delta_horizontal = e.delta

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
			// Recorded draw calls were meant for the old swapchain size.
			draw_current_batch()
			rb.resize_swapchain(e.width, e.height)
			s.proj_matrix = make_default_projection(e.width, e.height, _camera_flip_y())
			_update_view_projection()

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
			draw_current_batch()
			rb.resize_swapchain(e.screen_width, e.screen_height)
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
	assert_initialized()
	return s.events[:]
}

// Returns how many seconds the previous frame took. Often a tiny number such as 0.016 s.
//
// This value is updated when `calculate_frame_time()` runs (which is also called by `update()`).
get_frame_time :: proc() -> f32 {
	assert_initialized()
	return s.frame_time
}

// Returns how many seconds has elapsed since the game started. This is a `f64` number, giving good
// precision when the application runs for a long time.
//
// This value is updated when `calculate_frame_time()` runs (which is also called by `update()`).
get_time :: proc() -> f64 {
	assert_initialized()
	return s.time
}

// Resize the drawing area of the window (the screen) to a new size. While the user cannot resize
// windows with `window_mode == .Windowed_Resizable`, this procedure is able to resize such windows.
set_screen_size :: proc(width: int, height: int) {
	assert_initialized()

	// Recorded draw calls were meant for the old screen size.
	draw_current_batch()
	pf.set_screen_size(width, height)
	rb.resize_swapchain(pf.get_screen_width(), pf.get_screen_height())
}

// Gets the width of the drawing area within the window.
get_screen_width :: proc() -> int {
	assert_initialized()
	return pf.get_screen_width()
}

// Gets the height of the drawing area within the window.
get_screen_height :: proc() -> int  {
	assert_initialized()
	return pf.get_screen_height()
}

// Gets the screen width and height as a 2D vector.
get_screen_size :: proc() -> Vec2 {
	assert_initialized()
	return { f32(pf.get_screen_width()), f32(pf.get_screen_height()) }
}

// Change the window title.
set_window_title :: proc(title: string) {
	assert_initialized()
	pf.set_window_title(title)
}

// Moves the window.
//
// This does nothing for web builds.
set_window_position :: proc(x: int, y: int) {
	assert_initialized()
	pf.set_window_position(x, y)
}

// Gets the window position in the same coordinate system used by `set_window_position`.
//
// This returns {} for web and Wayland builds.
get_window_position :: proc() -> Vec2 {
	assert_initialized()
	return pf.get_window_position()
}

// Fetch the scale of the window. This usually comes from some DPI scaling setting in the OS.
// 1 means 100% scale, 1.5 means 150% etc.
//
// Karl2D does not do any automatic scaling. If you want a scaled resolution, then multiply the
// wanted resolution by the scale and send it into `set_screen_size`. You can use a camera and set
// the zoom to the window scale in order to make things the same percieved size.
get_window_scale :: proc() -> f32 {
	assert_initialized()
	return pf.get_window_scale()
}

// Use to change between windowed mode, resizable windowed mode and fullscreen
set_window_mode :: proc(window_mode: Window_Mode) {
	assert_initialized()
	pf.set_window_mode(window_mode)
}

// Flushes the current batch. A batch consists of a number of draw calls and a vertex buffer. This
// procedure sends all that off to the rendering backend for drawing. Normally, you do not need to
// call this procedure manually. It is done automatically when `present` or `clear` run. It can also
// happen when you destroy a resource such as a texture or shader that is used in the current
// batch.
//
// Note that `set_z` never starts a new draw call: the z value is stored in each vertex rather than
// being part of a draw call's settings, so it's fine to call it before every draw.
//
// All the draw calls of a batch share a vertex buffer of VERTEX_BUFFER_MAX bytes. The shader
// dictates how big a vertex is. The maximum number of vertices in a batch is therefore
// `VERTEX_BUFFER_MAX / shader.vertex_size`. Running out of room flushes the batch automatically.
draw_current_batch :: proc() {
	_finish_draw_call()

	if len(s.batch_draw_calls) > 0 {
		_update_font_atlases()
		rb.draw(s.vertex_buffer_cpu[:s.vertex_buffer_cpu_used], s.batch_draw_calls[:])
		runtime.clear(&s.batch_draw_calls)
	}

	// Both the recorded draw calls and the open one point into the arena, so neither may outlive
	// it. Emptying the arena is also what makes the next draw call take fresh copies.
	s.current_draw_call = {}
	s.vertex_buffer_cpu_used = 0
	free_all(s.batch_allocator)
}

//-------//
// INPUT //
//-------//

// Returns true if a keyboard key went down between the current and the previous frame. Set when
// 'process_events' runs.
//
// If `allow_repeat` is true, then this also returns true for OS-generated key-repeat events (the
// same behavior a text editor wants when you hold down Backspace). The repeat rate and initial
// delay come from the operating system's keyboard settings.
key_went_down :: proc(key: Keyboard_Key, allow_repeat := false) -> bool {
	if s.key_went_down[key] {
		return true
	}

	if allow_repeat && s.key_repeat[key] {
		return true
	}

	return false
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

// Returns all the Unicode code points that were typed since the last frame, taking the current
// keyboard layout into account. This is what you want for text input, as opposed to
// `key_went_down`, which tells you about physical keys rather than the characters they produce.
//
// Control characters (Backspace, Enter, Tab, etc) and presses of modifier keys on their own are
// never included.
//
// Warning: The returned slice is only valid during the current frame! You can make a clone of it
// using the `slice.clone` procedure (import `core:slice`).
get_typed_runes :: proc() -> []rune {
	return s.typed_runes[:]
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
// Positive means scrolling up.
get_mouse_wheel_delta :: proc() -> f32 {
	return s.mouse_wheel_delta
}

// Returns how many clicks the horizontal mouse wheel has scrolled between the previous and current
// frame. Positive means scrolling right.
//
// A tilt wheel or a two-finger sideways swipe on a trackpad drives this one.
get_mouse_wheel_delta_horizontal :: proc() -> f32 {
	return s.mouse_wheel_delta_horizontal
}

// Returns the mouse position, measured from the top-left corner of the window.
get_mouse_position :: proc() -> Vec2 {
	return s.mouse_position
}

// Returns how many pixels the mouse moved between the previous and the current frame.
get_mouse_delta :: proc() -> Vec2 {
	return s.mouse_delta
}

// Locks the mouse within the window. While the mouse is locked, you should no longer use
// get_mouse_position, as it may have weird/static values. Instead, use get_mouse_delta to fetch how
// much the mouse have been moved.
//
// On some platforms the mouse is just stuck at a specific point. On other platforms it may be
// teleported back to the center of the window on each frame.
//
// This call does not hide the cursor, do that separately using `set_cursor_hidden`.
//
// If the window loses focus, then the mouse may get unlocked. You can query the current lock
// status using `is_mouse_locked`, which should take into account if the OS has unlocked it for you
set_mouse_locked :: proc(locked: bool) {
	pf.set_mouse_locked(locked)
}

// Returns true if the mouse is currently locked. Note that the mouse can get unlocked by the OS,
// even though you previously called `set_mouse_locked(true)`. Therefore, it's best to check the
// current status using this procedure and then lock the mouse if needed.
is_mouse_locked :: proc() -> bool {
	return pf.is_mouse_locked()
}

@(deprecated="Use set_mouse_locked instead")
set_cursor_locked :: proc(locked: bool) {
	set_mouse_locked(locked)
}

@(deprecated="Use is_mouse_locked instead")
is_cursor_locked :: proc() -> bool {
	return is_mouse_locked()
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
	_begin_vertices(s.shape_drawing_texture, 6)
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
	_begin_vertices(s.shape_drawing_texture, 3*segments)

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
	_begin_vertices(s.shape_drawing_texture, 3)

	batch_vertex(vertices[0], {0, 0}, c)
	batch_vertex(vertices[1], {1, 1}, c)
	batch_vertex(vertices[2], {0, 1}, c)
}

// Draw a texture at a position. The top-left corner of the texture will end up at the position.
//
// Optional parameters:
// - origin: An offset for the position, and also the point to rotate around.
// - rotation: Measured in radians. Rotates around the top-left corner, plus any `origin` shift.
// - tint: A color to apply to the texture, in a multiplicative way. WHITE means no tinting.
//
// If you want to rotate around the middle of the texture, then try this:
//
//// middle := k2.rect_middle(k2.get_texture_rect(tex))
//// draw_texture(tex, pos + middle, middle, rot)
//
// The texture is fed into the active shader. Everything drawn in a single draw call must therefore
// use the same texture. Drawing with a new texture starts a new draw call. Put several images into
// one big texture, an atlas, to get fewer draw calls.
draw_texture :: proc(
	texture: Texture,
	position: Vec2,
	origin: Vec2 = {},
	rotation: f32 = 0,
	tint := WHITE,
) {
	if texture.handle == TEXTURE_NONE || texture.width == 0 || texture.height == 0 {
		return
	}

	source := get_texture_rect(texture)

	dest := Rect {
		position.x, position.y,
		source.w, source.h,
	}

	draw_texture_fit(
		texture,
		source,
		dest,
		origin,
		rotation,
		tint,
	)
}

// Draw a texture at a position, but only draw the region specified by the `source` rectangle. The
// `source` rectangle is specified in pixel coordinates. You can flip the texture by using negative
// width/height in `source`.
//
// Optional parameters:
// - origin: An offset for the position, and also the point to rotate around.
// - rotation: Measured in radians. Rotates around the top-left corner, plus any `origin` shift.
// - tint: A color to apply to the texture, in a multiplicative way. WHITE means no tinting.
draw_texture_rect :: proc(
	texture: Texture,
	source: Rect,
	position: Vec2,
	origin: Vec2 = {},
	rotation: f32 = 0,
	tint := WHITE,
) {
	dest := Rect {
		position.x, position.y,
		source.w, source.h,
	}

	draw_texture_fit(
		texture,
		source,
		dest,
		origin,
		rotation,
		tint,
	)
}

// Draw a texture by selecting a `source` rectangle and fitting it into a `dest` (destination)
// rectangle. `source` is measured in texture-space pixels and `dest` is measured in world-space
// pixels. You can flip the texture by using negative width/height for the `source` rectangle.
//
// Optional parameters:
// - origin: An offset for the dest rectangle, and also the point to rotate around.
// - rotation: Measured in radians. Rotates around the top-left corner, plus any `origin` shift.
// - tint: A color to apply to the texture, in a multiplicative way. WHITE means no tinting.
draw_texture_fit :: proc(
	texture: Texture,
	source: Rect,
	dest: Rect,
	origin: Vec2 = {},
	rotation: f32 = 0,
	tint := WHITE,
) {
	if texture.handle == TEXTURE_NONE || texture.width == 0 || texture.height == 0 {
		return
	}

	_begin_vertices(texture.handle, 6)

	flip_x: bool

	// Texture pixels are stored top-down, but a flipped `dest` grows upwards, so the texture has to
	// be sampled bottom-up to come out the right way round.
	flip_y := _camera_flip_y()

	source := source
	dest := dest

	if source.w < 0 {
		flip_x = true
		source.w = -source.w
	}

	if source.h < 0 {
		flip_y = !flip_y
		source.h = -source.h
	}

	// HACK: We ask the render backend if this texture needs flipping. The idea is that GL will
	// flip render textures, so we need to automatically unflip them.
	//
	// Could we do something with the projection matrix while drawing into those render textures
	// instead? I tried that, but couldn't get it to work.
	if rb.texture_needs_vertical_flip(texture.handle) {
		flip_y = !flip_y

		if source.h != f32(texture.height) {
			source.y = f32(texture.height) - source.h - source.y
		}
	}

	if dest.w < 0 {
		dest.w *= -1
	}

	if dest.h < 0 {
		dest.h *= -1
	}

	tl, tr, bl, br: Vec2

	// Rotation adapted from Raylib's "DrawTexturePro"
	if rotation == 0 {
		x := dest.x - origin.x
		y := dest.y - origin.y
		tl = { x,         y }
		tr = { x + dest.w, y }
		bl = { x,         y + dest.h }
		br = { x + dest.w, y + dest.h }
	} else {
		sin_rot := math.sin(rotation)
		cos_rot := math.cos(rotation)
		x := dest.x
		y := dest.y
		dx := -origin.x
		dy := -origin.y

		tl = {
			x + dx * cos_rot - dy * sin_rot,
			y + dx * sin_rot + dy * cos_rot,
		}

		tr = {
			x + (dx + dest.w) * cos_rot - dy * sin_rot,
			y + (dx + dest.w) * sin_rot + dy * cos_rot,
		}

		bl = {
			x + dx * cos_rot - (dy + dest.h) * sin_rot,
			y + dx * sin_rot + (dy + dest.h) * cos_rot,
		}

		br = {
			x + (dx + dest.w) * cos_rot - (dy + dest.h) * sin_rot,
			y + (dx + dest.w) * sin_rot + (dy + dest.h) * cos_rot,
		}
	}
	
	ts := Vec2{f32(texture.width), f32(texture.height)}

	up := Vec2{source.x, source.y} / ts
	us := Vec2{source.w, source.h} / ts
	
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

@(deprecated="Use draw_texture_rect instead")
draw_texture_section :: proc(
	texture: Texture,
	source: Rect,
	position: Vec2,
	origin: Vec2 = {},
	rotation: f32 = 0,
	tint := WHITE,
) {
	draw_texture_rect(texture, source, position, origin, rotation, tint)
}

@(deprecated="Use draw_texture_fit instead")
draw_texture_ex :: proc(tex: Texture, src: Rect, dst: Rect, origin: Vec2, rotation: f32, tint := WHITE) {
	draw_texture_fit(tex, src, dst, origin, rotation, tint)
}

// Measures how much space some text of a certain size will use on the screen. Will use the default
// font unless you specify a custom font.
measure_text :: proc(text: string, font_size: f32, font: Font = FONT_DEFAULT) -> Vec2 {
	if font < 0 || int(font) >= len(s.fonts) {
		return {}
	}

	font_object := s.fonts[font]

	switch font_object.type {
	case .Static:
		return measure_text_static(text, font_size, font)

	case .Dynamic:
		return measure_text_dynamic(text, font_size, font)
	}

	return {}

	// ----------

	measure_text_static :: proc(text: string, font_size: f32, font: Font) -> Vec2 {
		w: f32
		line_w: f32

		if int(font) >= len(s.fonts) {
			return {}
		}

		font_object := &s.fonts[font]
		scl := font_size / font_object.static_font_size
		num_linebreaks := 0

		for c in text {
			if c == '\r' {
				continue
			}

			if c == '\n' {
				if line_w > w {
					w = line_w
				}

				line_w = 0
				num_linebreaks += 1
				continue
			}

			if c == '\t' {
				line_w += font_size * 2
				continue
			}
			
			g: ^Font_Baked_Glyph

			for &r in font_object.static_glyph_ranges {
				if c >= r.start && c < r.end {
					g = &font_object.static_glyphs[r.start_idx + int(c - r.start)]
					break
				}
			}

			if g != nil {
				line_w += g.advance*scl
			} else {
				line_w += font_size * 0.5
			}
		}

		// Check last line
		if line_w > w {
			w = line_w
		}

		h := f32(num_linebreaks + 1) * font_object.static_line_spacing * scl

		return {
			w,
			h,
		}
	}

	measure_text_dynamic :: proc(text: string, font_size: f32, font: Font) -> Vec2 {
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

		return TextBounds(&s.fs, font_object.dynamic_fontstash_handle, font_size, text)
	}

}

@(deprecated="Use measure_text(text, font_size, font) instead")
measure_text_ex :: proc(font_handle: Font, text: string, font_size: f32) -> Vec2 {
	return measure_text(text, font_size, font_handle)
}

// Draw text at a position, with a size and color. The position is the top-left position of the
// text. If you've set a camera using `set_camera`, then the font size will be internally scaled
// so that the text appear sharp.
//
// Optional parameters:
// - font: The font to use, uses a default font if none is specified.
// - origin: The origin relative to the top-left position of the text. Used when rotating the text.
// - rotation: Rotating to apply to the text, measured in radians.
draw_text :: proc(
	text: string,
	position: Vec2,
	font_size: f32,
	color: Color,
	font := FONT_DEFAULT,
	origin: Vec2 = {},
	rotation: f32 = 0,
) {
	if int(font) >= len(s.fonts) {
		return
	}

	font_object := &s.fonts[font]

	switch font_object.type {
	case .Static:
		draw_text_static(
			text,
			position,
			font_size,
			color,
			font,
			origin,
			rotation,
		)

	case .Dynamic:
		draw_text_dynamic(
			text,
			position,
			font_size,
			color,
			font,
			origin,
			rotation,
		)
	}

	// ----------

	draw_text_static :: proc(
		text: string,
		position: Vec2,
		font_size: f32,
		color: Color,
		font := FONT_DEFAULT,
		origin: Vec2 = {},
		rotation: f32 = 0,
	) {
		// TODO: Add kerning.

		if int(font) >= len(s.fonts) {
			return
		}

		font_object := &s.fonts[font]

		// Laid out top-down: `char_offset` walks right along a line and down between lines, matching
		// the offsets stbtt baked into the glyphs.
		char_offset: Vec2
		scl := font_size / font_object.static_font_size

		// Where the top of the text block is. The glyph offsets are measured down from it. With
		// flipped Y `position` is the bottom-left corner of the block, so the top is a whole block
		// higher. The height must agree with what `measure_text_static` reports.
		y_up := _camera_flip_y()
		block_top := position.y

		if y_up {
			block_top += f32(count_text_lines(text))*font_object.static_line_spacing*scl
		}

		for c in text {
			if c == '\r' {
				continue
			}

			if c == '\n' {
				char_offset.x = 0 
				char_offset.y += font_object.static_line_spacing * scl
				continue
			}

			if c == '\t' {
				char_offset.x += font_size * 2
				continue
			}

			g: ^Font_Baked_Glyph

			for &r in font_object.static_glyph_ranges {
				if c >= r.start && c < r.end {
					g = &font_object.static_glyphs[r.start_idx + int(c - r.start)]
					break
				}
			}

			if g != nil {
				src := g.rect
				w := src.w * scl
				h := src.h * scl

				// `g.offset` is stbtt's top-down offset from the top of the line to the top of the
				// glyph bitmap. It is what makes descenders hang below the baseline, so it counts
				// down from the top of the block whichever way the Y axis points.
				offset_from_top := char_offset.y + g.offset.y*scl
				glyph_y := y_up ? block_top - offset_from_top - h : block_top + offset_from_top

				glyph_x := position.x + char_offset.x + g.offset.x*scl

				// The destination stays at `position` for every glyph and the per-glyph offset is
				// folded into the origin instead. That way `rotation` pivots the whole text block
				// around `position` rather than each glyph around itself.
				dst := Rect { position.x, position.y, w, h }
				char_origin := origin + position - { glyph_x, glyph_y }

				draw_texture_fit(
					font_object.atlas,
					src,
					dst,
					tint = color,
					origin = char_origin,
					rotation = rotation,
				)

				char_offset.x += g.advance*scl
			} else {
				invalid_rect_size := Vec2 {font_size*0.5, font_size*0.5}
				offset_from_top := char_offset.y + invalid_rect_size.y/2

				invalid_rect_y := y_up \
					? block_top - offset_from_top - invalid_rect_size.y \
					: block_top + offset_from_top

				invalid_rect := Rect {
					position.x + char_offset.x, invalid_rect_y,
					invalid_rect_size.x, invalid_rect_size.y,
				}

				draw_rect(invalid_rect, RED)

				char_offset.x += invalid_rect_size.x
			}
		}
	}

	draw_text_dynamic :: proc(
		text: string,
		position: Vec2,
		font_size: f32,
		color: Color,
		font := FONT_DEFAULT,
		origin: Vec2 = {},
		rotation: f32 = 0,
	) {
		if int(font) >= len(s.fonts) {
			return
		}

		_set_font(font)
		font_object := &s.fonts[font]

		camera_zoom: f32 = 1

		if cam, cam_ok := s.current_camera.?; cam_ok && cam.zoom > 0.001 {
			camera_zoom = cam.zoom
		}

		// Bake the glyph at font_size*camera_zoom pixels so it is sharp at the current zoom level.
		// We then divide quad positions back by camera_zoom to recover world-space coordinates.
		render_size := font_size * camera_zoom

		// FontStash lays the text out top-down starting at (0, 0), so its quads come out as offsets
		// from the top-left of the text block. This is where that corner goes. With flipped Y
		// `position` is the bottom-left corner of the block, so the top is a whole block higher. The
		// height must agree with what `measure_text_dynamic` reports, which is `lines * font_size`.
		y_up := _camera_flip_y()
		block_top := position.y

		if y_up {
			block_top += f32(count_text_lines(text))*font_size
		}

		fs.SetSize(&s.fs, render_size)
		iter := fs.TextIterInit(&s.fs, 0, 0, text)

		q: fs.Quad
		for fs.TextIterNext(&s.fs, &iter, &q) {
			if iter.codepoint == '\n' {
				iter.nexty += render_size
				iter.nextx = 0
				continue
			}

			if iter.codepoint == '\t' {
				iter.nextx += 2*render_size
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

			// Unscale quad positions from render-size space back to text-local world units.
			offset_from_left := q.x0 / camera_zoom
			offset_from_top := q.y0 / camera_zoom
			glyph_w := (q.x1 - q.x0) / camera_zoom
			glyph_h := (q.y1 - q.y0) / camera_zoom

			glyph_y := y_up ? block_top - offset_from_top - glyph_h : block_top + offset_from_top

			glyph_x := position.x + offset_from_left

			// As in `draw_text_static`: keep the destination at `position` and fold the per-glyph
			// offset into the origin, so that `rotation` pivots the block and not each glyph.
			dst := Rect { position.x, position.y, glyph_w, glyph_h }
			char_origin := origin + position - { glyph_x, glyph_y }

			draw_texture_fit(font_object.atlas, src, dst, char_origin, rotation, color)
		}
	}

}

@(deprecated="Use draw_text instead")
draw_text_ex :: proc(font_handle: Font, text: string, pos: Vec2, font_size: f32, color := BLACK) {
	draw_text(text, pos, font_size, color, font_handle)
}

//--------------------//
// TEXTURE MANAGEMENT //
//--------------------//

// Create an empty texture.
//
// The second return value is `true` if the texture was created correctly. It's optional to handle
// this error, it will also be logged. In case of failure, the returned `Texture` will still be
// possible to use, but it won't draw anything.
create_texture :: proc(
	width: int,
	height: int,
	format: Pixel_Format,
) -> (Texture, bool) #optional_ok {
	h, h_ok := rb.create_texture(width, height, format)

	if !h_ok {
		return {}, false
	}

	return {
		handle = h,
		width = width,
		height = height,
	}, true
}

// Load a texture from disk and upload it to the GPU so you can draw it to the screen.
// Supports PNG, BMP, TGA and baseline PNG. Note that progressive PNG files are not supported!
//
// The `options` parameter can be used to specify things things such as premultiplication of alpha.
//
// The second return value is `true` if the texture was loaded correctly. It's optional to handle
// this error, it will also be logged. In case of failure, the returned `Texture` will still be
// possible to use, but it won't draw anything.
load_texture_from_file :: proc(
	filename: string,
	options: Load_Texture_Options = {},
) -> (Texture, bool) #optional_ok {
	data, data_ok := read_entire_file(filename, frame_allocator)

	if !data_ok {
		log.errorf("Failed loading texture %s", filename)
		return {}, false
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
		return {}, false
	}

	return load_texture_from_bytes_raw(img.pixels.buf[:], img.width, img.height, .RGBA_8_Norm)
}

// Load a texture from a byte slice and upload it to the GPU so you can draw it to the screen.
// Supports PNG, BMP, TGA and baseline PNG. Note that progressive PNG files are not supported!
//
// The `options` parameter can be used to specify things things such as premultiplication of alpha.
//
// The second return value is `true` if the texture was loaded correctly. It's optional to handle
// this error, it will also be logged. In case of failure, the returned `Texture` will still be
// possible to use, but it won't draw anything.
load_texture_from_bytes :: proc(
	bytes: []u8,
	options: Load_Texture_Options = {},
) -> (Texture, bool) #optional_ok {
	load_options := image.Options {
		.alpha_add_if_missing,
	}

	if .Premultiply_Alpha in options {
		load_options += { .alpha_premultiply }
	}

	img, img_err := image.load_from_bytes(bytes, options = load_options, allocator = s.frame_allocator)

	if img_err != nil {
		log.errorf("Error loading texture: %v", img_err)
		return {}, false
	}

	return load_texture_from_bytes_raw(img.pixels.buf[:], img.width, img.height, .RGBA_8_Norm)
}

// Load raw texture data. You need to specify the data, size and format of the texture yourself.
// This assumes that there is no header in the data. If your data has a header (you read the data
// from a file on disk), then please use `load_texture_from_bytes` instead.
//
// The second return value is `true` if the texture was loaded correctly. It's optional to handle
// this error, it will also be logged. In case of failure, the returned `Texture` will still be
// possible to use, but it won't draw anything.
load_texture_from_bytes_raw :: proc(
	bytes: []u8,
	width: int,
	height: int,
	format: Pixel_Format,
) -> (Texture, bool) #optional_ok {
	backend_tex, backend_tex_ok := rb.load_texture(bytes[:], width, height, format)

	if !backend_tex_ok {
		return {}, false
	}

	return {
		handle = backend_tex,
		width = width,
		height = height,
	}, true
}

// Create a GPU texture from an image stored in RAM. There are currently no procedures to manipulate
// the image. However, you can create an `Image` struct manually and fill out the data as needed.
//
// The second return value is `true` if the texture was loaded correctly. It's optional to handle
// this error, it will also be logged. In case of failure, the returned `Texture` will still be
// possible to use, but it won't draw anything.
load_texture_from_image :: proc(image: Image) -> (Texture, bool) #optional_ok {
	if image.width == 0 || image.height == 0 {
		log.error("Invalid image: Height or width is zero")
		return {}, false
	}

	if len(image.pixels) != (image.width*image.height) {
		log.error("Invalid image: the pixels array is not of size image.width*image.height")
		return {}, false
	}

	backend_tex, backend_tex_ok := rb.load_texture(
		slice.reinterpret([]u8, image.pixels[:]),
		image.width,
		image.height,
		.RGBA_8_Norm,
	)

	if !backend_tex_ok {
		return {}, false
	}

	return {
		handle = backend_tex,
		width = image.width,
		height = image.height,
	}, true
}

// Load an image from disk into RAM. Supports the same formats as `load_texture_from_file`. The
// image is always RGBA8 with straight (non-premultiplied) alpha.
//
// Use `destroy_image` when you are done with it.
//
// The second return value is `true` if the image was loaded correctly. It's optional to handle
// this error, it will also be logged. In case of failure, the returned `Image` will be empty: it
// has no pixels and a width and height of zero.
load_image_from_file :: proc(filename: string) -> (Image, bool) #optional_ok {
	data, data_ok := read_entire_file(filename, frame_allocator)

	if !data_ok {
		log.errorf("Failed loading image %s", filename)
		return {}, false
	}

	return load_image_from_bytes(data)
}

// Load an image from a byte slice into RAM, for instance from `#load("my_image.png")`. Supports
// the same formats as `load_texture_from_bytes`. The image is always RGBA8 with straight
// (non-premultiplied) alpha.
//
// Use `destroy_image` when you are done with it.
//
// The second return value is `true` if the image was loaded correctly. It's optional to handle
// this error, it will also be logged. In case of failure, the returned `Image` will be empty: it
// has no pixels and a width and height of zero.
load_image_from_bytes :: proc(bytes: []u8) -> (Image, bool) #optional_ok {
	img, img_err := image.load_from_bytes(
		bytes,
		options = {.alpha_add_if_missing},
		allocator = s.frame_allocator,
	)

	if img_err != nil {
		log.errorf("Error loading image: %v", img_err)
		return {}, false
	}

	if img.depth != 8 || img.channels != 4 {
		log.errorf(
			"Error loading image: expected 8-bit RGBA, got %v-bit with %v channels",
			img.depth, img.channels,
		)
		image.destroy(img, s.frame_allocator)
		return {}, false
	}

	pixels := make([]Color, img.width*img.height, s.allocator)
	copy(pixels, slice.reinterpret([]Color, img.pixels.buf[:]))

	res := Image {
		pixels = pixels,
		width = img.width,
		height = img.height,
	}

	image.destroy(img, s.frame_allocator)
	return res, true
}

@(deprecated="Use load_image_from_file instead")
load_image :: proc(filename: string) -> (Image, bool) #optional_ok {
	return load_image_from_file(filename)
}

// Destroy an image previously loaded using `load_image_from_file` or `load_image_from_bytes`.
destroy_image :: proc(img: Image) {
	delete(img.pixels, s.allocator)
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
	// Recorded draw calls may still be waiting to use the old pixels.
	_flush_if_batch_uses_texture(tex.handle)
	return rb.update_texture(tex.handle, bytes, rect)
}

// Destroy a texture, freeing up any memory it has used on the GPU.
destroy_texture :: proc(tex: Texture) {
	_flush_if_batch_uses_texture(tex.handle)
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
	// Recorded draw calls may still be waiting to sample this texture with the old filter.
	_flush_if_batch_uses_texture(t.handle)
	rb.set_texture_filter(t.handle, scale_down_filter, scale_up_filter, mip_filter)
}

//-------//
// AUDIO //
//-------//

// Play an audio clip with the supplied initial settings. The return value is a `Sound`, which means
// something that is currently playing in the audio mixer. You can use the returned `Sound` with
// `set_sound_volume`, `stop_sound` etc in order to control the playback. Ignore the return value
// if you just want to start the sound and never touch it again.
//
// Audio clips are loaded using `load_audio_clip_from_file`, `load_audio_clip_from_bytes` and
// `load_audio_clip_from_bytes_raw`.
//
// Pass `bus` to play the sound on an audio bus. It plays on the master bus by default.
//
// Warning: If you pass `loop = true` and don't save the return value anywhere, then you've started
// a sound you cannot stop.
play_audio_clip :: proc(
	clip: Audio_Clip,
	volume: f32 = 1,
	pan: f32 = 0,
	pitch: f32 = 1,
	loop := false,
	bus: Audio_Bus = AUDIO_BUS_MASTER,
) -> Sound {
	audio_clip_object := hm.get(&s.audio_clips, clip)

	if audio_clip_object == nil {
		log.error("Cannot play audio clip, audio clip does not exist.")
		return SOUND_NONE
	}

	if bus != AUDIO_BUS_MASTER && hm.get(&s.audio_buses, bus) == nil {
		log.error("Cannot play audio clip, audio bus does not exist.")
		return SOUND_NONE
	}

	playback_settings := Sound_Settings {
		volume = clamp(volume, 0, 1),
		pan = clamp(pan, -1, 1),
		pitch = max(pitch, 0.01),
	}

	sound_object := Sound_Object {
		clip = clip,
		target_settings = playback_settings,
		current_settings = playback_settings,
		loop = loop,
		bus = bus,
	}

	sound, add_err := hm.add(&s.sounds, sound_object)

	if add_err != nil {
		log.errorf("Failed playing audio clip. Error: %v", add_err)
		return SOUND_NONE
	}

	return sound
}

// Stops the sound, which destroys its playback state in the mixer. For a `Sound` started using
// `play_audio_stream`, this also rewinds the stream to the start. Use `set_sound_paused` to pause
// the Sound instead, which won't lose the current playback position and settings.
stop_sound :: proc(sound: Sound) {
	sound_object := hm.get(&s.sounds, sound)

	if sound_object == nil {
		return
	}

	stream := sound_object.stream
	hm.remove(&s.sounds, sound)

	if stream != AUDIO_STREAM_NONE {
		_reset_audio_stream(stream)
	}
}

// Pause or unpause a sound. A paused sound keeps its position and stays valid until it is unpaused
// or stopped.
set_sound_paused :: proc(sound: Sound, paused: bool) {
	sound_object := hm.get(&s.sounds, sound)

	if sound_object == nil {
		return
	}

	sound_object.paused = paused
}

// Returns true if the sound exists and is not paused.
sound_is_playing :: proc(sound: Sound) -> bool {
	sound_object := hm.get(&s.sounds, sound)
	return sound_object != nil && !sound_object.paused
}

// Returns true if the sound still exists. Both playing and paused sounds are valid. A finished or
// stopped sound is not.
sound_is_valid :: proc(sound: Sound) -> bool {
	return hm.is_valid(&s.sounds, sound)
}

// Set the volume of a sound. Range: 0 to 1.
set_sound_volume :: proc(sound: Sound, volume: f32) {
	sound_object := hm.get(&s.sounds, sound)

	if sound_object == nil {
		return
	}

	sound_object.target_settings.volume = clamp(volume, 0, 1)
}

// Set the pan of a sound. Range: -1 to 1, where -1 is full left, 0 is center and 1 is full right.
set_sound_pan :: proc(sound: Sound, pan: f32) {
	sound_object := hm.get(&s.sounds, sound)

	if sound_object == nil {
		return
	}

	sound_object.target_settings.pan = clamp(pan, -1, 1)
}

// Set the pitch of a sound. Range: 0.01 and up, where 1 is the default. Pitch 2 makes the sound
// play twice as fast, which also makes it sound higher pitched.
set_sound_pitch :: proc(sound: Sound, pitch: f32) {
	sound_object := hm.get(&s.sounds, sound)

	if sound_object == nil {
		return
	}

	sound_object.target_settings.pitch = max(pitch, 0.01)
}

// Move the sound to another spot in its audio. `seconds` is measured from the start of the audio,
// so 0 moves it back to the beginning. Use `get_sound_length` to find out how far you can go.
//
// Moving a sound that plays an audio stream is a bit slower than one that plays a clip, since some
// audio has to be decoded before it can play. Don't do it every frame while dragging a scrub bar,
// do it when the player lets go.
set_sound_time :: proc(sound: Sound, seconds: f32) {
	sound_object := hm.get(&s.sounds, sound)

	if sound_object == nil {
		return
	}

	wanted_seconds := max(seconds, 0)
	length := get_sound_length(sound)

	if length > 0 {
		wanted_seconds = min(wanted_seconds, length)
	}

	// Jumping to another spot in the audio makes the waveform jump, which is heard as a click. So
	// we don't jump right away: The mixer fades the sound out first, then jumps, then fades it
	// back in. A paused sound isn't being mixed, so there is nothing to fade and nothing that
	// could click. Jump straight away in that case.
	if sound_object.paused {
		// Fade the sound in when it is unpaused, instead of jumping straight into the middle of
		// the waveform.
		sound_object.seek_fade = 1
		_apply_sound_time(sound, wanted_seconds)
		return
	}

	sound_object.pending_seek_seconds = wanted_seconds
	sound_object.has_pending_seek = true
}

// Get how far into its audio the sound currently is, in seconds. A looping sound goes back to 0
// each time it starts over. Returns 0 if the sound doesn't exist.
get_sound_time :: proc(sound: Sound) -> f32 {
	sound_object := hm.get(&s.sounds, sound)

	if sound_object == nil {
		return 0
	}

	// A seek that is still fading out hasn't moved the sound yet, but it is on its way there.
	// Report where it is going, so that things like a seek bar don't jump backwards for a moment.
	if sound_object.has_pending_seek {
		return sound_object.pending_seek_seconds
	}

	if sound_object.stream == AUDIO_STREAM_NONE {
		clip := hm.get(&s.audio_clips, sound_object.clip)

		if clip == nil {
			return 0
		}

		channels := 1
		if clip.channels == .Stereo {
			channels = 2
		}

		return f32(sound_object.offset / channels) / f32(clip.sample_rate)
	}

	sd := hm.get(&s.audio_streams, sound_object.stream)

	if sd == nil {
		return 0
	}

	ab := hm.get(&s.audio_clips, sd.clip)

	if ab == nil {
		return 0
	}

	channels := 1
	if ab.channels == .Stereo {
		channels = 2
	}

	// A seek that is still catching up has emptied the buffer, so there is nothing in there to
	// measure. Report where the sound is about to be instead.
	if sd.seek_discard > 0 {
		return f32((sd.decode_cursor + sd.seek_discard) / channels) / f32(ab.sample_rate)
	}

	// How many decoded samples are still sitting unplayed in the circular staging buffer.
	remaining := sd.buffer_write_pos - sound_object.offset

	if remaining < 0 {
		remaining = len(ab.samples) - sound_object.offset + sd.buffer_write_pos
	}

	position := sd.decode_cursor - remaining

	// A looping stream starts decoding the beginning of the file again before the listener has
	// heard the end of it, since the end is still sitting in the buffer. Count back into the
	// previous time round, so that the last bit of the audio is reported instead of jumping to
	// the start early.
	for position < 0 && sd.total_samples > 0 {
		position += sd.total_samples
	}

	return f32(max(position, 0) / channels) / f32(ab.sample_rate)
}

// Get the length of the sound's audio, in seconds. Use it together with `get_sound_time` to show
// how far into a song you are. Returns 0 if the sound doesn't exist or if the length is unknown.
get_sound_length :: proc(sound: Sound) -> f32 {
	sound_object := hm.get(&s.sounds, sound)

	if sound_object == nil {
		return 0
	}

	if sound_object.stream == AUDIO_STREAM_NONE {
		clip := hm.get(&s.audio_clips, sound_object.clip)

		if clip == nil {
			return 0
		}

		channels := 1
		if clip.channels == .Stereo {
			channels = 2
		}

		return f32(len(clip.samples) / channels) / f32(clip.sample_rate)
	}

	sd := hm.get(&s.audio_streams, sound_object.stream)

	if sd == nil {
		return 0
	}

	ab := hm.get(&s.audio_clips, sd.clip)

	if ab == nil {
		return 0
	}

	channels := 1
	if ab.channels == .Stereo {
		channels = 2
	}

	return f32(sd.total_samples / channels) / f32(ab.sample_rate)
}

// Make a sound loop when it reaches the end.
//
// Technical note: This also works for sounds started using `play_audio_stream`, but then it
// reaches into the streaming decoder and tells that one to loop. A `Sound` started from a stream
// plays a short buffer that the decoder keeps filling, so that sound always loops.
set_sound_loop :: proc(sound: Sound, loop: bool) {
	sound_object := hm.get(&s.sounds, sound)

	if sound_object == nil {
		return
	}

	// A stream loops by seeking its decoder back to the start. The voice of a stream always loops:
	// that is what makes its buffer circular, so it must not be touched here.
	if sound_object.stream != AUDIO_STREAM_NONE {
		if sd := hm.get(&s.audio_streams, sound_object.stream); sd != nil {
			sd.loop = loop
		}

		return
	}

	sound_object.loop = loop
}

// Route a sound into an audio bus. Pass `AUDIO_BUS_MASTER` for the master bus.
set_sound_bus :: proc(sound: Sound, bus: Audio_Bus) {
	sound_object := hm.get(&s.sounds, sound)

	if sound_object == nil {
		return
	}

	if bus != AUDIO_BUS_MASTER && hm.get(&s.audio_buses, bus) == nil {
		log.error("Cannot set bus, audio bus does not exist.")
		return
	}

	sound_object.bus = bus
}

// How many sounds currently play this clip. Useful for limiting how many overlapping sounds you
// start from the same clip.
get_num_sounds_playing_clip :: proc(clip: Audio_Clip) -> int {
	count: int

	for it := hm.dynamic_iterator_make(&s.sounds); sound_object, _ in hm.dynamic_iterate(&it) {
		if sound_object.clip == clip {
			count += 1
		}
	}

	return count
}

// Load a WAV file from disk. Returns an `Audio_Clip` which can be played using `play_audio_clip`.
//
// Supports mono and stereo WAV files with 8, 16, 24 or 32 bit integer samples, or 32 or 64 bit
// float samples.
//
// The second return value is `true` if the audio clip was loaded correctly. It's optional to
// handle this error, it will also be logged. In case of failure, the returned `Audio_Clip` will
// still be possible to use, but it won't play anything.
load_audio_clip_from_file :: proc(filename: string) -> (Audio_Clip, bool) #optional_ok {
	data, data_ok := read_entire_file(filename, frame_allocator)

	if !data_ok {
		log.errorf("Failed to load audio clip from file '%v'", filename)
		return AUDIO_CLIP_NONE, false
	}

	return load_audio_clip_from_bytes(data)
}

// Load a WAV file from some pre-loaded memory (can be loaded using `#load("sound.wav")`). Returns
// an `Audio_Clip` which can be played using `play_audio_clip`.
//
// Supports mono and stereo WAV data with 8, 16, 24 or 32 bit integer samples, or 32 or 64 bit
// float samples. Note that the data should be the entire WAV file, including the header. If your
// data does not include the header, then please use `load_audio_clip_from_bytes_raw`.
//
// The second return value is `true` if the audio clip was loaded correctly. It's optional to
// handle this error, it will also be logged. In case of failure, the returned `Audio_Clip` will
// still be possible to use, but it won't play anything.
load_audio_clip_from_bytes :: proc(bytes: []u8) -> (_clip: Audio_Clip, _ok: bool) #optional_ok {
	// A WAV file is a RIFF file: A 12 byte header followed by any number of chunks.
	if len(bytes) < 12 {
		log.error("Invalid wav file: Too small to contain a RIFF header")
		return
	}

	if string(bytes[:4]) != "RIFF" {
		log.error("Invalid wav file: No RIFF identifier")
		return
	}

	// This size can only fail to read if there are less than four bytes left, which the check above
	// rules out. Same thing for the reads of the chunk headers further down.
	riff_size, _ := endian.get_u32(bytes[4:8], .Little)

	if string(bytes[8:12]) != "WAVE" {
		log.error("Invalid wav file: Not WAVE format")
		return
	}

	// `riff_size` counts everything after itself. Some programs write a size that doesn't match the
	// file, so use it to cut away trailing junk but never trust it over the size of the buffer.
	chunks_end := len(bytes)

	if riff_end := int(riff_size) + 8; riff_end >= 12 && riff_end < chunks_end {
		chunks_end = riff_end
	}

	chunks := bytes[12:chunks_end]

	sample_rate: int
	samples: []u8
	channels: Audio_Channels
	format: Raw_Audio_Format
	has_fmt: bool
	has_data: bool

	// Each chunk is a four character id, the size of its content as a u32, and then the content
	// itself. We only look at "fmt " and "data". The others carry things such as metadata and loop
	// points, which we don't use.
	for len(chunks) >= 8 {
		chunk_id := string(chunks[:4])
		chunk_size, _ := endian.get_u32(chunks[4:8], .Little)
		content := chunks[8:]

		// Truncated file, or a program that wrote a too big size: Use what is actually there.
		if u64(chunk_size) < u64(len(content)) {
			content = content[:chunk_size]
		}

		switch chunk_id {
		case "fmt ":
			// The values the `audio_format` field below can have. Extensible means that the real
			// format is in a GUID at the end of the chunk. Recording programs tend to use it for
			// anything with more than 16 bits per sample.
			WAV_FORMAT_PCM :: 1
			WAV_FORMAT_FLOAT :: 3
			WAV_FORMAT_EXTENSIBLE :: 0xfffe

			// The fmt chunk is at least 16 bytes:
			//
			//	audio_format:    u16
			//	num_channels:    u16
			//	sample_rate:     u32
			//	byte_per_sec:    u32 // sample_rate * byte_per_bloc
			//	byte_per_bloc:   u16 // (num_channels * bits_per_sample) / 8
			//	bits_per_sample: u16
			if len(content) < 16 {
				log.errorf("Invalid wav fmt chunk: Size is %v, expected at least 16", len(content))
				return
			}

			audio_format, _ := endian.get_u16(content[0:2], .Little)
			num_channels, _ := endian.get_u16(content[2:4], .Little)
			fmt_sample_rate, _ := endian.get_u32(content[4:8], .Little)
			bits_per_sample, _ := endian.get_u16(content[14:16], .Little)

			// Those 16 bytes can be followed by an extension: A u16 with the size of the
			// extension, and for the extensible format also 6 bytes of extra channel information
			// and a 16 byte sub format GUID. The first two bytes of that GUID are the real
			// `audio_format`. We skip the rest: The channel mask in it only matters for more
			// channels than we support.
			if audio_format == WAV_FORMAT_EXTENSIBLE {
				if len(content) < 26 {
					log.errorf("Invalid wav fmt chunk: Size is %v, too small for an extensible " +
						"sub format", len(content))
					return
				}

				audio_format, _ = endian.get_u16(content[24:26], .Little)
			}

			if fmt_sample_rate == 0 {
				log.error("Invalid wav fmt chunk: Sample rate is zero")
				return
			}

			switch num_channels {
			case 1:
				channels = .Mono
			case 2:
				channels = .Stereo
			case:
				log.errorf("Unsupported number of channels in wav fmt chunk: %v", num_channels)
				return
			}

			switch audio_format {
			case WAV_FORMAT_PCM:
				switch bits_per_sample {
				case 8:
					format = .Integer8
				case 16:
					format = .Integer16
				case 24:
					format = .Integer24
				case 32:
					format = .Integer32
				case:
					log.errorf("Unsupported bits per sample in wav fmt chunk: %v", bits_per_sample)
					return
				}

			case WAV_FORMAT_FLOAT:
				switch bits_per_sample {
				case 32:
					format = .Float32
				case 64:
					format = .Float64
				case:
					log.errorf(
						"Unsupported bits per sample in float wav fmt chunk: %v",
						bits_per_sample,
					)
					return
				}

			case:
				log.errorf("Unsupported format in wav fmt chunk: %v", audio_format)
				return
			}

			sample_rate = int(fmt_sample_rate)
			has_fmt = true

		case "data":
			samples = content
			has_data = true
		}

		// Content is padded to an even number of bytes. The pad byte isn't part of the size.
		next := 8 + len(content) + (len(content) & 1)

		if next >= len(chunks) {
			break
		}

		chunks = chunks[next:]
	}

	if !has_fmt {
		log.error("Invalid wav file: No fmt chunk")
		return
	}

	if !has_data {
		log.error("Invalid wav file: No data chunk")
		return
	}

	return load_audio_clip_from_bytes_raw(samples, format, sample_rate, channels)
}

// Load an audio clip from some raw audio data. You need to specify the data, format and sample
// rate of the sound yourself. This assumes that there is no header in the data. If your data has a
// header (for example, you read a whole WAV file from disk), then please use
// `load_audio_clip_from_bytes` instead.
//
// The second return value is `true` if the audio clip was loaded correctly. It's optional to
// handle this error, it will also be logged. In case of failure, the returned `Audio_Clip` will
// still be possible to use, but it won't play anything.
load_audio_clip_from_bytes_raw :: proc(
	bytes: []u8,
	format: Raw_Audio_Format,
	sample_rate: int,
	channels: Audio_Channels,
) -> (Audio_Clip, bool) #optional_ok {
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

	case .Integer24:
		// There is no 24 bit integer type, so shift each sample up into the top of an i32. That
		// makes the same division as for 32 bit samples work.
		num_samples := len(bytes)/3
		samples = make([]Audio_Sample, num_samples, s.allocator)

		for idx in 0..<num_samples {
			b := bytes[idx*3:]
			sample := i32(u32(b[0]) << 8 | u32(b[1]) << 16 | u32(b[2]) << 24)
			samples[idx] = f32(sample) / f32(max(i32))
		}

	case .Integer32:
		samples_i32 := slice.reinterpret([]i32, bytes)
		samples = make([]Audio_Sample, len(samples_i32), s.allocator)

		for idx in 0..<len(samples) {
			samples[idx] = f32(samples_i32[idx]) / f32(max(i32))
		}

	case .Float32:
		samples = slice.clone(slice.reinterpret([]Audio_Sample, bytes), s.allocator)

	case .Float64:
		samples_f64 := slice.reinterpret([]f64, bytes)
		samples = make([]Audio_Sample, len(samples_f64), s.allocator)

		for idx in 0..<len(samples) {
			samples[idx] = Audio_Sample(samples_f64[idx])
		}
	}

	audio_clip_object := Audio_Clip_Object {
		sample_rate = sample_rate,
		samples = samples,
		channels = channels,
	}

	audio_clip, audio_clip_add_error := hm.add(&s.audio_clips, audio_clip_object)

	if audio_clip_add_error != nil {
		log.errorf("Failed to load audio clip. Error: %v", audio_clip_add_error)
		return AUDIO_CLIP_NONE, false
	}

	return audio_clip, true
}

// Destroy an audio clip previously loaded using `load_audio_clip_from_xxx`. Also stops sounds
// playing this clip.
destroy_audio_clip :: proc(clip: Audio_Clip)  {
	audio_clip_object := hm.get(&s.audio_clips, clip)

	if audio_clip_object == nil {
		log.debug("Tried to destroy non-existing audio clip")
		return
	}

	for it := hm.dynamic_iterator_make(&s.sounds); snd, snd_handle in hm.dynamic_iterate(&it) {
		if snd.clip == clip {
			hm.remove(&s.sounds, snd_handle)
		}
	}

	delete(audio_clip_object.samples, s.allocator)
	hm.remove(&s.audio_clips, clip)
}

// Load an audio stream from a file on disk. This is often used for playing music. An audio stream
// only loads a small part of the file at a time. As the file is played, new parts are streamed into
// memory. Start playing the stream using `play_audio_stream`.
//
// Supported file formats: ogg
//
// Audio streams do not stream in data automatically from the disk. You need to call
// `update_audio_stream` every frame to stream in the new data.
//
// The second return value is `true` if the audio stream was loaded correctly. It's optional to
// handle this error, it will also be logged. In case of failure, the returned `Audio_Stream` will
// still be possible to use, but it won't play anything.
load_audio_stream_from_file :: proc(
	filename: string,
) -> (
	_stream: Audio_Stream,
	_ok: bool,
) #optional_ok {
	f, f_err := file_open(filename)

	if f_err != nil {
		log.errorf("Failed opening file %v. Error: %v", filename, f_err)
		return
	}

	buf := make([dynamic]u8, frame_allocator)
	read_buf: [256]u8
	nbytes_read, read_err := file_read(f, read_buf[:])

	if read_err != nil {
		log.errorf("Failed reading from audio stream file %v. Error: %v", filename, read_err)

		if close_err := file_close(f); close_err != nil {
			log.errorf("Failed closing file. Error: %v", close_err)
		}
		
		return
	}

	vorbis_buffer := stbv.vorbis_alloc {
		alloc_buffer = make([^]u8, VORBIS_STATE_SIZE, s.allocator),
		alloc_buffer_length_in_bytes = VORBIS_STATE_SIZE,
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
			&vorbis_buffer,
		)

		if vorbis_err == nil {
			// The file was properly loaded!
			vorbis_res = vorbis
			_, seek_err := file_seek(f, i64(consumed), .Start)

			if seek_err != nil {
				log.errorf("Failed seeking in audio stream file %v. Error: %v", filename, seek_err)
				file_close(f)
				free(vorbis_buffer.alloc_buffer, s.allocator)
				return
			}

			break
		} else if vorbis_err == .need_more_data {
			// Read in more data from the file so that maybe `stbv.open_pushdata` succeeds next
			// iteration.
			nbytes_read, read_err = file_read(f, read_buf[:])

			if read_err != nil {
				log.errorf("Failed reading from audio stream file %v. Error: %v", filename, read_err)
				file_close(f)
				free(vorbis_buffer.alloc_buffer, s.allocator)
				return
			}

			if nbytes_read == 0 {
				log.errorf("Failed to load audio stream. Reached end of file before stream could be loaded.")
				file_close(f)
				free(vorbis_buffer.alloc_buffer, s.allocator)
				return
			}

			append(&buf, ..read_buf[:nbytes_read])
		} else {
			log.errorf("Failed to load audio stream. Error: %v", vorbis_err)
			file_close(f)
			free(vorbis_buffer.alloc_buffer, s.allocator)
			return
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
				
		free(vorbis_buffer.alloc_buffer, s.allocator)
		return
	}

	audio_clip := Audio_Clip_Object {
		sample_rate = int(info.sample_rate),
		samples = make([]Audio_Sample, AUDIO_STREAM_BUFFER_SIZE, s.allocator),
		channels = channels,
	}

	audio_clip_handle, audio_clip_handle_add_err := hm.add(&s.audio_clips, audio_clip)

	if audio_clip_handle_add_err != nil {
		log.errorf("Failed to load audio stream. Error: %v", audio_clip_handle_add_err)
		
		if close_err := file_close(f); close_err != nil {
			log.errorf("Failed closing file. Error: %v", close_err)
		}

		delete(audio_clip.samples, s.allocator)
		free(vorbis_buffer.alloc_buffer, s.allocator)
		return
	}

	asd := Audio_Stream_Data {
		mode = .From_File,
		file = f,
		vorbis = vorbis_res,
		vorbis_buffer = vorbis_buffer,
		clip = audio_clip_handle,
		total_samples = _ogg_file_total_frames(f) * int(info.channels),
		file_read_buf = make([dynamic]u8, s.allocator),
	}

	stream, stream_add_err := hm.add(&s.audio_streams, asd)

	if stream_add_err != nil {
		log.errorf("Failed to create audio stream from file. Error: %v", stream_add_err)
		file_close(asd.file)
		delete(asd.file_read_buf)
		delete(audio_clip.samples, s.allocator)
		hm.remove(&s.audio_clips, audio_clip_handle)
		free(vorbis_buffer.alloc_buffer, s.allocator)
		return
	}

	return stream, true
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
// executable (so the game is a single file). In that case you could also use `#load` to fetch the
// file and then send it into this procedure.
//
// Note that this procedure wants the encoded file, for example an ogg file just like it was on
// disk. For normal sounds there is a `load_audio_clip_from_bytes_raw` procedure where you just send
// in the samples. There is no such procedure for audio streams since the whole idea is to stream an
// encoded file into memory without having to decode the whole thing first.
//
// The second return value is `true` if the audio stream was loaded correctly. It's optional to
// handle this error, it will also be logged. In case of failure, the returned `Audio_Stream` will
// still be possible to use, but it won't play anything.
load_audio_stream_from_bytes :: proc(
	bytes: []u8,
) -> (
	_stream: Audio_Stream,
	_ok: bool,
) #optional_ok {
	vorbis_err: stbv.Error

	vorbis_buffer := stbv.vorbis_alloc {
		alloc_buffer = make([^]u8, VORBIS_STATE_SIZE, s.allocator),
		alloc_buffer_length_in_bytes = VORBIS_STATE_SIZE,
	}

	// This procedure is specifically made for our use case: Streaming from a file that is already
	// completely in memory.
	vorbis_res := stbv.open_memory(
		raw_data(bytes),
		i32(len(bytes)),
		&vorbis_err,
		&vorbis_buffer,
	)

	if vorbis_err != nil {
		log.errorf("Failed opening audio stream from bytes. Error: %v", vorbis_err)
		free(vorbis_buffer.alloc_buffer, s.allocator)
		return
	}

	info := stbv.get_info(vorbis_res)
	channels: Audio_Channels

	if info.channels == 1 {
		channels = Audio_Channels.Mono
	} else if info.channels == 2 {
		channels = Audio_Channels.Stereo
	} else{
		log.errorf("Unsupported number of channels: %v", info.channels)
		free(vorbis_buffer.alloc_buffer, s.allocator)
		return
	}

	audio_clip := Audio_Clip_Object {
		sample_rate = int(info.sample_rate),
		samples = make([]Audio_Sample, AUDIO_STREAM_BUFFER_SIZE, s.allocator),
		channels = channels,
	}

	audio_clip_handle, audio_clip_handle_add_err := hm.add(&s.audio_clips, audio_clip)

	if audio_clip_handle_add_err != nil {
		log.errorf("Failed to load audio stream. Error: %v", audio_clip_handle_add_err)
		delete(audio_clip.samples, s.allocator)
		free(vorbis_buffer.alloc_buffer, s.allocator)
		return
	}

	asd := Audio_Stream_Data {
		mode = .From_Bytes,
		bytes = bytes,
		vorbis = vorbis_res,
		clip = audio_clip_handle,
		vorbis_buffer = vorbis_buffer,
		total_samples = int(stbv.stream_length_in_samples(vorbis_res)) * int(info.channels),
	}

	stream, stream_add_err := hm.add(&s.audio_streams, asd)

	if stream_add_err != nil {
		log.errorf("Failed to create audio stream from bytes. Error: %v", stream_add_err)
		delete(audio_clip.samples, s.allocator)
		hm.remove(&s.audio_clips, audio_clip_handle)
		free(vorbis_buffer.alloc_buffer, s.allocator)
		return
	}

	return stream, true
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

	if playing := hm.get(&s.sounds, sd.sound); playing != nil {
		hm.remove(&s.sounds, sd.sound)
	}

	if ab := hm.get(&s.audio_clips, sd.clip); ab != nil {
		delete(ab.samples, s.allocator)
		hm.remove(&s.audio_clips, sd.clip)
	}

	switch sd.mode {
	case .From_File:
		file_close(sd.file)
		delete(sd.file_read_buf)
	case .From_Bytes:
		// don't free the bytes, they are owned by the game
	}

	free(sd.vorbis_buffer.alloc_buffer, s.allocator)
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

	pab := hm.get(&s.sounds, sd.sound)

	if pab == nil {
		// Don't log an error here: Not playing the stream is a valid state. It just doesn't need
		// any updating.
		return
	}

	ab := hm.get(&s.audio_clips, pab.clip)

	if ab == nil {
		hm.remove(&s.sounds, sd.sound)
		log.error("Trying to update audio stream with destroyed clip")
		return
	}

	audio_stream_remaining :: proc(as: ^Audio_Stream_Data, pab: ^Sound_Object, ab: ^Audio_Clip_Object) -> int {
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
								hm.remove(&s.sounds, sd.sound)
								_reset_audio_stream(stream)
								break
							}

							stbv.flush_pushdata(sd.vorbis)
							sd.decode_cursor = 0

							// A discard larger than the file would otherwise spin forever.
							sd.seek_discard = 0

							continue
						} else {
							hm.remove(&s.sounds, sd.sound)
							_reset_audio_stream(stream)
							break
						}
					} else {
						hm.remove(&s.sounds, sd.sound)
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
						// A pending seek throws away decoded samples instead of writing them,
						// until the decoder has caught up to the target position.
						if sd.seek_discard > 0 {
							sd.seek_discard -= 1
						} else {
							ab.samples[sd.buffer_write_pos] = mono[samp_idx]
							sd.buffer_write_pos = (sd.buffer_write_pos + 1) % len(ab.samples)
						}

						sd.decode_cursor += 1
					}
				} else if channels == 2 {
					left: [^]f32 = output[0]
					right: [^]f32 = output[1]

					for samp_idx in 0..<samples {
						if sd.seek_discard > 0 {
							sd.seek_discard -= 2
						} else {
							ab.samples[sd.buffer_write_pos] = left[samp_idx]
							ab.samples[sd.buffer_write_pos + 1] = right[samp_idx]
							sd.buffer_write_pos = (sd.buffer_write_pos + 2) % len(ab.samples)
						}

						sd.decode_cursor += 2
					}
				} else {
					hm.remove(&s.sounds, sd.sound)
					log.error("Invalid num channels")
					break
				}
				sd.file_read_buf_offset += int(bytes_used)
			} else {
				hm.remove(&s.sounds, sd.sound)
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
					sd.decode_cursor = 0

					// A discard larger than the file would otherwise spin forever.
					sd.seek_discard = 0

					continue
				} else {
					// TODO: Stopping here is bad as the samples haven't been mixed in yet. Remove the
					// stream but push the final samples into the clip and destroy that one
					// when it finishes playing (in the mixer).
					hm.remove(&s.sounds, sd.sound)
					_reset_audio_stream(stream)
					break
				}
			}

			if channels == 1 {
				mono: [^]f32 = output[0]

				for samp_idx in 0..<samples {
					ab.samples[sd.buffer_write_pos] = mono[samp_idx]
					sd.buffer_write_pos = (sd.buffer_write_pos + 1) % len(ab.samples)
					sd.decode_cursor += 1
				}
			} else if channels == 2 {
				left: [^]f32 = output[0]
				right: [^]f32 = output[1]

				for samp_idx in 0..<samples {
					ab.samples[sd.buffer_write_pos] = left[samp_idx]
					ab.samples[sd.buffer_write_pos + 1] = right[samp_idx]
					sd.buffer_write_pos = (sd.buffer_write_pos + 2) % len(ab.samples)
					sd.decode_cursor += 2
				}
			} else {
				hm.remove(&s.sounds, sd.sound)
				log.error("Invalid num channels")
				break
			}
		}
	}
}

// Start playing an audio stream. Returns a `Sound`, which you can control using
// `set_sound_volume`, `stop_sound` etc. The playback starts from wherever the stream last was,
// which is the beginning if the stream was just loaded, was stopped using `stop_sound` or has
// finished playing.
//
// A stream can only play one sound at a time. If it is already playing, then this hands back the
// sound that is already playing and ignores the settings you pass in. Use the `set_sound_xxx`
// procedures to change how it plays. Use `stop_sound` first if you want to start over from the
// beginning. A paused sound starts playing again.
//
// Don't forget to call `update_audio_stream` every frame in order to stream in new data.
play_audio_stream :: proc(
	stream: Audio_Stream,
	volume: f32 = 1,
	pan: f32 = 0,
	pitch: f32 = 1,
	loop := false,
	bus: Audio_Bus = AUDIO_BUS_MASTER,
) -> Sound {
	sd := hm.get(&s.audio_streams, stream)

	if sd == nil {
		log.error("Cannot play audio stream, stream does not exist.")
		return SOUND_NONE
	}

	if bus != AUDIO_BUS_MASTER && hm.get(&s.audio_buses, bus) == nil {
		log.error("Cannot play audio stream, audio bus does not exist.")
		return SOUND_NONE
	}

	// A stream can only feed one sound, and that sound is already playing, so there is nothing to
	// start. Hand back the sound that is already going. Unpause it though: This procedure is how
	// you play a stream, so it should be playing when we are done.
	if existing := hm.get(&s.sounds, sd.sound); existing != nil {
		existing.paused = false
		return sd.sound
	}

	sd.loop = loop

	playback_settings := Sound_Settings {
		volume = clamp(volume, 0, 1),
		pan = clamp(pan, -1, 1),
		pitch = max(pitch, 0.01),
	}

	sound_object := Sound_Object {
		clip = sd.clip,
		target_settings = playback_settings,
		current_settings = playback_settings,
		bus = bus,
		stream = stream,

		// This means that we are looping the buffer itself. We will use this buffer as a circular
		// buffer, filling it with samples as we stream in more. Thus it needs to be looped to not
		// stop when the end of the circular buffer is reached.
		loop = true,
	}

	add_err: runtime.Allocator_Error
	sd.sound, add_err = hm.add(&s.sounds, sound_object)

	if add_err != nil {
		log.errorf("Failed playing audio stream. Error: %v", add_err)
		return SOUND_NONE
	}

	sound := sd.sound

	// Decode into the buffer before returning, so that there is something to play right away. The
	// mixer may well run before the game gets around to calling `update_audio_stream`. A sound
	// that reads an empty buffer moves its read position past the write position, which makes the
	// buffer look full rather than empty, so it would not be refilled until the read position had
	// wrapped all the way around.
	update_audio_stream(stream)

	return sound
}

// Create an audio bus: A group of sounds that are mixed together before they reach the master bus.
// Route sounds into it using `set_sound_bus`, or the `bus` parameter of `play_audio_clip` or
// `play_audio_stream`.
//
// A new bus has volume 1, pan 0 and no effect. That makes it a passthrough: Playing a sound on a
// fresh bus sounds exactly like playing it on the master bus, until you change something.
create_audio_bus :: proc() -> Audio_Bus {
	bus_object := Audio_Bus_Object {
		target_settings = DEFAULT_AUDIO_BUS_SETTINGS,
		current_settings = DEFAULT_AUDIO_BUS_SETTINGS,
	}

	bus, add_err := hm.add(&s.audio_buses, bus_object)

	if add_err != nil {
		log.errorf("Failed creating audio bus. Error: %v", add_err)

		// The master bus always exists, so anything routed to this handle still plays.
		return AUDIO_BUS_MASTER
	}

	return bus
}

// Destroy an audio bus. Everything routed to it goes back to the master bus, including sounds that
// are playing right now.
destroy_audio_bus :: proc(bus: Audio_Bus) {
	if bus == AUDIO_BUS_MASTER {
		log.error("Cannot destroy audio bus, the master bus cannot be destroyed.")
		return
	}

	if hm.get(&s.audio_buses, bus) == nil {
		log.error("Cannot destroy audio bus, audio bus does not exist.")
		return
	}

	// Move everything that points at this bus over to the master bus. We do it here, and not by
	// letting the mixer notice that the bus is gone, so that the mixer never has to deal with a bus
	// handle that doesn't resolve.

	for it := hm.dynamic_iterator_make(&s.sounds); sound_object, _ in hm.dynamic_iterate(&it) {
		if sound_object.bus == bus {
			sound_object.bus = AUDIO_BUS_MASTER
		}
	}

	hm.remove(&s.audio_buses, bus)
}

// Set the volume of an audio bus. Range: 0 to 1. Everything mixed into the bus is scaled by this.
//
// This works on `AUDIO_BUS_MASTER` as well, which is how you set the master volume of your game.
set_audio_bus_volume :: proc(bus: Audio_Bus, volume: f32) {
	bus_object := bus == AUDIO_BUS_MASTER ? &s.master_bus : hm.get(&s.audio_buses, bus)

	if bus_object == nil {
		log.error("Cannot set audio bus volume, audio bus does not exist.")
		return
	}

	bus_object.target_settings.volume = clamp(volume, 0, 1)
}

// Set the pan of an audio bus. Range: -1 to 1, where -1 is full left, 0 is center and 1 is full
// right.
//
// This is a balance control: It turns the opposite side down. The pan of a sound works
// differently: It moves the sound between the left and right speakers while keeping the overall
// loudness the same. A bus is already a finished stereo mix, and a bus at pan 0 has to leave it
// exactly as it is.
set_audio_bus_pan :: proc(bus: Audio_Bus, pan: f32) {
	bus_object := bus == AUDIO_BUS_MASTER ? &s.master_bus : hm.get(&s.audio_buses, bus)

	if bus_object == nil {
		log.error("Cannot set audio bus pan, audio bus does not exist.")
		return
	}

	bus_object.target_settings.pan = clamp(pan, -1, 1)
}

// Set an effect to run on everything that is mixed into the bus. This is how you apply your own
// audio processing, such as a filter, to a whole group of sounds at once.
//
// `user_data` is handed to the effect when it runs. Put whatever state your effect needs there:
// The effect is called once per mixed chunk, so anything it wants to remember between the chunks
// has to live in `user_data`. Pass `nil` as `effect` to remove the effect.
//
// See `Audio_Effect_Proc` for what the effect is given and what it is allowed to do.
set_audio_bus_effect :: proc(bus: Audio_Bus, effect: Audio_Effect_Proc, user_data: rawptr = nil) {
	bus_object := bus == AUDIO_BUS_MASTER ? &s.master_bus : hm.get(&s.audio_buses, bus)

	if bus_object == nil {
		log.error("Cannot set audio bus effect, audio bus does not exist.")
		return
	}

	bus_object.effect = effect
	bus_object.effect_user_data = user_data
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

	// The buses have a chunk each, which the sounds routed to that bus are mixed into. Those hold
	// the previous chunk's mix, so they need zeroing too.
	for it := hm.dynamic_iterator_make(&s.audio_buses); bus, _ in hm.dynamic_iterate(&it) {
		slice.zero(bus.chunk[:])
	}

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
				// Note that this uses `dest_to_write` and not `n`: The ramps run across the whole
				// chunk. If we run out of samples early then only part of the ramp is used here,
				// and the caller carries it on from there.
				t := f32(samp_idx) / f32(dest_to_write)
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
				// Note that this uses `dest_to_write` and not `n`: The ramps run across the whole
				// chunk. If we run out of samples early then only part of the ramp is used here,
				// and the caller carries it on from there.
				t := f32(samp_idx) / f32(dest_to_write)
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

	// Used for the smooth adjustment of volume, pan and pitch, both for the playing sounds below
	// and for the buses further down.

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

	for ps_iter := hm.dynamic_iterator_make(&s.sounds); ps, ps_handle in hm.dynamic_iterate(&ps_iter) {
		data := hm.get(&s.audio_clips, ps.clip)

		if data == nil {
			log.error("Trying to play sound with destroyed data")
			hm.remove(&s.sounds, ps_handle)
			continue
		}

		// A paused sound stays in the list but is not mixed.
		if ps.paused {
			continue
		}

		// Where this sound is mixed into: The chunk of the bus it is routed to, or the output
		// itself, which is the master bus. `destroy_audio_bus` moves everything back to the master
		// bus, so a bus that doesn't resolve shouldn't happen. Fall back to the master bus if it
		// does anyway, without logging: We'd log it 31 times a second.
		dest := out

		if ps.bus != AUDIO_BUS_MASTER {
			if bus := hm.get(&s.audio_buses, ps.bus); bus != nil {
				dest = bus.chunk[:]
			}
		}

		// Before we get to the mixing we smoothly adjust pitch, volume and pan. We do this to avoid
		// clicks in the audio. The clicks happen because abrupt changes cause discontinuities in
		// the audio waveform. Understand: Sound does not happen because the waveform has a high
		// value, it happens because there is a sudden change in the waveform. Bigger change, bigger
		// sound.

		settings := &ps.current_settings
		target_settings := &ps.target_settings

		// We get the delta twice because we first need to move the pitch towards its target.
		adjust_parameter_delta := calc_adjust_parameter_delta(data.sample_rate, max(settings.pitch, 0.01))
		settings.pitch = max(move_towards(settings.pitch, target_settings.pitch, adjust_parameter_delta), 0.01)
		pitch := settings.pitch
		adjust_parameter_delta = calc_adjust_parameter_delta(data.sample_rate, pitch)

		// `set_sound_time` doesn't move the sound itself, it just says where the sound should go.
		// We move it here, once the sound has faded out. Then we fade it back in. That way moving
		// to a completely different part of the waveform doesn't click.

		seek_fade_target: f32 = ps.has_pending_seek ? 1 : 0
		seek_fade_start := clamp(ps.seek_fade, 0, 1)
		seek_fade_moved := move_towards(ps.seek_fade, seek_fade_target, adjust_parameter_delta)
		seek_fade_end := clamp(seek_fade_moved, 0, 1)
		ps.seek_fade = seek_fade_end

		// Wait for `seek_fade_start` rather than `seek_fade_end`: The chunk that fades the sound
		// all the way out is the one that holds the fade, so it still has to be mixed.
		if ps.has_pending_seek && seek_fade_start == 1 {
			seek_seconds := ps.pending_seek_seconds
			ps.has_pending_seek = false

			// This may remove the sound, so `continue` makes us avoid using `ps` after this. There
			// is nothing to mix anyway: The fade has taken the volume all the way down.
			_apply_sound_time(ps_handle, seek_seconds)
			continue
		}

		// We can't just use the `volume_end` value for the volume. We are going to mix in
		// `AUDIO_MIX_CHUNK_SIZE` number of samples. We'd still get clicks in the sound if we hopped
		// to the ending volume. Instead, we calculate what the first sample should use and what
		// the last one should use. Then we feed those into the `add`/`add_interpolate` procedures.
		// It will lerp across the range as it is mixing in the samples.

		volume_start := clamp(settings.volume, 0, 1) * (1 - seek_fade_start)
		volume_end := clamp(move_towards(settings.volume, target_settings.volume, adjust_parameter_delta), 0, 1)
		settings.volume = volume_end
		volume_end *= 1 - seek_fade_end

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
			dest,
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
				mixed_before_loop := num_mixed
				overflow := AUDIO_MIX_CHUNK_SIZE - mixed_before_loop

				// Carry the volume and pan ramps on from where the first part of the chunk got to.
				// Starting them over would jump the volume back up in the middle of the chunk,
				// which is heard as a click.
				split := f32(mixed_before_loop) / f32(AUDIO_MIX_CHUNK_SIZE)
				volume_split := math.lerp(volume_start, volume_end, split)
				pan_stereo_split := linalg.lerp(pan_stereo_start, pan_stereo_end, split)

				num_mixed = audio_mix(
					dest[mixed_before_loop:],
					data.samples[ps.offset:],
					data.channels,
					interpolate,
					source_dest_ratio,
					overflow,
					ps.offset_fraction,
					volume_split,
					volume_end,
					pan_stereo_split,
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
				hm.remove(&s.sounds, ps_handle)
				continue
			}
		}
	}

	// BUSES
	//
	// The sounds routed to a bus have been mixed into that bus's chunk. Now run the effect of each
	// bus on its chunk and mix the chunk into the master bus, which is the `out` slice.

	// The buses run at the mixer's sample rate and are never pitched, so the ramp is the same for
	// all of them.
	bus_adjust_delta := calc_adjust_parameter_delta(AUDIO_MIX_SAMPLE_RATE, 1)

	for it := hm.dynamic_iterator_make(&s.audio_buses); bus, _ in hm.dynamic_iterate(&it) {
		// The effect runs even when the bus is silent. Effects tend to keep state, such as a filter
		// or an echo. Skipping them while silent would leave that state behind, and it would jump
		// once the bus is turned back up.
		if bus.effect != nil {
			bus.effect(bus.chunk[:], bus.effect_user_data)
		}

		volume_start := bus.current_settings.volume
		volume_end := move_towards(volume_start, bus.target_settings.volume, bus_adjust_delta)
		bus.current_settings.volume = volume_end

		pan_start := bus.current_settings.pan
		pan_end := move_towards(pan_start, bus.target_settings.pan, bus_adjust_delta)
		bus.current_settings.pan = pan_end

		if volume_start == 0 && volume_end == 0 {
			continue
		}

		// The pan of a bus is a balance: It turns the opposite side down. The playing sounds use a
		// constant-power curve instead, but that curve scales both channels by 0.707 in the middle.
		// A bus that has not been touched has to leave the mix exactly as it is.
		gain_start := [2]f32 {
			volume_start * min(1, 1 - pan_start),
			volume_start * min(1, 1 + pan_start),
		}

		gain_end := [2]f32 {
			volume_end * min(1, 1 - pan_end),
			volume_end * min(1, 1 + pan_end),
		}

		for samp_idx in 0..<AUDIO_MIX_CHUNK_SIZE {
			t := f32(samp_idx) / f32(AUDIO_MIX_CHUNK_SIZE)
			out[samp_idx] += bus.chunk[samp_idx] * linalg.lerp(gain_start, gain_end, t)
		}
	}

	// MASTER BUS
	//
	// Everything is in `out` now. The master effect, volume and pan apply to the whole mix.

	master := &s.master_bus

	if master.effect != nil {
		master.effect(out, master.effect_user_data)
	}

	volume_start := master.current_settings.volume
	volume_end := move_towards(volume_start, master.target_settings.volume, bus_adjust_delta)
	master.current_settings.volume = volume_end

	pan_start := master.current_settings.pan
	pan_end := move_towards(pan_start, master.target_settings.pan, bus_adjust_delta)
	master.current_settings.pan = pan_end

	// A game that never touches the master bus shouldn't pay for it.
	if volume_start != 1 || volume_end != 1 || pan_start != 0 || pan_end != 0 {
		gain_start := [2]f32 {
			volume_start * min(1, 1 - pan_start),
			volume_start * min(1, 1 + pan_start),
		}

		gain_end := [2]f32 {
			volume_end * min(1, 1 - pan_end),
			volume_end * min(1, 1 + pan_end),
		}

		for samp_idx in 0..<AUDIO_MIX_CHUNK_SIZE {
			t := f32(samp_idx) / f32(AUDIO_MIX_CHUNK_SIZE)
			out[samp_idx] *= linalg.lerp(gain_start, gain_end, t)
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
//
// The second return value is `true` if the render texture was created correctly. It's optional to
// handle this error, it will also be logged. In case of failure, the returned `Render_Texture`
// will still be possible to use, but setting it does nothing, so drawing stays where it was.
create_render_texture :: proc(width: int, height: int) -> (Render_Texture, bool) #optional_ok {
	texture, render_target, render_texture_ok := rb.create_render_texture(width, height)

	if !render_texture_ok {
		return {}, false
	}

	return {
		texture = { 
			handle = texture,
			width = width,
			height = height,
		},
		render_target = render_target,
	}, true
}

// Destroy a Render_Texture previously created using `create_render_texture`.
destroy_render_texture :: proc(render_texture: Render_Texture) {
	// Recorded draw calls may still be waiting to draw into this render target, or sample it.
	_flush_if_batch_uses_render_target(render_texture.render_target)
	_flush_if_batch_uses_texture(render_texture.texture.handle)
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

		if s.current_render_target == rt.render_target {
			return
		}

		s.current_render_target = rt.render_target
		s.current_render_target_width = rt.texture.width
		s.current_render_target_height = rt.texture.height

		s.proj_matrix = make_default_projection(
			rt.texture.width,
			rt.texture.height,
			_camera_flip_y(),
		)

		_update_view_projection()
	} else {
		if s.current_render_target == RENDER_TARGET_NONE {
			return
		}

		s.current_render_target = RENDER_TARGET_NONE
		s.current_render_target_width = 0
		s.current_render_target_height = 0

		s.proj_matrix = make_default_projection(
			pf.get_screen_width(),
			pf.get_screen_height(),
			_camera_flip_y(),
		)

		_update_view_projection()
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

// Like `load_static_font_from_bytes` but reads a file from disk using a specified name.
//
// The second return value is `true` if the font was loaded correctly. It's optional to handle this
// error, it will also be logged. In case of failure, the returned `Font` will still be possible to
// use, but text drawn with it uses the default font.
load_static_font_from_file :: proc(
	filename: string,
	font_size: f32,
	codepoints: []rune = {},
	options: Font_Options = {},
) -> (Font, bool) #optional_ok {
	data, data_ok := read_entire_file(filename, s.frame_allocator)

	if !data_ok {
		log.errorf("Failed loading font %s", filename)
		return FONT_NONE, false
	}

	return load_static_font_from_bytes(data, font_size, codepoints, options)
}

// Load the TTF font contained in `data` and bake it into a texture. The characters in the texture
// will be of of the specified `font_size`. If you do not specify a list of `codepoints`, then this
// procedure defaults to using all codepoints between 32 to 127 (ASCII).
//
// The second return value is `true` if the font was loaded correctly. It's optional to handle this
// error, it will also be logged. In case of failure, the returned `Font` will still be possible to
// use, but text drawn with it uses the default font.
load_static_font_from_bytes :: proc(
	data: []byte,
	font_size: f32,
	codepoints: []rune = {},
	options: Font_Options = {},
) -> (Font, bool) #optional_ok {
	codepoints := codepoints
	font_info: stbtt.fontinfo
	font_offset := stbtt.GetFontOffsetForIndex(raw_data(data), 0)
	init_ok := stbtt.InitFont(&font_info, raw_data(data), font_offset)

	if !init_ok {
		log.error("Failed loading TTF/TTC font")
		return FONT_NONE, false
	}

	scale_factor := stbtt.ScaleForPixelHeight(&font_info, font_size)

	ascent, descent, line_gap: i32
	stbtt.GetFontVMetrics(&font_info, &ascent, &descent, &line_gap)

	default_codepoints: [95]rune

	if len(codepoints) == 0 {
		for &d, idx in default_codepoints {
			d = rune(idx + 32)
		}

		codepoints = default_codepoints[:]
	}

	glyph_ranges := make([dynamic]Font_Baked_Glyph_Range, s.frame_allocator)
	glyphs := make([dynamic]Font_Baked_Glyph, s.frame_allocator)

	for c in codepoints {
		idx := stbtt.FindGlyphIndex(&font_info, c)
		
		if idx > 0 {
			advance: i32
			stbtt.GetGlyphHMetrics(&font_info, idx, &advance, nil)

			append(&glyphs, Font_Baked_Glyph {
				value = c,
				index = int(idx),
				advance = f32(advance) * scale_factor,
			})
		}
	}

	slice.sort_by(
		glyphs[:],
		proc(i, j: Font_Baked_Glyph) -> bool {
			return i.value < j.value
		},
	)

	cur_glyph_range: Font_Baked_Glyph_Range

	for g, g_idx in glyphs {
		if g_idx == 0 {
			cur_glyph_range = {
				start = g.value,
				start_idx = g_idx,
			}
		} else if g.value != cur_glyph_range.end {
			append(&glyph_ranges, cur_glyph_range)
			cur_glyph_range = {
				start = g.value,
				start_idx = g_idx,
			}
		}

		cur_glyph_range.end = g.value + 1
	}

	append(&glyph_ranges, cur_glyph_range)

	Glyph_Image_Data :: struct {
		pixels: [^]byte,
		width: i32,
		height: i32,
	}

	glyphs_img_data := make([]Glyph_Image_Data, len(glyphs), s.frame_allocator)
	glyphs_pack_rects := make([]stbrp.Rect, len(glyphs), s.frame_allocator)

	for &g, g_idx in glyphs {
		x_off, y_off: i32
		w, h: i32

		pixels := stbtt.GetGlyphBitmap(
			&font_info,
			scale_factor,
			scale_factor,
			i32(g.index),
			&w,
			&h,
			&x_off,
			&y_off,
		)

		glyphs_img_data[g_idx] = {
			pixels = pixels,
			width = w,
			height = h,
		}

		g.offset = {
			f32(x_off),
			f32(y_off) + f32(ascent) * scale_factor,
		}

		glyphs_pack_rects[g_idx] = {
			// w & h are packed with 1 pixel padding, so we get 1 px spacing betwen characters.
			w = stbrp.Coord(w) + 1,
			h = stbrp.Coord(h) + 1,
		}
	}

	atlas_size := 128
	MAX_ATLAS_SIZE :: 4096
	atlas_packed := false

	for atlas_size <= MAX_ATLAS_SIZE {
		rp_ctx: stbrp.Context
		rp_nodes := make([]stbrp.Node, i32(atlas_size), s.frame_allocator)
		
		stbrp.init_target(
			&rp_ctx,
			i32(atlas_size),
			i32(atlas_size),
			raw_data(rp_nodes),
			i32(len(rp_nodes)),
		)
		
		rect_pack_res := stbrp.pack_rects(
			&rp_ctx,
			raw_data(glyphs_pack_rects),
			i32(len(glyphs_pack_rects)),
		)

		if rect_pack_res == 1 {
			atlas_packed = true
			break
		}

		atlas_size *= 2
	}

	if !atlas_packed {
		log.error("Failed packing font atlas")
		return {}, false
	}

	atlas := make([]Color, atlas_size*atlas_size, s.frame_allocator)

	if options.premultiply_alpha {
		for pr, pr_idx in glyphs_pack_rects {
			g := &glyphs[pr_idx]

			g.rect = {
				f32(pr.x),
				f32(pr.y),
				// w & h are packed with 1 pixel padding, so we get 1 px spacing betwen characters.
				f32(pr.w) - 1,
				f32(pr.h) - 1,
			}

			gimg := glyphs_img_data[pr_idx]

			for sx in 0..<gimg.width {
				for sy in 0..<gimg.height {
					dx := int(pr.x) + int(sx)
					dy := int(pr.y) + int(sy)

					assert(dx >= 0 && dx < atlas_size)
					assert(dy >= 0 && dy < atlas_size)

					alpha := gimg.pixels[sy * gimg.width + sx]
					alpha_norm := f32(alpha)/255

					atlas[dy * atlas_size + dx] = {
						u8(255 * alpha_norm),
						u8(255 * alpha_norm),
						u8(255 * alpha_norm),
						alpha,
					}
				}
			}
		}
	} else {
		for pr, pr_idx in glyphs_pack_rects {
			g := &glyphs[pr_idx]

			g.rect = {
				f32(pr.x),
				f32(pr.y),
				// w & h are packed with 1 pixel padding, so we get 1 px spacing betwen characters.
				f32(pr.w) - 1,
				f32(pr.h) - 1,
			}

			gimg := glyphs_img_data[pr_idx]

			for sx in 0..<gimg.width {
				for sy in 0..<gimg.height {
					dx := int(pr.x) + int(sx)
					dy := int(pr.y) + int(sy)

					assert(dx >= 0 && dx < atlas_size)
					assert(dy >= 0 && dy < atlas_size)

					alpha := gimg.pixels[sy * gimg.width + sx]

					atlas[dy * atlas_size + dx] = {
						255,
						255,
						255,
						alpha,
					}
				}
			}
		}
	}

	for gimg in glyphs_img_data {
		if gimg.pixels != nil {
			stbtt.FreeBitmap(gimg.pixels, nil)
		}
	}

	img := Image {
		pixels = atlas,
		width = atlas_size,
		height = atlas_size,
	}

	tex := load_texture_from_image(img)
	set_texture_filter(tex, options.filter)

	font := Font_Data {
		atlas = tex,
		type = .Static,
		options = options,
		static_glyphs = slice.clone(glyphs[:], s.allocator),
		static_glyph_ranges = slice.clone(glyph_ranges[:], s.allocator),
		static_font_size = font_size,

		// Fomula from stbtt.GetFontVMetrics docs 
		static_line_spacing = f32(ascent - descent + line_gap) * scale_factor,
	}

	font_handle := Font(len(s.fonts))
	append(&s.fonts, font)
	return font_handle, true
}

// Like `load_dynamic_font_from_bytes`, but reads a file from disk using a filename.
//
// The second return value is `true` if the font was loaded correctly. It's optional to handle this
// error, it will also be logged. In case of failure, the returned `Font` will still be possible to
// use, but text drawn with it uses the default font.
load_dynamic_font_from_file :: proc(
	filename: string,
	options: Font_Options = {},
) -> (Font, bool) #optional_ok {
	data, data_ok := read_entire_file(filename, s.frame_allocator)

	if !data_ok {
		log.errorf("Failed loading font %s", filename)
		return FONT_NONE, false
	}

	return load_dynamic_font_from_bytes(data, options)
}

// Load a TTF font stored in `data` as a dynamic font. This means that an atlas will be dynamically
// built as you draw characters using this font.
//
// The second return value is `true` if the font was loaded correctly. It's optional to handle this
// error, it will also be logged. In case of failure, the returned `Font` will still be possible to
// use, but text drawn with it uses the default font.
load_dynamic_font_from_bytes :: proc(
	data: []u8,
	options: Font_Options = {},
) -> (Font, bool) #optional_ok {
	font_info: stbtt.fontinfo
	font_offset := stbtt.GetFontOffsetForIndex(raw_data(data), 0)
	init_ok := stbtt.InitFont(&font_info, raw_data(data), font_offset)

	if !init_ok {
		log.error("Failed loading TTF/TTC font")
		return FONT_NONE, false
	}

	fontstash_handle := fs.AddFontMem(&s.fs, "", slice.clone(data, s.allocator), false)
	h := Font(len(s.fonts))

	atlas_texture, atlas_texture_ok := rb.create_texture(
		FONT_DEFAULT_ATLAS_SIZE,
		FONT_DEFAULT_ATLAS_SIZE,
		.RGBA_8_Norm,
	)

	if !atlas_texture_ok {
		return FONT_NONE, false
	}

	data := Font_Data {
		dynamic_fontstash_handle = fontstash_handle,
		atlas = {
			handle = atlas_texture,
			width = FONT_DEFAULT_ATLAS_SIZE,
			height = FONT_DEFAULT_ATLAS_SIZE,
		},
		type = .Dynamic,
		options = options,
	}

	set_texture_filter(data.atlas, options.filter)
	append(&s.fonts, data)
	return h, true
}

@(deprecated="Use load_dynamic_font_from_file or load_static_font_from_file.")
load_font_from_file :: proc(
	filename: string,
	options: Font_Options = {},
) -> (Font, bool) #optional_ok {
	return load_dynamic_font_from_file(filename, options)
}

@(deprecated="Use load_dynamic_font_from_bytes or load_static_font_from_bytes")
load_font_from_bytes :: proc(data: []u8, options: Font_Options = {}) -> (Font, bool) #optional_ok {
	return load_dynamic_font_from_bytes(data, options)
}

// Destroy a font previously loaded using `load_font_from_file` or `load_font_from_bytes`.
destroy_font :: proc(font: Font) {
	if int(font) >= len(s.fonts) {
		return
	}

	f := &s.fonts[font]

	// Recorded draw calls may still be waiting to sample this font's atlas.
	_flush_if_batch_uses_texture(f.atlas.handle)
	rb.destroy_texture(f.atlas.handle)

	// So `_update_font_atlases` stops uploading glyphs to a texture that is gone.
	f.atlas = {}

	switch f.type {
	case .Static:
		delete(f.static_glyphs, s.allocator)
		delete(f.static_glyph_ranges, s.allocator)
	case .Dynamic:
		// TODO fontstash has no "destroy font" proc... I should make my own version of fontstash
		delete(s.fs.fonts[f.dynamic_fontstash_handle].glyphs)
		delete(s.fs.fonts[f.dynamic_fontstash_handle].loadedData, s.allocator)
		s.fs.fonts[f.dynamic_fontstash_handle].glyphs = {}
	}

}

@(deprecated="Use FONT_DEFAULT constant instead")
get_default_font :: proc() -> Font {
	return FONT_DEFAULT
}

//---------//
// CURSORS //
//---------//

// Sets the cursor, either to one the operating system provides or to one made with
// `create_custom_cursor`. `set_cursor(.Default)` goes back to the normal OS cursor.
set_cursor :: proc(cursor: Cursor) {
	pf.set_cursor(cursor)
}

// Create a cursor from an image. `hotspot` is the position within the image that points at things,
// in physical pixels.
//
// The cursor does not need `image` after it is created. You may destroy it.
//
// The second return value is `true` if the cursor was created correctly. It's optional to handle
// this error, it will also be logged. In case of failure, the returned `Custom_Cursor` will still
// be possible to use, but setting it leaves the cursor as it is.
create_custom_cursor :: proc(image: Image, hotspot: [2]int) -> (Custom_Cursor, bool) #optional_ok {
	if image.width == 0 || image.height == 0 {
		log.error("Invalid cursor image: height or width is zero")
		return {}, false
	}

	if len(image.pixels) != image.width*image.height {
		log.error("Invalid cursor image: the pixels array is not of size image.width*image.height")
		return {}, false
	}

	cursor, cursor_ok := pf.create_custom_cursor(image, hotspot)

	if !cursor_ok {
		return {}, false
	}

	return cursor, true
}

// Destroy a cursor previously created using `create_custom_cursor`. If it is the cursor currently
// on screen then Karl2D will restore the default OS cursor.
destroy_custom_cursor :: proc(custom_cursor: Custom_Cursor) {
	pf.destroy_custom_cursor(custom_cursor)
}

// Hide or show the mouse cursor. The cursor may get shown again if the window loses focus.
// Therefore, it's often best to use `is_cursor_hidden` to check the current status and use this
// procedure to hide the cursor as needed.
//
// This call does not lock the mouse within the window, do that using a separate call to
// `set_mouse_locked`.
set_cursor_hidden :: proc(hidden: bool) {
	pf.set_cursor_hidden(hidden)
}

// Returns true if the cursor is hidden. The cursor may get re-shown by the OS, for example when the
// window loses focus. Therefore, this procedure may return false even though you've hidden the
// cursor previously. It should always reflect the true hide-state of the cursor.
is_cursor_hidden :: proc() -> bool {
	return pf.is_cursor_hidden()
}

//---------//
// SHADERS //
//---------//

// Load a shader from a vertex and fragment shader file. If the vertex and fragment shaders live in
// the same file, then pass it twice.
//
// `layout_formats` can in many cases be left default initialized. It is used to specify the format
// of the vertex shader inputs. By formats this means the format that you pass on the CPU side.
//
// The second return value is `true` if the shader was loaded correctly. It's optional to handle
// this error, it will also be logged. In case of failure, the returned `Shader` will still be
// possible to use, but setting it does nothing: drawing carries on with the shader already set.
load_shader_from_file :: proc(
	vertex_filename: string,
	fragment_filename: string,
	layout_formats: []Pixel_Format = {}
) -> (Shader, bool) #optional_ok {
	vertex_source, vertex_source_ok := read_entire_file(vertex_filename, frame_allocator)

	if !vertex_source_ok {
		log.errorf("Failed loading shader %s", vertex_filename)
		return {}, false
	}

	fragment_source: []byte
	
	if fragment_filename == vertex_filename {
		fragment_source = vertex_source
	} else {
		fragment_source_ok: bool
		fragment_source, fragment_source_ok = read_entire_file(fragment_filename, frame_allocator)

		if !fragment_source_ok {
			log.errorf("Failed loading shader %s", fragment_filename)
			return {}, false
		}
	}

	return load_shader_from_bytes(vertex_source, fragment_source, layout_formats)
}

// Load a vertex and fragment shader from a block of memory. See `load_shader_from_file` for what
// `layout_formats` means.
//
// The second return value is `true` if the shader was loaded correctly. It's optional to handle
// this error, it will also be logged. In case of failure, the returned `Shader` will still be
// possible to use, but setting it does nothing: drawing carries on with the shader already set.
load_shader_from_bytes :: proc(
	vertex_shader_bytes: []byte,
	fragment_shader_bytes: []byte,
	layout_formats: []Pixel_Format = {},
) -> (Shader, bool) #optional_ok {
	handle, desc, shader_ok := rb.load_shader(
		vertex_shader_bytes,
		fragment_shader_bytes,
		s.frame_allocator,
		layout_formats,
	)

	if !shader_ok {
		return {}, false
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
	return shd, true
}

// Destroy a shader previously loaded using `load_shader_from_file` or `load_shader_from_bytes`
destroy_shader :: proc(shader: Shader) {
	// Recorded draw calls may still be waiting to draw with this shader.
	_flush_if_batch_uses_shader(shader.handle)
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
		if shd.handle == SHADER_NONE {
			log.error("Cannot set shader, shader does not exist.")
			return
		}

		if shd.handle == s.current_shader.handle {
			return
		}
	} else {
		if s.current_shader.handle == s.default_shader.handle {
			return
		}
	}

	s.current_shader = shader.? or_else s.default_shader
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

	// Draw calls recorded before this point keep the old value. The next one takes a fresh copy.
	s.current_constants_dirty = true
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
	if camera == s.current_camera {
		return
	}

	s.current_camera = camera

	if c, c_ok := camera.?; c_ok {
		s.view_matrix = camera_view_matrix(c)
	} else {
		s.view_matrix = 1
	}

	// The Y axis picks which edge of the surface Y = 0 sits on. So the projection depends on the
	// camera, not just on the surface size.
	if s.current_render_target == RENDER_TARGET_NONE {
		s.proj_matrix = make_default_projection(
			pf.get_screen_width(),
			pf.get_screen_height(),
			_camera_flip_y(),
		)
	} else {
		s.proj_matrix = make_default_projection(
			s.current_render_target_width,
			s.current_render_target_height,
			_camera_flip_y(),
		)
	}

	_update_view_projection()
}

// Transform a point `pos` that lives on the screen into the camera's coordinates.
//
// Example: Bringing the mouse position into the coordinate space of a camera:
//
//// world_mouse_pos := k2.screen_to_camera(k2.get_mouse_position(), world_camera)
screen_to_camera :: proc(pos: Vec2, camera: Camera) -> Vec2 {
	pos := pos

	// Screen Y counts down from the top. A flipped camera counts it from the bottom of the surface.
	if camera.flip_y {
		surface_height := s.current_render_target_height

		if s.current_render_target == RENDER_TARGET_NONE {
			surface_height = pf.get_screen_height()
		}

		pos.y = f32(surface_height) - pos.y
	}

	return (camera_inverse_view_matrix(camera) * Vec4 { pos.x, pos.y, 0, 1 }).xy
}

// Transform a point `pos` that lives in the camera's coordinates to a point on the screen. This can
// be useful when you need to compare such a position to a screen-space point.
camera_to_screen :: proc(pos: Vec2, camera: Camera) -> Vec2 {
	res := (camera_view_matrix(camera) * Vec4 { pos.x, pos.y, 0, 1 }).xy

	if camera.flip_y {
		surface_height := s.current_render_target_height

		if s.current_render_target == RENDER_TARGET_NONE {
			surface_height = pf.get_screen_height()
		}

		res.y = f32(surface_height) - res.y
	}

	return res
}

@(deprecated="Use screen_to_camera instead")
screen_to_world :: proc(pos: Vec2, camera: Camera) -> Vec2 {
	return screen_to_camera(pos, camera)
}

@(deprecated="Use camera_to_screen instead")
world_to_screen :: proc(pos: Vec2, camera: Camera) -> Vec2 {
	return camera_to_screen(pos, camera)
}

// Calculate the matrix that `screen_to_camera` and `camera_to_screen` uses to do transformations.
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
	// A zoom of 0 is what a zero-initialized camera has. Treat it as 1 so such a camera draws at
	// normal scale instead of collapsing everything to nothing.
	zoom := c.zoom == 0 ? 1 : c.zoom

	inv_target_translate := linalg.matrix4_translate(vec3_from_vec2(-c.target))
	inv_rot := linalg.matrix4_rotate_f32(c.rotation, {0, 0, 1})
	inv_scale := linalg.matrix4_scale(Vec3{zoom, zoom, 1})
	inv_offset_translate := linalg.matrix4_translate(vec3_from_vec2(c.offset))

	return inv_offset_translate * inv_scale * inv_rot * inv_target_translate
}

// The inverse of `camera_view_matrix`. It undoes the camera instead of applying it.
camera_inverse_view_matrix :: proc(c: Camera) -> Mat4 {
	// As in `camera_view_matrix`: a zoom of 0 is treated as 1. It also makes the division safe.
	zoom := c.zoom == 0 ? 1 : c.zoom

	offset_translate := linalg.matrix4_translate(vec3_from_vec2(-c.offset))
	rot := linalg.matrix4_rotate_f32(-c.rotation, {0, 0, 1})
	scale := linalg.matrix4_scale(Vec3{1/zoom, 1/zoom, 1})
	target_translate := linalg.matrix4_translate(vec3_from_vec2(c.target))

	return target_translate * rot * scale * offset_translate
}

@(deprecated="Use camera_inverse_view_matrix instead")
camera_world_matrix :: proc(c: Camera) -> Mat4 {
	return camera_inverse_view_matrix(c)
}

//------//
// MISC //
//------//

// Choose how the alpha channel is used when mixing half-transparent color with what is already
// drawn. The default is the .Alpha mode, but you also have the option of using .Premultiply_Alpha.
set_blend_mode :: proc(mode: Blend_Mode) {
	if s.current_blend_mode == mode {
		return
	}

	s.current_blend_mode = mode
}

// Make everything outside of the screen-space rectangle `scissor_rect` not render. Disable the
// scissor rectangle by running `set_scissor_rect(nil)`.
set_scissor_rect :: proc(scissor_rect: Maybe(Rect)) {
	s.current_scissor = scissor_rect
}

// Set the z used by draws that happen after this call. Only has an effect when `depth_test` was
// enabled in `Init_Options`. Higher z ends up in front. Unlike `set_blend_mode` and
// `set_scissor_rect`, this never starts a new draw call: the z is stored in each vertex rather
// than being part of a draw call's settings, so it's fine to call this before every draw.
set_z :: proc(z: f32) {
	s.z = z
}

// Get the z previously set with `set_z`. Defaults to 0.
get_z :: proc() -> f32 {
	return s.z
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

//--------------//
// EXPERIMENTAL //
//--------------//
//
// These procedures are experimental and may not stay.

// The witdth a button drawn using `ui_button` will have
ui_button_width :: proc(text: string, button_height: f32) -> f32 {
	return measure_text(text, button_height).x
}

// Experimental UI button. Returns true if the button was pressed. Currently only works properly
// when no camera is set.
//
// Mainly used by the samples in order to create the "Source" button.
//
// Note that this does not support zoomed cameras right now, since it uses unscaled mouse positions.
// As this is experimental, you are probably better off copying this procedure to your own code and
// modifying it, rather than using it as-is.
ui_button :: proc(r: Rect, text: string) -> bool {
	in_rect := point_in_rect(get_mouse_position(), r)
	bg_color := DARK_GRAY
	border_color := WHITE
	text_color := WHITE
	res := false

	if in_rect {
		bg_color = GRAY
		text_color = WHITE

		if mouse_button_went_down(.Left) {
			res = true
			bg_color = BLACK
		}
	}
	
	draw_rect(r, bg_color)
	draw_rect_outline(r, 1, border_color)

	text_width := measure_text(text, r.h).x
	draw_text(text, {r.x + r.w/2 - text_width/2, r.y}, r.h, WHITE)
	return res
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

// An image kept in RAM, you can fill this out and pass it to `load_texture_from_image` in order
// to transport it to the GPU.
Image :: struct {
	pixels: []Color,
	width: int,
	height: int,
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

	// Zoom the camera. A bigger value means "more zoom". A zoom of 0 is treated as 1, so a camera
	// without a zoom set draws at normal scale.
	//
	// To make a certain amount of pixels always occupy the height of the camera, set the zoom to:
	//
	//     k2.get_screen_height()/wanted_pixel_height
	zoom: f32,

	// Flips the Y axis. The origin becomes the bottom-left of the screen, Y grows upwards and the
	// direction of rotation is reversed. This is useful as a "world camera" when using libraries
	// such as Box2D. That way, you don't have to make any extra conversions between you gameplay /
	// physics code and Karl2D.
	//
	// When `flip_y` is true:
	// - A `Rect` will have its `(x, y)` in the bottom-left corner, rather than top-left.
	// - Textures will be drawn with their bottom-left corner as position, rather than top-left.
	// - Blocks of text will have their origin in the bottom-left corner of the block, rather than
	//   top-left.
	//
	// Caveats:
	// - The `rect_top_*`, `rect_bottom*` and `cut_rect_*` procs still assume that (x, y) is the
	//   top-left corner. But those procs are often use for UIs and screen-space things. An idea is
	//   to only use `flip_y` for the world camera. Let the UI use either no camera or a non-flipped
	//   camera.
	flip_y: bool,
}

Window_Mode :: enum {
	Windowed,
	Windowed_Resizable,
	Borderless_Fullscreen,
}

Init_Options :: struct {
	window_mode: Window_Mode,

	// Enable to request anti-alias. On most systems this means 4x Multi Sample Anti Alias
	anti_alias: bool,

	// This hint may disable scaling of the window when created. Scaling here refers to the scaling
	// that is set for the monitor in the OS settings (the same number returned by
	// `get_window_scale`).
	//
	// Note that this is a _hint_. It only works on some platforms, such as Windows. On other
	// platforms, such as Linux+Wayland, it does not work, because Wayland always auto scales all
	// windows.
	disable_auto_scale_hint: bool,

	// Enable depth testing. Draws are then sorted by the z value set with `set_z`: higher z ends up
	// in front. Things drawn at the same z use the drawing order, like when depth testing is off.
	depth_test: bool,

	// The range of z values you can use with `set_z`. Leave both at zero to get the default range
	// of -1 to 1. Set them to something like 0 and 1000 if you'd rather feed `set_z` world
	// coordinates. Only used when `depth_test` is on.
	depth_range_min: f32,
	depth_range_max: f32,
}

DEPTH_RANGE_DEFAULT_MIN :: -1
DEPTH_RANGE_DEFAULT_MAX :: 1

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

// Supported font types:
// - Static: A pre-baked font where you specify a range of characters that are baked into a texture.
// - Dynamic: A font where an atlas is continuously updated as you need need new characters. This
//            mode current uses fontstash.
//
// Future types (TODO):
// - Slug: Upload the character bezier curves to the GPU and render the text on the GPU without the
//         need for any atlas texture. This will be based on the "slug font algorithm" that was
//         recently put into public domain.
Font_Type :: enum {
	Static,
	Dynamic,
}

Font_Data :: struct {
	atlas: Texture,
	options: Font_Options,

	type: Font_Type,

	// type == .Static
	static_glyphs: []Font_Baked_Glyph,
	static_glyph_ranges: []Font_Baked_Glyph_Range,
	static_font_size: f32,
	static_line_spacing: f32,

	// type == .Dynamic
	dynamic_fontstash_handle: int,
}

Handle :: hm.Handle64
Texture_Handle :: distinct Handle
Render_Target_Handle :: distinct Handle
Font :: distinct int
DEFAULT_FONT_DATA :: #load("default_fonts/roboto.ttf")
// The cursors an operating system provides out of the box. Use with `set_cursor`.
//
// Not every platform has every one of them. Where one is missing, the closest thing is used
// instead:
// - macOS has no public busy cursor, so `Wait` and `Progress` show the default arrow, and no
//   public diagonal resize cursors, so `Resize_NESW` and `Resize_NWSE` do too.
// - On Linux these come from the user's cursor theme. A theme missing one of them falls back to
//   whatever the window would otherwise inherit, usually the default arrow.
Standard_Cursor :: enum {
	Default,
	Text,
	Hand,
	Crosshair,
	Wait,
	Progress,
	Resize_EW,
	Resize_NS,
	Resize_NESW,
	Resize_NWSE,
	Move,
	Not_Allowed,
}

// A cursor made from your own image, created with `create_custom_cursor`.
Custom_Cursor :: distinct Handle

CUSTOM_CURSOR_NONE :: Custom_Cursor{}

// The cursor to show: either one the OS provides or one you made. Never both, which is why this
// is a union. The zero value is `Standard_Cursor.Default`.
Cursor :: union #no_nil {
	Standard_Cursor,
	Custom_Cursor,
}

Font_Baked_Glyph_Range :: struct {
	start_idx: int,
	start: rune,
	end: rune,
}

Font_Baked_Glyph :: struct {
	value: rune,
	// stbtt index, for faster lookup
	index: int,
	rect: Rect,
	offset: Vec2,
	advance: f32,
}

FONT_NONE :: Font(0)

// The default font. It's a font called "roboto". It is loaded from `DEFAULT_FONT_DATA` on Karl2D is
// initialized.
FONT_DEFAULT :: Font(1) 

TEXTURE_NONE :: Texture_Handle {}
RENDER_TARGET_NONE :: Render_Target_Handle {}

AUDIO_MIX_SAMPLE_RATE :: 44100
AUDIO_MIX_CHUNK_SIZE :: 1400

// Single channel audio sample. Can have a value between -1 and 1. For stereo sound every other
// sample in an array of samples will be interpreted as left and right respectively.
Audio_Sample :: f32

// Represents something that is currently playing in the audio mixer. Created using
// `play_audio_clip` and `play_audio_stream`. A sound is automatically destroyed when it finishes
// playing. It is safe to keep using the handle after that: The procedures that take a `Sound` will
// then just do nothing.
Sound :: distinct Handle

SOUND_NONE :: Sound {}

// Plays an ogg file by decoding it a little bit at a time, instead of loading all of the audio
// data up front like an `Audio_Clip` does. Good for music, which would otherwise use a lot of
// memory. Start it using `play_audio_stream`.
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

// From stb_vorbis.odin "In my test files the maximal-size usage is ~150KB.)"
VORBIS_STATE_SIZE :: 300 * mem.Kilobyte

Audio_Stream_Data :: struct {
	handle: Audio_Stream,
	
	vorbis: ^stbv.vorbis,
	vorbis_buffer: stbv.vorbis_alloc,
	sound: Sound,
	clip: Audio_Clip,

	// Where in the audio clip referred to by `clip` that we have most recently written samples.
	// Together with the `offset` of the Sound_Object, this forms a circular buffer.
	buffer_write_pos: int,

	// How far into the file the samples we most recently wrote into the clip were, counted the
	// same way as the clip's samples: In the case of stereo, left and right count as one each.
	// Take away the samples in the clip that haven't played yet and you get the spot the listener
	// is hearing, which is what `get_sound_time` does.
	decode_cursor: int,

	// When above zero, `update_audio_stream` throws this many decoded samples away instead of
	// writing them to the clip. Used when moving the stream, since the decoder can only move in
	// steps of a whole ogg page.
	seek_discard: int,

	// How many samples the whole file has, counted the same way as `decode_cursor`. Worked out
	// when the stream is loaded. Zero if it could not be worked out.
	total_samples: int,

	// Different from `loop` in `Sound_Object`. This says if the whole stream should loop
	// when it reaches end-of-file. The `loop` in `Sound_Object` just says to loop the
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

// The format used to describe that data passed to `load_audio_clip_from_bytes_raw`.
Raw_Audio_Format :: enum {
	Integer8, // unsigned, like in 8 bit WAV files. The other integer formats are signed.
	Integer16,
	Integer24, // three bytes per sample, little endian
	Integer32,
	Float32,
	Float64,
}

// A piece of audio that has been completely loaded into memory. Play it using `play_audio_clip`.
// Several sounds can play the same clip at the same time.
Audio_Clip :: distinct Handle

AUDIO_CLIP_NONE :: Audio_Clip{}

Audio_Clip_Object :: struct {
	handle: Audio_Clip,

	// All the samples of the audio clip. In the case of stereo, the left and right samples are
	// interleaved.
	samples: []Audio_Sample,

	// The number of samples per second. Note that the mixer uses 44100 samples per second (as
	// defined by AUDIO_MIX_SAMPLE_RATE). When the sample rate of the buffer and the mixer do no
	// match, then interpolation will happen during mixing.
	sample_rate: int,

	// If this is Stereo, then the left and right samples are interleaved in `samples`.
	channels: Audio_Channels,
}

Sound_Settings :: struct {
	volume: f32,
	pan: f32,
	pitch: f32,
}

// What `Sound` handles are mapped to: something that is currently playing in the mixer. It holds
// the clip it plays and the settings it plays with.
Sound_Object :: struct {
	handle: Sound,
	clip: Audio_Clip,
	target_settings: Sound_Settings,
	current_settings: Sound_Settings,

	// How many samples have played?
	offset: int,

	// Only used when playing sounds that have pitch != 1 or when the sound has a sample rate that
	// does not match the mixer's sample rate. In those cases we may get "fractional samples"
	// because we may be in samples that are inbetween two samples in the original sound.
	offset_fraction: f32,

	loop: bool,

	// Set using `set_sound_paused`. The mixer skips paused sounds.
	paused: bool,

	// `set_sound_time` doesn't move the sound straight away. The mixer fades it out first, then
	// moves it, then fades it back in, so that landing in a completely different part of the
	// waveform doesn't click. This is where it is going once the fade out is done.
	pending_seek_seconds: f32,
	has_pending_seek: bool,

	// The fade used when moving a sound: 0 is no fade and 1 is completely faded out. The mixer
	// raises it while a move is pending and lowers it again once the move is done.
	seek_fade: f32,

	// The bus this is mixed into. The zero value is the master bus.
	bus: Audio_Bus,

	// Set when this sound plays an audio stream. Zero for sounds played from a clip. Used by
	// `set_sound_loop` to redirect to the stream's own loop flag.
	stream: Audio_Stream,
}

// A bus is a group of sounds that are mixed together before they reach the master bus. You can set
// the volume and the pan of the whole group, and you can run an effect on it. Create one using
// `create_audio_bus` and route sounds into it using `set_sound_bus`, or the `bus` parameter of
// `play_audio_clip` or `play_audio_stream`.
Audio_Bus :: distinct Handle

// All other buses are mixed into the master bus, as well as sounds that play directly on the master
// bus. This is the default bus of all sounds.
//
// You can use this with `set_audio_bus_volume`, `set_audio_bus_pan` and `set_audio_bus_effect`.
// That's how you set the master volume of your game.
AUDIO_BUS_MASTER :: Audio_Bus {}

// Runs on the mixed samples of a whole bus, before the bus is mixed into the master bus. Modify
// `samples` in place. This is how you write your own audio effects, such as a filter or an echo.
//
// `samples` is `AUDIO_MIX_CHUNK_SIZE` stereo samples at `AUDIO_MIX_SAMPLE_RATE`. Keep any state
// your effect needs in `user_data`: You get called once per mixed chunk, so anything you want to
// carry between the chunks needs to live there.
//
// This runs on the main thread today, but keep in mind that it may move to a separate thread in the
// future.
Audio_Effect_Proc :: proc(samples: [][2]Audio_Sample, user_data: rawptr)

Audio_Bus_Settings :: struct {
	volume: f32,
	pan: f32,
}

Audio_Bus_Object :: struct {
	handle: Audio_Bus,

	// Same idea as in `Sound_Object`: The current settings move towards the target
	// settings a bit at a time, so that changing the volume of a bus doesn't click.
	target_settings: Audio_Bus_Settings,
	current_settings: Audio_Bus_Settings,

	effect: Audio_Effect_Proc,
	effect_user_data: rawptr,

	// The sounds routed to this bus are mixed in here. The bus effect runs on this. Then this is
	// mixed into the master bus. Unused for the master bus itself: That one is mixed straight into
	// `mix_buffer`.
	chunk: [AUDIO_MIX_CHUNK_SIZE][2]Audio_Sample,
}

DEFAULT_AUDIO_BUS_SETTINGS :: Audio_Bus_Settings {
	volume = 1,
	pan = 0,
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

	typed_runes: [dynamic]rune,

	mouse_position: Vec2,
	mouse_delta: Vec2,
	mouse_wheel_delta: f32,
	mouse_wheel_delta_horizontal: f32,

	key_went_down: #sparse [Keyboard_Key]bool,
	key_went_up: #sparse [Keyboard_Key]bool,
	key_is_held: #sparse [Keyboard_Key]bool,
	key_repeat: #sparse [Keyboard_Key]bool,

	mouse_button_went_down: #sparse [Mouse_Button]bool,
	mouse_button_went_up: #sparse [Mouse_Button]bool,
	mouse_button_is_held: #sparse [Mouse_Button]bool,

	gamepad_button_went_down: [MAX_GAMEPADS]#sparse [Gamepad_Button]bool,
	gamepad_button_went_up: [MAX_GAMEPADS]#sparse [Gamepad_Button]bool,
	gamepad_button_is_held: [MAX_GAMEPADS]#sparse [Gamepad_Button]bool,

	// Also see FONT_NONE and FONT_DEFAULT
	fonts: [dynamic]Font_Data,
	shape_drawing_texture: Texture_Handle,
	// The settings the next draw call will be recorded with. Changing one of these does not affect
	// draw calls that are already recorded.
	current_font: Font,
	current_camera: Maybe(Camera),
	current_shader: Shader,
	current_scissor: Maybe(Rect),
	current_texture: Texture_Handle,
	current_render_target: Render_Target_Handle,

	// Size of `current_render_target`, or 0 when drawing to the window. Needed to build the
	// projection, and to measure Y up from the bottom of it, without asking the backend.
	current_render_target_width: int,
	current_render_target_height: int,
	current_blend_mode: Blend_Mode,

	// Recorded but not drawn yet. They all point into `vertex_buffer_cpu`.
	batch_draw_calls: [dynamic]Draw_Call,

	// The one vertices go into right now. A zeroed one means there is none.
	current_draw_call: Draw_Call,

	// Holds the constant values and textures that the draw calls point at.
	batch_arena: runtime.Arena,
	batch_allocator: runtime.Allocator,

	// Says that the shader constants may differ from what the open draw call captured.
	current_constants_dirty: bool,

	view_matrix: Mat4,
	proj_matrix: Mat4,

	// `proj_matrix * view_matrix`. Kept around because every draw call needs it. Update it with
	// `_update_view_projection`.
	view_projection: Mat4,

	z: f32,
	depth_test: bool,
	depth_range_min: f32,
	depth_range_max: f32,

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

	audio_clips: hm.Dynamic_Handle_Map(Audio_Clip_Object, Audio_Clip),
	sounds: hm.Dynamic_Handle_Map(Sound_Object, Sound),

	audio_streams: hm.Dynamic_Handle_Map(Audio_Stream_Data, Audio_Stream),

	audio_buses: hm.Dynamic_Handle_Map(Audio_Bus_Object, Audio_Bus),

	// The master bus is not in `audio_buses`. It is identified by the zero handle, which the handle
	// map can't store, and it needs to exist without anyone creating it.
	master_bus: Audio_Bus_Object,

	// Mixer will never mix in more than 1.5 * AUDIO_MIX_CHUNK_SIZE. So 10 times the chunk size is
	// ample.
	mix_buffer: [AUDIO_MIX_CHUNK_SIZE*10][2]Audio_Sample,

	// Where the mixer currently is in the mix buffer.
	mix_buffer_offset: int,
}


// Karl2D currently reports left, right, and middle mouse buttons.
// `Max` defines the upper bound of the `Mouse_Button` enum.
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
	Event_Key_Repeat,
	Event_Typed_Rune,
	Event_Mouse_Move,
	Event_Mouse_Wheel,
	Event_Mouse_Wheel_Horizontal,
	Event_Mouse_Button_Went_Down,
	Event_Mouse_Button_Went_Up,
	Event_Mouse_Teleported,
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

// A key is being held down and the OS is auto-repeating it. Sent in addition to (not instead of)
// the initial `Event_Key_Went_Down`.
Event_Key_Repeat :: struct {
	key: Keyboard_Key,
}

// A Unicode code point was typed, taking the current keyboard layout into account. Use this for
// text input. See `get_typed_runes`.
Event_Typed_Rune :: struct {
	typed: rune,
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

// Used by mouse capturing to inform us that the cursor was teleported. This is like a mouse move,
// but will not be used for calculating mouse delta movement.
Event_Mouse_Teleported :: struct {
	position: Vec2,
}

Event_Mouse_Move :: struct {
	position: Vec2,
}

// The vertical mouse wheel scrolled. `delta` is positive when scrolling up.
Event_Mouse_Wheel :: struct {
	delta: f32,
}

// The horizontal mouse wheel scrolled. `delta` is positive when scrolling right. A tilt wheel or a
// two-finger sideways swipe on a trackpad drives this one.
Event_Mouse_Wheel_Horizontal :: struct {
	delta: f32,
}

// Reports the new size of the drawable game area
Event_Screen_Resize :: struct {
	width, height: int,
}

// You can also use `k2.get_window_scale()`
Event_Window_Scale_Changed :: struct {
	scale: f32,
	screen_width: int,
	screen_height: int,
}

Event_Window_Focused :: struct {}

Event_Window_Unfocused :: struct {}


// Used by API builder. Everything after this constant will not be in karl2d.doc.odin
API_END :: true

// Returns true if `r` should be treated as a typed character for text input purposes. Filters out
// control characters such as Backspace, Enter, Tab, Escape and Delete. Used by the platform
// backends when producing `Event_Typed_Rune` events.
@(private="package")
is_typable_rune :: proc(r: rune) -> bool {
	return r >= 32 && r != 0x7f
}

// The number of lines `text` occupies. Used to size the text block without having to measure the
// whole thing: only the height matters for placing the block.
@(private="file", require_results)
count_text_lines :: proc "contextless" (text: string) -> int {
	lines := 1

	for c in text {
		if c == '\n' {
			lines += 1
		}
	}

	return lines
}

assert_initialized :: proc(loc := #caller_location) {
	assert(s != nil, "Call k2.init before using this Karl2D procedure", loc)
}

// Moves the decoder of a stream that reads from a file to `target_frame`, or to a little before
// it. Returns the frame it landed on, or -1 if it could not get there.
//
// We can't ask the decoder to jump, because it only ever sees the small pieces of the file we hand
// it. But we can seek the file ourselves and tell the decoder to resynchronize: It then looks for
// an ogg page it trusts, and once it has decoded a frame it can say how far into the audio that
// page was.
//
// So we look for the right spot in the file. We keep two known points, one before the wanted spot
// and one after it, and narrow the gap between them. The first couple of tries assume the bytes
// are spread evenly over the audio, which lands close on most files. A file that spends very
// different numbers of bytes on different parts of the audio ruins that assumption, so after that
// we cut the remaining range in half instead, which always gets there.
//
// Landing a little before the wanted spot is fine: `update_audio_stream` decodes the bit in
// between and throws it away, which is quick. Landing after it is no good at all.
_seek_file_stream :: proc(sd: ^Audio_Stream_Data, target_frame: int) -> int {
	ab := hm.get(&s.audio_clips, sd.clip)

	if ab == nil || sd.total_samples <= 0 {
		return -1
	}

	channels := 1
	if ab.channels == .Stereo {
		channels = 2
	}

	total_frames := sd.total_samples / channels

	if total_frames <= 0 {
		return -1
	}

	file_size, file_size_err := file_seek(sd.file, 0, .End)

	if file_size_err != nil || file_size <= 0 {
		return -1
	}

	// Seeks the file to `offset` and lets the decoder find a page from there. Returns the frame the
	// decoder ends up at, or -1 if no page turned up.
	resync_at :: proc(sd: ^Audio_Stream_Data, offset: i64) -> int {
		// Ogg pages are usually 4 to 8 kilobytes, so reading this much normally turns up a page
		// right away.
		READ_SIZE :: 8192

		// A page should turn up long before this many reads. This is here so that a file that is
		// not what we think it is cannot spin forever.
		MAX_READS :: 64

		if _, seek_err := file_seek(sd.file, offset, .Start); seek_err != nil {
			return -1
		}

		runtime.clear(&sd.file_read_buf)
		sd.file_read_buf_offset = 0
		stbv.flush_pushdata(sd.vorbis)

		for _ in 0..<MAX_READS {
			decoded_channels: i32
			samples: i32
			output: [^]^f32

			bytes_used := stbv.decode_frame_pushdata(
				sd.vorbis,
				raw_data(sd.file_read_buf[sd.file_read_buf_offset:]),
				i32(len(sd.file_read_buf) - sd.file_read_buf_offset),
				&decoded_channels,
				&output,
				&samples,
			)

			sd.file_read_buf_offset += int(bytes_used)

			if samples > 0 {
				// The decoder has found a page and decoded a frame from it, so it can now say
				// where in the audio the next frame starts.
				return int(stbv.get_sample_offset(sd.vorbis))
			}

			if bytes_used == 0 {
				read_buf_size := len(sd.file_read_buf)
				non_zero_resize(&sd.file_read_buf, read_buf_size + READ_SIZE)
				read, read_err := file_read(
					sd.file,
					sd.file_read_buf[read_buf_size:read_buf_size + READ_SIZE],
				)

				if read > 0 {
					shrink(&sd.file_read_buf, read_buf_size + read)
				}

				if read <= 0 || read_err != nil {
					return -1
				}
			}
		}

		return -1
	}

	// Landing this far before the wanted spot is close enough to stop looking.
	close_enough := 2 * ab.sample_rate

	// Once the two known points are this close together there is nothing to gain by narrowing
	// further: What is left decodes in well under a millisecond.
	SMALL_RANGE :: 64 * 1024

	// Cutting the range in half each time gets anywhere in a file of any size we might see well
	// inside this many tries.
	MAX_TRIES :: 40

	// The two points we know: The audio at `lo_byte` starts at `lo_frame`, and the same for `hi`.
	lo_byte, hi_byte := i64(0), file_size
	lo_frame, hi_frame := 0, total_frames

	// The best spot found so far, and where in the file it was.
	best_frame := -1
	best_byte := i64(0)

	// Where in the file the decoder was left by the most recent try.
	decoder_byte := i64(-1)

	for try in 0..<MAX_TRIES {
		if hi_byte - lo_byte <= SMALL_RANGE {
			break
		}

		guess: i64

		if try < 2 && hi_frame > lo_frame {
			// Assume the bytes are spread evenly over the audio between the two known points.
			aim := clamp(target_frame - close_enough/2, lo_frame, hi_frame)
			span := f64(hi_byte - lo_byte)
			part := f64(aim - lo_frame) / f64(hi_frame - lo_frame)
			guess = lo_byte + i64(span * part)
		} else {
			guess = lo_byte + (hi_byte - lo_byte)/2
		}

		guess = clamp(guess, lo_byte, hi_byte)
		landed := resync_at(sd, guess)
		decoder_byte = guess

		if landed < 0 {
			// No page turned up here, so there is nothing usable this far in. Look earlier.
			hi_byte = guess
			continue
		}

		if landed > target_frame {
			hi_byte = guess
			hi_frame = landed
			continue
		}

		lo_byte = guess
		lo_frame = landed

		if landed > best_frame {
			best_frame = landed
			best_byte = guess
		}

		if target_frame - landed <= close_enough {
			break
		}
	}

	if best_frame < 0 {
		return -1
	}

	// The last try usually is the best spot, since that is when we stop looking. If it isn't then
	// the decoder is somewhere else and has to be put back.
	if decoder_byte != best_byte && best_frame != resync_at(sd, best_byte) {
		return -1
	}

	// Move the bytes the decoder hasn't used yet to the start of the read buffer, the same way
	// `update_audio_stream` does, so that it carries on from here.
	if len(sd.file_read_buf) > 0 {
		copy(sd.file_read_buf[:], sd.file_read_buf[sd.file_read_buf_offset:])
		shrink(&sd.file_read_buf, len(sd.file_read_buf) - sd.file_read_buf_offset)
		sd.file_read_buf_offset = 0
	}

	return best_frame
}

// Works out how many audio frames an ogg file holds by looking at the last page in it.
//
// An ogg file is a sequence of pages. Each page starts with "OggS" and stores a granule position:
// The number of frames that have been decoded once that page has been played. The granule position
// of the last page is therefore the length of the whole file. We do it this way because the
// decoder cannot tell us the length of a file we feed to it a small piece at a time.
//
// The file position is restored before returning. Returns 0 if no length could be found.
_ogg_file_total_frames :: proc(f: ^File) -> int {
	// The biggest an ogg page can be. Reading this many bytes from the end of the file means we
	// are certain to see the start of the last page.
	MAX_OGG_PAGE_SIZE :: 65307

	// The smallest an ogg page header can be. Reading fewer bytes than this means there is no
	// page to find.
	MIN_OGG_PAGE_SIZE :: 27

	restore_pos, restore_pos_err := file_seek(f, 0, .Current)

	if restore_pos_err != nil {
		return 0
	}

	file_size, file_size_err := file_seek(f, 0, .End)

	if file_size_err != nil {
		return 0
	}

	read_size := min(int(file_size), MAX_OGG_PAGE_SIZE)

	if read_size < MIN_OGG_PAGE_SIZE {
		file_seek(f, restore_pos, .Start)
		return 0
	}

	if _, seek_err := file_seek(f, file_size - i64(read_size), .Start); seek_err != nil {
		file_seek(f, restore_pos, .Start)
		return 0
	}

	buf := make([]u8, read_size, frame_allocator)
	filled: int

	// A single read may hand back less than we asked for, so keep going until the buffer is full.
	for filled < read_size {
		read, read_err := file_read(f, buf[filled:])

		if read <= 0 || read_err != nil {
			break
		}

		filled += read
	}

	file_seek(f, restore_pos, .Start)

	if filled < MIN_OGG_PAGE_SIZE {
		return 0
	}

	buf = buf[:filled]

	// Walk backwards until we find a page that tells us where it ends.
	for idx := len(buf) - MIN_OGG_PAGE_SIZE; idx >= 0; idx -= 1 {
		if string(buf[idx:idx + 4]) != "OggS" {
			continue
		}

		granule, granule_ok := endian.get_u64(buf[idx + 6:idx + 14], .Little)

		if !granule_ok {
			continue
		}

		// All ones means that no packet finishes on this page, so it says nothing about the
		// length. Keep looking at earlier pages.
		if granule == max(u64) {
			continue
		}

		return int(granule)
	}

	return 0
}

// Moves a sound to another spot in its audio. Run by the mixer once the sound has faded out, and
// by `set_sound_time` directly for sounds that are paused.
_apply_sound_time :: proc(sound: Sound, seconds: f32) {
	sound_object := hm.get(&s.sounds, sound)

	if sound_object == nil {
		return
	}

	clamped_seconds := max(seconds, 0)

	if sound_object.stream == AUDIO_STREAM_NONE {
		clip := hm.get(&s.audio_clips, sound_object.clip)

		if clip == nil {
			return
		}

		channels := 1
		if clip.channels == .Stereo {
			channels = 2
		}

		total_frames := len(clip.samples) / channels
		target_frame := clamp(int(clamped_seconds * f32(clip.sample_rate)), 0, total_frames)

		sound_object.offset = target_frame * channels
		sound_object.offset_fraction = 0
		return
	}

	sd := hm.get(&s.audio_streams, sound_object.stream)

	if sd == nil {
		return
	}

	ab := hm.get(&s.audio_clips, sd.clip)

	if ab == nil {
		return
	}

	channels := 1
	if ab.channels == .Stereo {
		channels = 2
	}

	target_frame := int(clamped_seconds * f32(ab.sample_rate))

	// Don't go past the end of the audio when we know where that is.
	if sd.total_samples > 0 {
		target_frame = min(target_frame, sd.total_samples / channels)
	}

	switch sd.mode {
	case .From_Bytes:
		if stbv.seek(sd.vorbis, u32(target_frame)) == 0 {
			log.error("Cannot set sound position, seeking in the audio stream failed.")
			return
		}

		sd.decode_cursor = target_frame * channels
		sd.seek_discard = 0

	case .From_File:
		target := target_frame * channels

		// A short step forwards is cheapest to do by decoding the samples in between and throwing
		// them away, which is what `seek_discard` makes `update_audio_stream` do.
		if target >= sd.decode_cursor && target - sd.decode_cursor <= 2 * ab.sample_rate * channels {
			sd.seek_discard = target - sd.decode_cursor
			break
		}

		// Anything longer is done by seeking the file itself.
		if landed := _seek_file_stream(sd, target_frame); landed >= 0 {
			sd.decode_cursor = landed * channels
			sd.seek_discard = target - sd.decode_cursor
			break
		}

		// The file could not be searched, so go back to the start and decode from there.
		file_seek(sd.file, 0, .Start)
		runtime.clear(&sd.file_read_buf)
		sd.file_read_buf_offset = 0
		stbv.flush_pushdata(sd.vorbis)
		sd.decode_cursor = 0
		sd.seek_discard = target
	}

	slice.zero(ab.samples)
	sd.buffer_write_pos = 0
	sound_object.offset = 0
	sound_object.offset_fraction = 0

	// Decode into the buffer right away. If we left this to the next `update_audio_stream` then
	// the mixer would play the silence we just wrote. Worse, once the mixer has moved the read
	// position past the write position, the buffer looks full rather than empty, so it would not
	// be refilled until the read position had wrapped all the way around.
	//
	// This may remove the sound, so don't touch `sound_object` after it.
	update_audio_stream(sound_object.stream)
}

// Moves the decode cursor of a stream back to the start. Run when a stream-fed sound is stopped
// and when a non-looping stream reaches the end of the file, so that playing it again starts from
// the beginning.
_reset_audio_stream :: proc(stream: Audio_Stream) {
	sd := hm.get(&s.audio_streams, stream)

	if sd == nil {
		log.error("Cannot reset audio stream, stream does not exist.")
		return
	}

	sd.buffer_write_pos = 0
	sd.decode_cursor = 0
	sd.seek_discard = 0

	switch sd.mode {
	case .From_File:
		file_seek(sd.file, 0, .Start)
		runtime.clear(&sd.file_read_buf)
		sd.file_read_buf_offset = 0
		stbv.flush_pushdata(sd.vorbis)

	case .From_Bytes:
		stbv.seek_start(sd.vorbis)
	}

	// Zero the staging buffer so a replay doesn't briefly play stale samples before
	// `update_audio_stream` refills it.
	if ab := hm.get(&s.audio_clips, sd.clip); ab != nil {
		slice.zero(ab.samples)
	}

	if snd := hm.get(&s.sounds, sd.sound); snd != nil {
		snd.offset = 0
		snd.offset_fraction = 0
	}
}

// Run by the drawing procedures before they add any vertices. Draws the batch if `vertices_needed`
// more vertices will not fit in the vertex buffer, which leaves an empty one to put them in. Then
// starts a new draw call if the settings changed.
_begin_vertices :: proc(texture: Texture_Handle, vertices_needed: int) {
	s.current_texture = texture

	// Starting a draw call can pad the write position by up to one vertex, so ask for one extra.
	bytes_needed := s.current_shader.vertex_size*(vertices_needed + 1)

	if s.vertex_buffer_cpu_used + bytes_needed > len(s.vertex_buffer_cpu) {
		draw_current_batch()
	}

	if !_draw_call_matches_settings() {
		_finish_draw_call()
		_start_draw_call()
	}
}

// Whether the open draw call already draws things the way the current settings say. A zeroed draw
// call has no shader. It therefore never matches. That is the state right after a flush.
_draw_call_matches_settings :: proc() -> bool {
	dc := s.current_draw_call

	// The constants are the one thing we can't compare, see `current_constants_dirty`.
	if s.current_constants_dirty {
		return false
	}

	if dc.shader != s.current_shader.handle ||
	   dc.render_target != s.current_render_target ||
	   dc.scissor != s.current_scissor ||
	   dc.blend_mode != s.current_blend_mode {
		return false
	}

	return _textures_match(dc.textures)
}

// Compares the textures the current settings would bind against the ones a draw call captured.
// The shader's bindpoints are used as they are. The exception is the one Karl2D fills in with the
// texture being drawn.
_textures_match :: proc(recorded: []Texture_Handle) -> bool {
	shader := s.current_shader

	if len(recorded) != len(shader.texture_bindpoints) {
		return false
	}

	def_tex_idx, has_def_tex_idx := shader.default_texture_index.?

	for bindpoint, i in shader.texture_bindpoints {
		wanted := has_def_tex_idx && i == def_tex_idx ? s.current_texture : bindpoint

		if recorded[i] != wanted {
			return false
		}
	}

	return true
}

// Starts the draw call that the following vertices go into. Everything it needs is captured here.
// The drawing itself happens later, when the batch is flushed. Run `_finish_draw_call` first, or
// the vertices of the one that is already open are lost.
_start_draw_call :: proc() {
	shader := s.current_shader

	// Vertices for different shaders can share the buffer. Each draw call therefore starts at a
	// multiple of its own vertex size. That lets the backends address it as a plain vertex index.
	if remainder := s.vertex_buffer_cpu_used % shader.vertex_size; remainder != 0 {
		s.vertex_buffer_cpu_used += shader.vertex_size - remainder
	}

	// The shader keeps one copy of its constants and bindpoints. A draw call runs long after it was
	// recorded, so it needs the values it saw back then. A later `set_shader_constant` or write to
	// `texture_bindpoints` must not reach back and change it. It therefore gets its own copy.
	//
	// Draw calls that would copy the same values share one instead. That saves the copying. It also
	// lets the backend compare the two pointers to see there is nothing to re-upload.
	prev := s.current_draw_call
	same_shader := prev.shader == shader.handle

	constants_data := prev.constants_data

	if !same_shader || s.current_constants_dirty {
		constants_data = slice.clone(shader.constants_data, s.batch_allocator)
		_write_builtin_constants(shader, constants_data)
	}

	textures := prev.textures

	if !same_shader || !_textures_match(prev.textures) {
		textures = slice.clone(shader.texture_bindpoints, s.batch_allocator)

		// The texture being drawn is ours rather than the shader's. It goes into the copy.
		if def_tex_idx, has_def_tex_idx := shader.default_texture_index.?; has_def_tex_idx {
			textures[def_tex_idx] = s.current_texture
		}
	}

	// Scissor rectangles are screen space, which is what D3D11 and OpenGL take.
	scissor := s.current_scissor

	s.current_draw_call = {
		vertex_offset = s.vertex_buffer_cpu_used,
		shader = shader.handle,
		vertex_size = shader.vertex_size,
		constants = shader.constants,
		constants_data = constants_data,
		textures = textures,
		render_target = s.current_render_target,
		scissor = scissor,
		blend_mode = s.current_blend_mode,
	}

	s.current_constants_dirty = false
}

// Writes the constants that Karl2D itself supplies into a draw call's copy of them. They are ours
// rather than the shader program's, which is why they go into the copy and not into the shader.
// The view-projection matrix is the only one right now.
_write_builtin_constants :: proc(shader: Shader, constants_data: []u8) {
	for mloc, builtin in shader.constant_builtin_locations {
		constant, constant_ok := mloc.?

		if !constant_ok {
			continue
		}

		switch builtin {
		case .View_Projection_Matrix:
			if constant.size == size_of(Mat4) {
				(^Mat4)(&constants_data[constant.offset])^ = s.view_projection
			}
		}
	}
}

// Puts the open draw call into the list of recorded ones. Empty ones are left out, which is what a
// run of settings changes leaves behind. What stays open is an empty draw call with the same
// settings, so running this twice cannot record the same vertices twice.
_finish_draw_call :: proc() {
	dc := &s.current_draw_call

	if dc.shader == SHADER_NONE {
		return
	}

	dc.vertex_count = (s.vertex_buffer_cpu_used - dc.vertex_offset) / dc.vertex_size

	if dc.vertex_count > 0 {
		// Compared against the last draw call that made it into the list, because that is the one
		// the backend will have set up before this one. Dropped draw calls never happened.
		if len(s.batch_draw_calls) == 0 {
			dc.changed = DRAW_CALL_CHANGE_ALL
		} else {
			dc.changed = _draw_call_changes(s.batch_draw_calls[len(s.batch_draw_calls) - 1], dc^)
		}

		append(&s.batch_draw_calls, dc^)
	}

	dc.vertex_offset = s.vertex_buffer_cpu_used
	dc.vertex_count = 0
}

// Works out what `next` needs the backend to set up that `prev` did not. It is done here so that
// each backend does not have to. Things that go together are also decided in one place. A new
// render target needs a new scissor rect, for example.
_draw_call_changes :: proc(
	prev: Draw_Call,
	next: Draw_Call,
) -> (changed: bit_set[Draw_Call_Change]) {
	if prev.shader != next.shader {
		// A different shader has its own constant buffers and texture bindpoints. Those have to be
		// set up again even when the values in them are the same.
		changed += { .Shader, .Constants, .Textures }
	}

	// Draw calls that hold the same values share one copy of them. The same memory therefore means
	// there is nothing to re-upload.
	if raw_data(prev.constants_data) != raw_data(next.constants_data) {
		changed += { .Constants }
	}

	if raw_data(prev.textures) != raw_data(next.textures) {
		changed += { .Textures }
	}

	if prev.render_target != next.render_target {
		// A draw call without a scissor rect gets one that covers the whole render target.
		changed += { .Render_Target, .Scissor }
	}

	if prev.scissor != next.scissor {
		changed += { .Scissor }
	}

	if prev.blend_mode != next.blend_mode {
		changed += { .Blend_Mode }
	}

	return
}

// Callers must run `_begin_vertices` first. That leaves room in the buffer and a draw call to put
// the vertex in.
batch_vertex :: proc(v: Vec2, uv: Vec2, color: Color) {
	v := v
	shd := s.current_shader

	base_offset := s.vertex_buffer_cpu_used
	pos_offset := shd.default_input_offsets[.Position]
	uv_offset := shd.default_input_offsets[.UV]
	color_offset := shd.default_input_offsets[.Color]
	
	mem.set(&s.vertex_buffer_cpu[base_offset], 0, shd.vertex_size)

	if pos_offset != -1 {
		(^Vec2)(&s.vertex_buffer_cpu[base_offset + pos_offset])^ = v

		if s.depth_test {
			(^f32)(&s.vertex_buffer_cpu[base_offset + pos_offset + size_of(Vec2)])^ = s.z
		}
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

// Draws the batch if any recorded draw call still samples `texture`. Those draw calls have to
// happen before the texture changes or goes away. Nothing has usually been drawn with it yet, in
// which case there is nothing to wait for.
_flush_if_batch_uses_texture :: proc(texture: Texture_Handle) {
	if texture == TEXTURE_NONE {
		return
	}

	uses_texture :: proc(dc: Draw_Call, texture: Texture_Handle) -> bool {
		for t in dc.textures {
			if t == texture {
				return true
			}
		}

		return false
	}

	if uses_texture(s.current_draw_call, texture) {
		draw_current_batch()
		return
	}

	for dc in s.batch_draw_calls {
		if uses_texture(dc, texture) {
			draw_current_batch()
			return
		}
	}
}

// Same as `_flush_if_batch_uses_texture`. This one is for a shader that is about to go away.
_flush_if_batch_uses_shader :: proc(shader: Shader_Handle) {
	if shader == SHADER_NONE {
		return
	}

	if s.current_draw_call.shader == shader {
		draw_current_batch()
		return
	}

	for dc in s.batch_draw_calls {
		if dc.shader == shader {
			draw_current_batch()
			return
		}
	}
}

// Same as `_flush_if_batch_uses_texture`. This one is for a render target about to go away.
_flush_if_batch_uses_render_target :: proc(render_target: Render_Target_Handle) {
	if render_target == RENDER_TARGET_NONE {
		return
	}

	if s.current_draw_call.render_target == render_target {
		draw_current_batch()
		return
	}

	for dc in s.batch_draw_calls {
		if dc.render_target == render_target {
			draw_current_batch()
			return
		}
	}
}

// Run after changing `proj_matrix` or `view_matrix`. Draw calls then pick up the new combination.
_update_view_projection :: proc() {
	s.view_projection = s.proj_matrix * s.view_matrix
	s.current_constants_dirty = true
}

VERTEX_BUFFER_MAX :: 1000000

// How much room the batch arena starts with. A draw call needs a handful of bytes for its
// textures. It only copies the constants when they actually changed. This therefore covers a frame
// with thousands of draw calls in it. The arena grows if a frame needs more.
BATCH_ARENA_BLOCK_SIZE :: 64*1024

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
	if name == "position" && (type == .Vec2 || type == .Vec3) {
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
		// The shaders take a vec3 position, but with depth testing off we only feed it xy and let
		// the shader default z to 0. That keeps the 2D vertex at 20 bytes.
		case .Position: return s.depth_test ? .RGB_32_Float : .RG_32_Float
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
matrix_ortho3d_f32 :: proc "contextless" (
	left, right, bottom, top: f32,
	z_min, z_max: f32,
	clip_z_min, clip_z_max: f32,
) -> Mat4 #no_bounds_check {
	m: Mat4

	// Maps the user-facing z range onto the render backend's clip space z range. GL and D3D11
	// disagree on that range (-w..w vs 0..w), which is why this can't just be a fixed +1 like a
	// pure 2D ortho matrix would use.
	z_scale := (clip_z_max - clip_z_min) / (z_max - z_min)

	m[0, 0] = +2 / (right - left)
	m[1, 1] = +2 / (top - bottom)
	m[2, 2] = z_scale
	m[0, 3] = -(right + left)   / (right - left)
	m[1, 3] = -(top   + bottom) / (top - bottom)
	m[2, 3] = clip_z_min - z_min * z_scale
	m[3, 3] = 1

	return m
}

make_default_projection :: proc(w, h: int, flip_y: bool) -> matrix[4,4]f32 {
	clip_z_min, clip_z_max := rb.get_depth_clip_range()

	if flip_y {
		return matrix_ortho3d_f32(
			0, f32(w), 0, f32(h),
			s.depth_range_min, s.depth_range_max,
			clip_z_min, clip_z_max,
		)
	}

	return matrix_ortho3d_f32(
		0, f32(w), f32(h), 0,
		s.depth_range_min, s.depth_range_max,
		clip_z_min, clip_z_max,
	)
}

// Returns true if the currently used camera wants the Y axis to be flipped.
_camera_flip_y :: proc() -> bool {
	if cam, cam_ok := s.current_camera.?; cam_ok {
		return cam.flip_y
	}

	return false
}

FONT_DEFAULT_ATLAS_SIZE :: 2048

// Gets glyphs that were baked since the last flush onto the GPU. Drawing text with a dynamic font
// bakes the glyphs it needs into fontstash's atlas as it goes. This has to run before the draw
// calls that use them. Fontstash only ever puts glyphs in unused parts of the atlas. Texture
// coordinates already recorded in the vertex buffer therefore stay valid.
//
// Every dynamic font shares one fontstash atlas. Each has its own GPU texture mirroring it. They
// all get the same update.
_update_font_atlases :: proc() {
	font_dirty_rect: [4]f32

	if !fs.ValidateTexture(&s.fs, &font_dirty_rect) {
		return
	}

	for font in s.fonts {
		// A static font has a finished atlas of its own, it is not part of fontstash's. A
		// destroyed font has no atlas left at all.
		if font.type == .Dynamic && font.atlas.handle != TEXTURE_NONE {
			_update_font_atlas(font, font_dirty_rect)
		}
	}
}

_update_font_atlas :: proc(font: Font_Data, font_dirty_rect: [4]f32) {
	tw := FONT_DEFAULT_ATLAS_SIZE
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

// Not for direct use. Specify font to `draw_text_ex`
_set_font :: proc(fh: Font) {
	fh := fh

	if s.current_font == fh {
		return
	}

	s.current_font = fh

	if fh == 0 {
		fh = FONT_DEFAULT
	}

	font := &s.fonts[fh]
	fs.SetFont(&s.fs, font.dynamic_fontstash_handle)
}

_ :: jpeg
_ :: bmp
_ :: png
_ :: tga

Color_F32 :: [4]f32

f32_color_from_color :: proc(color: Color) -> Color_F32 {
	return (Color_F32)(color)/255
}

color_from_f32_color :: proc(color: Color_F32) -> Color {
	return (Color)(color*255)
}
