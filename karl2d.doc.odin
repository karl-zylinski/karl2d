// This file gives an overview of the Karl2D API. It shows all procedures without their bodies.
// This file is generated from the contents of 'karl2d.odin'. It should not be compiled.
#+build ignore
package karl2d

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
) -> ^State

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
update :: proc() -> bool

// Returns true the user has pressed the close button on the window, or used a key stroke such as
// ALT+F4 on Windows. The application can decide if it wants to shut down or if it wants to show
// some kind of confirmation dialogue.
//
// Called by `update`, but can be called manually if you need more control.
close_window_requested :: proc() -> bool

// Closes the window and cleans up Karl2D's internal state.
shutdown :: proc()

// Clear the "screen" with the supplied color. By default this will clear your window. But if you
// have set a Render Texture using the `set_render_texture` procedure, then that Render Texture will
// be cleared instead.
clear :: proc(color: Color)

// The library may do some internal allocations that have the lifetime of a single frame. This
// procedure empties that Frame Allocator.
//
// Called as part of `update`, but can be called manually if you need more control.
reset_frame_allocator :: proc()

// Calculates how long the previous frame took and how it has been since the application started.
// You can fetch the calculated values using `get_frame_time` and `get_time`.
//
// Called as part of `update`, but can be called manually if you need more control.
calculate_frame_time :: proc()

// Present the drawn stuff to the player. Also known as "flipping the backbuffer": Call at end of
// frame to make everything you've drawn appear on the screen.
//
// When you draw using for example `draw_texture`, then that stuff is drawn to an invisible texture
// called a "backbuffer". This makes sure that we don't see half-drawn frames. So when you are happy
// with a frame and want to show it to the player, call this procedure.
//
// WebGL note: WebGL does the backbuffer flipping automatically. But you should still call this to
// make sure that all rendering has been sent off to the GPU (as it calls `draw_current_batch()`).
present :: proc()

// Process all events that have arrived from the platform APIs. This includes keyboard, mouse,
// gamepad and window events. This procedure processes and stores the information that procs like
// `key_went_down` need.
//
// Called by `update`, but can be called manually if you need more control.
process_events :: proc()

// Fetch a list of all events that happened this frame. Most games can use the `key_is_held`, 
// `mouse_button_went_down` etc procedures to check input state. But if you want a list of events
// instead, then you can use this. These events will also include things like "Window Focus" events
// and "Window Resize" events.
//
// Note: Gamepad axis movement (analogue sticks and analogue triggers) are _not_ events. Those can
// only be queried using `k2.get_gamepad_axis`.
//
// Note: These are the events the platform reported. The touch that `set_touch_events_from_mouse`
// makes from the mouse is not one of them, it only shows up in `get_touches`.
//
// Warning: The returned slice is only valid during the current frame! You can make a clone of it
// using the `slice.clone` procedure (import `core:slice`).
get_events :: proc() -> []Event

// Returns how many seconds the previous frame took. Often a tiny number such as 0.016 s.
//
// This value is updated when `calculate_frame_time()` runs (which is also called by `update()`).
get_frame_time :: proc() -> f32

// Returns how many seconds has elapsed since the game started. This is a `f64` number, giving good
// precision when the application runs for a long time.
//
// This value is updated when `calculate_frame_time()` runs (which is also called by `update()`).
get_time :: proc() -> f64

// Resize the drawing area of the window (the screen) to a new size. While the user cannot resize
// windows with `window_mode == .Windowed_Resizable`, this procedure is able to resize such windows.
set_screen_size :: proc(width: int, height: int)

// Gets the width of the drawing area within the window.
get_screen_width :: proc() -> int

// Gets the height of the drawing area within the window.
get_screen_height :: proc() -> int

// Gets the screen width and height as a 2D vector.
get_screen_size :: proc() -> Vec2

// Change the window title.
set_window_title :: proc(title: string)

// Moves the window.
//
// This does nothing for web builds.
set_window_position :: proc(x: int, y: int)

// Gets the window position in the same coordinate system used by `set_window_position`.
//
// This returns {} for web and Wayland builds.
get_window_position :: proc() -> Vec2

// Fetch the scale of the window. This usually comes from some DPI scaling setting in the OS.
// 1 means 100% scale, 1.5 means 150% etc.
//
// Karl2D does not do any automatic scaling. If you want a scaled resolution, then multiply the
// wanted resolution by the scale and send it into `set_screen_size`. You can use a camera and set
// the zoom to the window scale in order to make things the same percieved size.
get_window_scale :: proc() -> f32

// Use to change between windowed mode, resizable windowed mode and fullscreen
set_window_mode :: proc(window_mode: Window_Mode)

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
draw_current_batch :: proc()

//-------//
// INPUT //
//-------//

// Returns true if a keyboard key went down between the current and the previous frame. Set when
// 'process_events' runs.
//
// If `allow_repeat` is true, then this also returns true for OS-generated key-repeat events (the
// same behavior a text editor wants when you hold down Backspace). The repeat rate and initial
// delay come from the operating system's keyboard settings.
key_went_down :: proc(key: Keyboard_Key, allow_repeat := false) -> bool

// Returns true if a keyboard key went up (was released) between the current and the previous frame.
// Set when 'process_events' runs.
key_went_up :: proc(key: Keyboard_Key) -> bool

// Returns true if a keyboard is currently being held down. Set when 'process_events' runs.
key_is_held :: proc(key: Keyboard_Key) -> bool

// Returns all the Unicode code points that were typed since the last frame, taking the current
// keyboard layout into account. This is what you want for text input, as opposed to
// `key_went_down`, which tells you about physical keys rather than the characters they produce.
//
// Control characters (Backspace, Enter, Tab, etc) and presses of modifier keys on their own are
// never included.
//
// Warning: The returned slice is only valid during the current frame! You can make a clone of it
// using the `slice.clone` procedure (import `core:slice`).
get_typed_runes :: proc() -> []rune

// Returns all touches that were active at any point during this frame, including those that ended
// this frame (those have `went_up` set).
//
// Note: Only web reports touches from a real touch screen. On desktop the only touches you get are
// the ones `set_touch_events_from_mouse` makes from the mouse.
//
// Note: The order is not stable. When a touch ends, the last one in the list takes its place, so
// match touches by `id` between frames rather than by where they sit in the slice.
//
// Warning: The returned slice is only valid during the current frame!
get_touches :: proc() -> []Touch

// Enabled by default. Holding the left mouse button produces a touch (with id `EMULATED_TOUCH_ID`),
// so code written for touch also works with a mouse. Turn it off if you handle the mouse yourself,
// otherwise one drag arrives as both.
//
// The touch is built from the mouse state, so it never shows up in `get_events`, only in
// `get_touches`.
set_touch_events_from_mouse :: proc(enabled: bool)

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
get_held_modifiers :: proc() -> bit_set[Modifier]

// Returns true if a mouse button went down between the current and the previous frame. Specify
// which mouse button using the `button` parameter.
//
// Set when 'process_events' runs.
mouse_button_went_down :: proc(button: Mouse_Button) -> bool

// Returns true if a mouse button went up (was released) between the current and the previous frame.
// Specify which mouse button using the `button` parameter.
//
// Set when 'process_events' runs.
mouse_button_went_up :: proc(button: Mouse_Button) -> bool

// Returns true if a mouse button is currently being held down. Specify which mouse button using the
// `button` parameter. Set when 'process_events' runs.
mouse_button_is_held :: proc(button: Mouse_Button) -> bool

// Returns how many clicks the mouse wheel has scrolled between the previous and current frame.
// Positive means scrolling up.
get_mouse_wheel_delta :: proc() -> f32

// Returns how many clicks the horizontal mouse wheel has scrolled between the previous and current
// frame. Positive means scrolling right.
//
// A tilt wheel or a two-finger sideways swipe on a trackpad drives this one.
get_mouse_wheel_delta_horizontal :: proc() -> f32

// Returns the mouse position, measured from the top-left corner of the window.
get_mouse_position :: proc() -> Vec2

// Returns how many pixels the mouse moved between the previous and the current frame.
get_mouse_delta :: proc() -> Vec2

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
set_mouse_locked :: proc(locked: bool)

// Returns true if the mouse is currently locked. Note that the mouse can get unlocked by the OS,
// even though you previously called `set_mouse_locked(true)`. Therefore, it's best to check the
// current status using this procedure and then lock the mouse if needed.
is_mouse_locked :: proc() -> bool

// Returns true if a gamepad with the supplied index is connected. The parameter should be a value
// between 0 and MAX_GAMEPADS.
is_gamepad_active :: proc(gamepad: Gamepad_Index) -> bool

// Returns true if a gamepad button went down between the previous and the current frame.
gamepad_button_went_down :: proc(gamepad: Gamepad_Index, button: Gamepad_Button) -> bool

// Returns true if a gamepad button went up (was released) between the previous and the current
// frame.
gamepad_button_went_up :: proc(gamepad: Gamepad_Index, button: Gamepad_Button) -> bool

// Returns true if a gamepad button is currently held down.
//
// The "trigger buttons" on some gamepads also have an analogue "axis value" associated with them.
// Fetch that value using `get_gamepad_axis()`.
gamepad_button_is_held :: proc(gamepad: Gamepad_Index, button: Gamepad_Button) -> bool

// Returns the value of analogue gamepad axes such as the thumbsticks and trigger buttons. The value
// is in the range -1 to 1 for sticks and 0 to 1 for trigger buttons.
get_gamepad_axis :: proc(gamepad: Gamepad_Index, axis: Gamepad_Axis) -> f32

// Set the left and right vibration motor speed. The range of left and right is 0 to 1. Note that on
// most gamepads, the left motor is "low frequency" and the right motor is "high frequency". They do
// not vibrate with the same speed.
set_gamepad_vibration :: proc(gamepad: Gamepad_Index, left: f32, right: f32)

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
draw_rect :: proc(rect: Rect, color: Color, origin: Vec2 = {}, rotation: f32 = 0)

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
)

// Draw the outline of a rectangle with a specific thickness. The outline is drawn using four
// rectangles.
draw_rect_outline :: proc(r: Rect, thickness: f32, color: Color)

// Draw a circle with a certain center and radius. Note the `segments` parameter: This circle is not
// perfect! It is drawn using a number of "cake segments".
draw_circle :: proc(center: Vec2, radius: f32, color: Color, segments := 16)

// Like `draw_circle` but only draws the outer edge of the circle.
draw_circle_outline :: proc(center: Vec2, radius: f32, thickness: f32, color: Color, segments := 16)

// Draws a line from `start` to `end` of a certain thickness.
draw_line :: proc(start: Vec2, end: Vec2, thickness: f32, color: Color)

// Draws a triangle using three vertices. The order of the vertices does not matter: Clockwise and
// counter-clockwise triangles will give the same result.
draw_triangle :: proc(vertices: [3]Vec2, c: Color)

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
)

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
)

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
)

// Measures how much space some text of a certain size will use on the screen. Will use the default
// font unless you specify a custom font.
measure_text :: proc(text: string, font_size: f32, font: Font = FONT_DEFAULT) -> Vec2

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
)

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
) -> (Texture, bool) #optional_ok

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
) -> (Texture, bool) #optional_ok

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
) -> (Texture, bool) #optional_ok

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
) -> (Texture, bool) #optional_ok

// Create a GPU texture from an image stored in RAM. There are currently no procedures to manipulate
// the image. However, you can create an `Image` struct manually and fill out the data as needed.
//
// The second return value is `true` if the texture was loaded correctly. It's optional to handle
// this error, it will also be logged. In case of failure, the returned `Texture` will still be
// possible to use, but it won't draw anything.
load_texture_from_image :: proc(image: Image) -> (Texture, bool) #optional_ok

// Load an image from disk into RAM. Supports the same formats as `load_texture_from_file`. The
// image is always RGBA8 with straight (non-premultiplied) alpha.
//
// Use `destroy_image` when you are done with it.
//
// The second return value is `true` if the image was loaded correctly. It's optional to handle
// this error, it will also be logged. In case of failure, the returned `Image` will be empty: it
// has no pixels and a width and height of zero.
load_image_from_file :: proc(filename: string) -> (Image, bool) #optional_ok

// Load an image from a byte slice into RAM, for instance from `#load("my_image.png")`. Supports
// the same formats as `load_texture_from_bytes`. The image is always RGBA8 with straight
// (non-premultiplied) alpha.
//
// Use `destroy_image` when you are done with it.
//
// The second return value is `true` if the image was loaded correctly. It's optional to handle
// this error, it will also be logged. In case of failure, the returned `Image` will be empty: it
// has no pixels and a width and height of zero.
load_image_from_bytes :: proc(bytes: []u8) -> (Image, bool) #optional_ok

// Destroy an image previously loaded using `load_image_from_file` or `load_image_from_bytes`.
destroy_image :: proc(img: Image)

// Get a rectangle that spans the whole texture. Coordinates will be (x, y) = (0, 0) and size
// (w, h) = (texture_width, texture_height)
get_texture_rect :: proc(t: Texture) -> Rect

// Update a texture with new pixels. `bytes` is the new pixel data. `rect` is the rectangle in
// `tex` where the new pixels should end up.
update_texture :: proc(tex: Texture, bytes: []u8, rect: Rect) -> bool

// Destroy a texture, freeing up any memory it has used on the GPU.
destroy_texture :: proc(tex: Texture)

// Controls how a texture should be filtered. You can choose "point" or "linear" filtering. Which
// means "pixly" or "smooth". This filter will be used for up and down-scaling as well as for
// mipmap sampling. Use `set_texture_filter_ex` if you need to control these settings separately.
set_texture_filter :: proc(t: Texture, filter: Texture_Filter)

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
)

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
) -> Sound

// Stops the sound, which destroys its playback state in the mixer. For a `Sound` started using
// `play_audio_stream`, this also rewinds the stream to the start. Use `set_sound_paused` to pause
// the Sound instead, which won't lose the current playback position and settings.
stop_sound :: proc(sound: Sound)

// Pause or unpause a sound. A paused sound keeps its position and stays valid until it is unpaused
// or stopped.
set_sound_paused :: proc(sound: Sound, paused: bool)

// Returns true if the sound exists and is not paused.
sound_is_playing :: proc(sound: Sound) -> bool

// Returns true if the sound still exists. Both playing and paused sounds are valid. A finished or
// stopped sound is not.
sound_is_valid :: proc(sound: Sound) -> bool

// Set the volume of a sound. Range: 0 to 1.
set_sound_volume :: proc(sound: Sound, volume: f32)

// Set the pan of a sound. Range: -1 to 1, where -1 is full left, 0 is center and 1 is full right.
set_sound_pan :: proc(sound: Sound, pan: f32)

// Set the pitch of a sound. Range: 0.01 and up, where 1 is the default. Pitch 2 makes the sound
// play twice as fast, which also makes it sound higher pitched.
set_sound_pitch :: proc(sound: Sound, pitch: f32)

// Move the sound to another spot in its audio. `seconds` is measured from the start of the audio,
// so 0 moves it back to the beginning. Use `get_sound_length` to find out how far you can go.
//
// Moving a sound that plays an audio stream is a bit slower than one that plays a clip, since some
// audio has to be decoded before it can play. Don't do it every frame while dragging a scrub bar,
// do it when the player lets go.
set_sound_time :: proc(sound: Sound, seconds: f32)

// Get how far into its audio the sound currently is, in seconds. A looping sound goes back to 0
// each time it starts over. Returns 0 if the sound doesn't exist.
get_sound_time :: proc(sound: Sound) -> f32

// Get the length of the sound's audio, in seconds. Use it together with `get_sound_time` to show
// how far into a song you are. Returns 0 if the sound doesn't exist or if the length is unknown.
get_sound_length :: proc(sound: Sound) -> f32

// Make a sound loop when it reaches the end.
//
// Technical note: This also works for sounds started using `play_audio_stream`, but then it
// reaches into the streaming decoder and tells that one to loop. A `Sound` started from a stream
// plays a short buffer that the decoder keeps filling, so that sound always loops.
set_sound_loop :: proc(sound: Sound, loop: bool)

// Route a sound into an audio bus. Pass `AUDIO_BUS_MASTER` for the master bus.
set_sound_bus :: proc(sound: Sound, bus: Audio_Bus)

// How many sounds currently play this clip. Useful for limiting how many overlapping sounds you
// start from the same clip.
get_num_sounds_playing_clip :: proc(clip: Audio_Clip) -> int

// Load a WAV file from disk. Returns an `Audio_Clip` which can be played using `play_audio_clip`.
//
// Supports mono and stereo WAV files with 8, 16, 24 or 32 bit integer samples, or 32 or 64 bit
// float samples.
//
// The second return value is `true` if the audio clip was loaded correctly. It's optional to
// handle this error, it will also be logged. In case of failure, the returned `Audio_Clip` will
// still be possible to use, but it won't play anything.
load_audio_clip_from_file :: proc(filename: string) -> (Audio_Clip, bool) #optional_ok

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
load_audio_clip_from_bytes :: proc(bytes: []u8) -> (Audio_Clip, bool) #optional_ok

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
) -> (Audio_Clip, bool) #optional_ok

// Destroy an audio clip previously loaded using `load_audio_clip_from_xxx`. Also stops sounds
// playing this clip.
destroy_audio_clip :: proc(clip: Audio_Clip)

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
) -> (Audio_Stream, bool) #optional_ok

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
) -> (Audio_Stream, bool) #optional_ok

// Destroy an audio stream previously loaded using `load_audio_stream_from_file` or
// `load_audio_stream_from_bytes`. This cleans up some internal state and closes file handles.
//
// If you created the stream using `load_audio_stream_from_bytes`, then this procedure will NOT
// deallocate the bytes that you sent into that procedure.
destroy_audio_stream :: proc(stream: Audio_Stream)

// TODO-UPDATE-COMMENT this may now be called from a thread of your own, one thread at a time per
// stream, and the decoding it does no longer holds the mutex the mixer needs.
// Streams in new audio data from the audio stream. You need to call this once per frame in order
// for the streaming to actually happen. 
update_audio_stream :: proc(stream: Audio_Stream)

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
) -> Sound

// Create an audio bus: A group of sounds that are mixed together before they reach the master bus.
// Route sounds into it using `set_sound_bus`, or the `bus` parameter of `play_audio_clip` or
// `play_audio_stream`.
//
// A new bus has volume 1, pan 0 and no effect. That makes it a passthrough: Playing a sound on a
// fresh bus sounds exactly like playing it on the master bus, until you change something.
create_audio_bus :: proc() -> Audio_Bus

// Destroy an audio bus. Everything routed to it goes back to the master bus, including sounds that
// are playing right now.
destroy_audio_bus :: proc(bus: Audio_Bus)

// Set the volume of an audio bus. Range: 0 to 1. Everything mixed into the bus is scaled by this.
//
// This works on `AUDIO_BUS_MASTER` as well, which is how you set the master volume of your game.
set_audio_bus_volume :: proc(bus: Audio_Bus, volume: f32)

// Set the pan of an audio bus. Range: -1 to 1, where -1 is full left, 0 is center and 1 is full
// right.
//
// This is a balance control: It turns the opposite side down. The pan of a sound works
// differently: It moves the sound between the left and right speakers while keeping the overall
// loudness the same. A bus is already a finished stereo mix, and a bus at pan 0 has to leave it
// exactly as it is.
set_audio_bus_pan :: proc(bus: Audio_Bus, pan: f32)

// Set an effect to run on everything that is mixed into the bus. This is how you apply your own
// audio processing, such as a filter, to a whole group of sounds at once.
//
// `user_data` is handed to the effect when it runs. Put whatever state your effect needs there:
// The effect is called once per mixed chunk, so anything it wants to remember between the chunks
// has to live in `user_data`. Pass `nil` as `effect` to remove the effect.
//
// See `Audio_Effect_Proc` for what the effect is given and what it is allowed to do.
set_audio_bus_effect :: proc(bus: Audio_Bus, effect: Audio_Effect_Proc, user_data: rawptr = nil)

// Update the audio mixer and feed more audio data into the audio backend. This is done
// automatically when `update` runs, so you normally don't need to call this manually.
//
// This procedure implements a custom software audio mixer. The audio backend is just fed the
// resulting mix. Therefore, you can see everything regarding how audio is processed in this
// procedure.
//
// Will only run if the audio backend is running low on audio data.
update_audio_mixer :: proc()

//-----------------//
// RENDER TEXTURES //
//-----------------//

// Create a texture that you can render into. Meaning that you can draw into it instead of drawing
// onto the screen. Use `set_render_texture` to enable this Render Texture for drawing.
//
// The second return value is `true` if the render texture was created correctly. It's optional to
// handle this error, it will also be logged. In case of failure, the returned `Render_Texture`
// will still be possible to use, but setting it does nothing, so drawing stays where it was.
create_render_texture :: proc(width: int, height: int) -> (Render_Texture, bool) #optional_ok

// Destroy a Render_Texture previously created using `create_render_texture`.
destroy_render_texture :: proc(render_texture: Render_Texture)

// Make all rendering go into a texture instead of onto the screen. Create the render texture using
// `create_render_texture`. Pass `nil` to resume drawing onto the screen.
set_render_texture :: proc(render_texture: Maybe(Render_Texture))

//-------------//
// MATHEMATICS //
//-------------//

// Returns true if rectangles `a` and `b` are overlapping.
rect_overlapping :: proc(a: Rect, b: Rect) -> bool

// Returns the overlap of rectangle `a` and `b`. The second return value is `false` if no overlap
// was found, `true` otherwise.
rect_overlap :: proc(a: Rect, b: Rect) -> (Rect, bool)

// Return true if `point` is inside `rect`.
point_in_rect :: proc(point: Vec2, rect: Rect) -> bool

// Returns the mid-point of a rectangle.
//
// Useful when for passing as `origin` to drawing procedures, especially when you want the
// drawn thing to rotate around its center.
rect_middle :: proc(r: Rect) -> Vec2

rect_center :: rect_middle
rect_centre :: rect_middle

// Combine a position and a size into a rectangle.
rect_from_pos_size :: proc(pos: Vec2, size: Vec2) -> Rect

// Get the top left corner of a rectangle.
rect_top_left :: proc(r: Rect) -> Vec2

// Get the top middle point of a rectangle. That is, the mid-point between the top left and top
// right corners.
rect_top_middle :: proc(r: Rect) -> Vec2

// Get the top right corner of a rectangle.
rect_top_right :: proc(r: Rect) -> Vec2

// Get the bottom left corner of a rectangle.
rect_bottom_left :: proc(r: Rect) -> Vec2

// Get the bottom middle point of a rectangle. That is, the mid-point between the bottom left and
// bottom right corners.
rect_bottom_middle :: proc(r: Rect) -> Vec2

// Get the bottom right corner of a rectangle.
rect_bottom_right :: proc(r: Rect) -> Vec2

// Make a rectangle smaller by `x` pixels in the horizontal direction and `y` pixels in the vertical
rect_shrink :: proc(r: Rect, x: f32, y: f32) -> Rect

// Make a rectangle bigger by `x` pixels in the horizontal direction and `y` pixels in the vertical.
rect_expand :: proc(r: Rect, x: f32, y: f32) -> Rect

// Cut off `h` pixels from the top of `r`. `r` is modified. The cut off part is returned.
// `m` is the margin added above the cut part.
rect_cut_top :: proc(r: ^Rect, h: f32, m: f32) -> Rect

// Cut off `h` pixels from the bottom of `r`. `r` is modified. The cut off part is returned.
// `m` is the margin added below the cut part.
rect_cut_bottom :: proc(r: ^Rect, h: f32, m: f32) -> Rect

// Cut off `w` pixels from the left of `r`. `r` is modified. The cut off part is returned.
// `m` is the margin added to the left of the cut part.
rect_cut_left :: proc(r: ^Rect, w: f32, m: f32) -> Rect

// Cut off `w` pixels from the right of `r`. `r` is modified. The cut off part is returned.
// `m` is the margin added to the right of the cut part.
rect_cut_right :: proc(r: ^Rect, w: f32, m: f32) -> Rect

// Rotate 2D vector `v` by `angle_radians` radians around the origin (0, 0).
//
// If you need to rotate around a point that is not the origin, then you can first subtract the
// point from `v`, then rotate and then add the point back to the result.
rotate :: proc(v: Vec2, angle_radians: f32) -> Vec2

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
) -> (Font, bool) #optional_ok

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
) -> (Font, bool) #optional_ok

// Like `load_dynamic_font_from_bytes`, but reads a file from disk using a filename.
//
// The second return value is `true` if the font was loaded correctly. It's optional to handle this
// error, it will also be logged. In case of failure, the returned `Font` will still be possible to
// use, but text drawn with it uses the default font.
load_dynamic_font_from_file :: proc(
	filename: string,
	options: Font_Options = {},
) -> (Font, bool) #optional_ok

// Load a TTF font stored in `data` as a dynamic font. This means that an atlas will be dynamically
// built as you draw characters using this font.
//
// The second return value is `true` if the font was loaded correctly. It's optional to handle this
// error, it will also be logged. In case of failure, the returned `Font` will still be possible to
// use, but text drawn with it uses the default font.
load_dynamic_font_from_bytes :: proc(
	data: []u8,
	options: Font_Options = {},
) -> (Font, bool) #optional_ok

// Destroy a font previously loaded using `load_font_from_file` or `load_font_from_bytes`.
destroy_font :: proc(font: Font)

//---------//
// CURSORS //
//---------//

// Sets the cursor, either to one the operating system provides or to one made with
// `create_custom_cursor`. `set_cursor(.Default)` goes back to the normal OS cursor.
set_cursor :: proc(cursor: Cursor)

// Create a cursor from an image. `hotspot` is the position within the image that points at things,
// in physical pixels.
//
// The cursor does not need `image` after it is created. You may destroy it.
//
// The second return value is `true` if the cursor was created correctly. It's optional to handle
// this error, it will also be logged. In case of failure, the returned `Custom_Cursor` will still
// be possible to use, but setting it leaves the cursor as it is.
create_custom_cursor :: proc(image: Image, hotspot: [2]int) -> (Custom_Cursor, bool) #optional_ok

// Destroy a cursor previously created using `create_custom_cursor`. If it is the cursor currently
// on screen then Karl2D will restore the default OS cursor.
destroy_custom_cursor :: proc(custom_cursor: Custom_Cursor)

// Hide or show the mouse cursor. The cursor may get shown again if the window loses focus.
// Therefore, it's often best to use `is_cursor_hidden` to check the current status and use this
// procedure to hide the cursor as needed.
//
// This call does not lock the mouse within the window, do that using a separate call to
// `set_mouse_locked`.
set_cursor_hidden :: proc(hidden: bool)

// Returns true if the cursor is hidden. The cursor may get re-shown by the OS, for example when the
// window loses focus. Therefore, this procedure may return false even though you've hidden the
// cursor previously. It should always reflect the true hide-state of the cursor.
is_cursor_hidden :: proc() -> bool

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
) -> (Shader, bool) #optional_ok

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
) -> (Shader, bool) #optional_ok

// Destroy a shader previously loaded using `load_shader_from_file` or `load_shader_from_bytes`
destroy_shader :: proc(shader: Shader)

// Fetches the shader that Karl2D uses by default.
get_default_shader :: proc() -> Shader

// The supplied shader will be used for subsequent drawing. Return to the default shader by calling
// `set_shader(nil)`.
set_shader :: proc(shader: Maybe(Shader))

// Set the value of a constant (also known as uniform in OpenGL). Look up shader constant locations
// (the kind of value needed for `loc`) by running `loc := shader.constant_lookup["constant_name"]`.
set_shader_constant :: proc(shd: Shader, loc: Shader_Constant_Location, val: any)

// Sets the value of a shader input (also known as a shader attribute). There are three default
// shader inputs known as position, texcoord and color. If you have shader with additional inputs,
// then you can use this procedure to set their values. This is a way to feed per-object data into
// your shader.
//
// `input` should be the index of the input and `val` should be a value of the correct size.
//
// You can modify which type that is expected for `val` by passing a custom `layout_formats` when
// you load the shader.
override_shader_input :: proc(shader: Shader, input: int, val: any)

// Returns the number of bytes that a pixel in a texture uses.
pixel_format_size :: proc(f: Pixel_Format) -> int

//-------------------------------//
// CAMERA AND COORDINATE SYSTEMS //
//-------------------------------//

// Make Karl2D use a camera. Return to the "default camera" by passing `nil`. All drawing operations
// will use this camera until you again change it.
set_camera :: proc(camera: Maybe(Camera))

// Transform a point `pos` that lives on the screen into the camera's coordinates.
//
// Example: Bringing the mouse position into the coordinate space of a camera:
//
//// world_mouse_pos := k2.screen_to_camera(k2.get_mouse_position(), world_camera)
screen_to_camera :: proc(pos: Vec2, camera: Camera) -> Vec2

// Transform a point `pos` that lives in the camera's coordinates to a point on the screen. This can
// be useful when you need to compare such a position to a screen-space point.
camera_to_screen :: proc(pos: Vec2, camera: Camera) -> Vec2

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
camera_view_matrix :: proc(c: Camera) -> Mat4

// The inverse of `camera_view_matrix`. It undoes the camera instead of applying it.
camera_inverse_view_matrix :: proc(c: Camera) -> Mat4

//------//
// MISC //
//------//

// Choose how the alpha channel is used when mixing half-transparent color with what is already
// drawn. The default is the .Alpha mode, but you also have the option of using .Premultiply_Alpha.
set_blend_mode :: proc(mode: Blend_Mode)

// Make everything outside of the screen-space rectangle `scissor_rect` not render. Disable the
// scissor rectangle by running `set_scissor_rect(nil)`.
set_scissor_rect :: proc(scissor_rect: Maybe(Rect))

// Set the z used by draws that happen after this call. Only has an effect when `depth_test` was
// enabled in `Init_Options`. Higher z ends up in front. Unlike `set_blend_mode` and
// `set_scissor_rect`, this never starts a new draw call: the z is stored in each vertex rather
// than being part of a draw call's settings, so it's fine to call this before every draw.
set_z :: proc(z: f32)

// Get the z previously set with `set_z`. Defaults to 0.
get_z :: proc() -> f32

// Restore the internal state using the pointer returned by `init`. Useful after reloading the
// library (for example, when doing code hot reload).
set_internal_state :: proc(state: ^State)

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
open_url :: proc(url: string) -> Open_URL_Error

//--------------//
// EXPERIMENTAL //
//--------------//
//
// These procedures are experimental and may not stay.

// The witdth a button drawn using `ui_button` will have
ui_button_width :: proc(text: string, button_height: f32) -> f32

// Experimental UI button. Returns true if the button was pressed. `r` is in the space of whatever
// camera is currently set (see `set_camera`), same as any other drawing call.
//
// A left click presses it, and so does a tap, so it works on a touch screen with no mouse at all.
//
// Mainly used by the samples in order to create the "Source" button. As this is experimental, you
// are probably better off copying this procedure to your own code and modifying it, rather than
// using it as-is.
ui_button :: proc(r: Rect, text: string) -> bool

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

color_alpha :: proc(c: Color, a: u8) -> Color

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

MAX_OGG_PAGE_SIZE :: 65307

AUDIO_STREAM_READ_BUF_SIZE :: 2 * MAX_OGG_PAGE_SIZE

AUDIO_STREAM_READ_SIZE :: 4096

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

	decode_mutex: sync.Mutex,

	stop_requested: bool,

	rewind_requested: bool,

	needs_refill: bool,

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
	file_read_buf: []u8,

	file_read_buf_len: int,
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
// TODO-UPDATE-COMMENT `len(samples)` is now whatever buffer size the backend asked for, and this
// runs on the thread the backend mixes on rather than on the main thread.
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

	touches: [dynamic; MAX_TOUCHES]Touch,

	// See `set_touch_events_from_mouse`.
	touch_events_from_mouse: bool,

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

	// TODO-UPDATE-COMMENT only the backends that are handed samples use this. A backend that mixes
	// itself has the mixer write straight into the buffer its device is about to play.
	// Mixer will never mix in more than 1.5 * AUDIO_MIX_CHUNK_SIZE. So 10 times the chunk size is
	// ample.
	mix_buffer: [AUDIO_MIX_CHUNK_SIZE*10][2]Audio_Sample,

	// Where the mixer currently is in the mix buffer.
	mix_buffer_offset: int,

	audio_mutex: sync.Mutex,

	audio_thread_logger: runtime.Logger,
}

// Karl2D currently reports left, right, and middle mouse buttons.
// `Max` defines the upper bound of the `Mouse_Button` enum.
Mouse_Button :: enum {
	Left,
	Right,
	Middle,
	Max = 255,
}

// The maximum number of touches Karl2D tracks at once. Ten fingers, plus the one
// `set_touch_events_from_mouse` makes from the mouse.
MAX_TOUCHES :: 11

// Identifies one finger for as long as it stays on the screen. Stable from the moment the touch
// goes down until it goes up. Ids may be reused after that.
Touch_Id :: distinct u64

// The id of the touch synthesized by `set_touch_events_from_mouse`. Never collides with a real id.
EMULATED_TOUCH_ID :: max(Touch_Id)

Touch :: struct {
	id: Touch_Id,

	// Measured from the top-left corner of the window, like `get_mouse_position`.
	position: Vec2,

	// How many pixels the touch moved between the previous and the current frame.
	delta: Vec2,

	// The touch started this frame.
	went_down: bool,

	// The touch ended this frame. It stays in the list for this one frame, so you can react to it.
	went_up: bool,

	// The OS threw the touch away, for example due to palm rejection or the window losing focus.
	// `went_up` is set as well, so code that doesn't care about the difference still works.
	cancelled: bool,
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
	Event_Touch_Went_Down,
	Event_Touch_Moved,
	Event_Touch_Went_Up,
	Event_Touch_Cancelled,
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

Event_Touch_Went_Down :: struct { id: Touch_Id, position: Vec2 }
Event_Touch_Moved     :: struct { id: Touch_Id, position: Vec2 }
Event_Touch_Went_Up   :: struct { id: Touch_Id, position: Vec2 }

// No position: not every platform knows where a cancelled touch was. The touch keeps the last
// position it was seen at.
Event_Touch_Cancelled :: struct { id: Touch_Id }
