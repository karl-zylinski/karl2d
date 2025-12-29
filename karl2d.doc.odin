// This file is purely documentational. It is generated from the contents of 'karl2d.odin'.
#+build ignore
package karl2d

//-----------------------------------------------//
// SETUP, WINDOW MANAGEMENT AND FRAME MANAGEMENT //
//-----------------------------------------------//

// Opens a window and initializes some internal state. The internal state will use `allocator` for
// all dynamically allocated memory. The return value can be ignored unless you need to later call
// `set_internal_state`.
init :: proc(window_width: int, window_height: int, window_title: string,
            window_creation_flags := Window_Flags {},
            allocator := context.allocator, loc := #caller_location) -> ^State

// Returns true the user has pressed the close button on the window, or used a key stroke such as
// ALT+F4 on Windows. The application can decide if it wants to shut down or if it wants to show
// some kind of confirmation dialogue.
//
// Commonly used for creating the "main loop" of a game: `for !k2.shutdown_wanted {}`
shutdown_wanted :: proc() -> bool

// Closes the window and cleans up Karl2D's internal state.
shutdown :: proc()

// Clear the "screen" with the supplied color. By default this will clear your window. But if you
// have set a Render Texture using the `set_render_texture` procedure, then that Render Texture will
// be cleared instead.
clear :: proc(color: Color)

// Call at the start of each frame. This procedure does two main things:
// - Fetches how long the previous frame took and how long since the program started. These values
//   can be fetched using `get_frame_time()` and `get_time()`
// - Clears Karl2D's internal "frame_allocator" -- that's the allocator the library uses for
//   dynamic memory that has a lifetime of a single frame.
new_frame :: proc()

// "Flips the backbuffer": Call at end of frame to make everything you've drawn appear on the screen.
//
// When you draw using for example `draw_texture`, then that stuff is drawn to an invisible texture
// called a "backbuffer". This makes sure that we don't see half-drawn frames. So when you are happy
// with a frame and want to show it to the player, call this procedure.
//
// WebGL note: WebGL does the backbuffer flipping automatically. But you should still call this to
// make sure that all rendering has been sent off to the GPU (it calls `draw_current_batch()`).
present :: proc()

// Call at start or end of frame to process all events that have arrived to the window. This
// includes keyboard, mouse, gamepad and window events.
//
// WARNING: Not calling this will make your program impossible to interact with.
process_events :: proc()

// Returns how many seconds the previous frame took. Often a tiny number such as 0.016 s.
//
// You must call `new_frame()` at the start of your frame in order for the frame_time to be updated.
get_frame_time :: proc() -> f32

// Returns how many seconds has elapsed since the game started.
//
// You must call `new_frame()` at the start of your frame for this value to get updated.
get_time :: proc() -> f64

// Gets the width of the drawing area within the window. The returned number is not scaled by any
// monitor DPI scaling. You do that manually using the number returned by `get_window_scale()`.
get_screen_width :: proc() -> int

// Gets the height of the drawing area within the window. The returned number is not scaled by any
// monitor DPI scaling. You do that manually using the number returned by `get_window_scale()`.
get_screen_height :: proc() -> int

// Moves the window.
//
// WebGL note: This moves the canvas within the window, which may not be what you want.
set_window_position :: proc(x: int, y: int)

// Resize the window to a new size. If the window has the flag Resizable set, then the backbuffer
// will also be resized.
set_window_size :: proc(width: int, height: int)

// Fetch the scale of the window. This usually comes from some DPI scaling setting in the OS.
// 1 means 100% scale, 1.5 means 150% etc.
get_window_scale :: proc() -> f32

// These are the same kind of flags that you can send to `init`.
set_window_flags :: proc(flags: Window_Flags)

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
draw_current_batch :: proc()

//-------//
// INPUT //
//-------//

// Returns true if a keyboard key went down between the current and the previous frame. Set when
// 'process_events' runs.
key_went_down :: proc(key: Keyboard_Key) -> bool

// Returns true if a keyboard key went up (was released) between the current and the previous frame.
// Set when 'process_events' runs.
key_went_up :: proc(key: Keyboard_Key) -> bool

// Returns true if a keyboard is currently being held down. Set when 'process_events' runs.
key_is_held :: proc(key: Keyboard_Key) -> bool

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
get_mouse_wheel_delta :: proc() -> f32

// Returns the mouse position, measured from the top-left corner of the window.
get_mouse_position :: proc() -> Vec2

// Returns how many pixels the mouse moved between the previous and the current frame.
get_mouse_delta :: proc() -> Vec2

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
draw_rect :: proc(r: Rect, c: Color)

// Creates a rectangle from a position and a size and draws it.
draw_rect_vec :: proc(pos: Vec2, size: Vec2, c: Color)

// Draw a rectangle with a custom origin and rotation.
//
// The origin says which point the rotation rotates around. If the origin is `(0, 0)`, then the
// rectangle rotates around the top-left corner of the rectangle. If it is `(rect.w/2, rect.h/2)`
// then the rectangle rotates around its center.
draw_rect_ex :: proc(r: Rect, origin: Vec2, rot: f32, c: Color)

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

// Draw a texture at a specific position. The texture will be drawn with its top-left corner at
// position `pos`.
//
// Load textures using `load_texture_from_file` or `load_texture_from_bytes`.
draw_texture :: proc(tex: Texture, pos: Vec2, tint := WHITE)

// Draw a section of a texture at a specific position. `rect` is a rectangle measured in pixels. It
// tells the procedure which part of the texture to display. The texture will be drawn with its
// top-left corner at position `pos`.
draw_texture_rect :: proc(tex: Texture, rect: Rect, pos: Vec2, tint := WHITE)

// Draw a texture by taking a section of the texture specified by `src` and draw it into the area of
// the screen specified by `dst`. You can also rotate the texture around an origin point of your
// choice.
//
// Tip: Use `k2.get_texture_rect(tex)` for `src` if you want to draw the whole texture.
draw_texture_ex :: proc(tex: Texture, src: Rect, dst: Rect, origin: Vec2, rotation: f32, tint := WHITE)

// Tells you how much space some text of a certain size will use on the screen. The font used is the
// default font. The return value contains the width and height of the text.
measure_text :: proc(text: string, font_size: f32) -> Vec2

// Tells you how much space some text of a certain size will use on the screen, using a custom font.
// The return value contains the width and height of the text.
measure_text_ex :: proc(font_handle: Font_Handle, text: string, font_size: f32) -> Vec2

// Draw text at a position with a size. This uses the default font. `pos` will be equal to the 
// top-left position of the text.
draw_text :: proc(text: string, pos: Vec2, font_size: f32, color := BLACK)

// Draw text at a position with a size, using a custom font. `pos` will be equal to the  top-left
// position of the text.
draw_text_ex :: proc(font_handle: Font_Handle, text: string, pos: Vec2, font_size: f32, color := BLACK)

//--------------------//
// TEXTURE MANAGEMENT //
//--------------------//

// Create an empty texture.
create_texture :: proc(width: int, height: int, format: Pixel_Format) -> Texture

// Load a texture from disk and upload it to the GPU so you can draw it to the screen.
// Supports PNG, BMP, TGA and baseline PNG. Note that progressive PNG files are not supported!
//
// The `options` parameter can be used to specify things things such as premultiplication of alpha.
load_texture_from_file :: proc(filename: string, options: Load_Texture_Options = {}) -> Texture

// Load a texture from a byte slice and upload it to the GPU so you can draw it to the screen.
// Supports PNG, BMP, TGA and baseline PNG. Note that progressive PNG files are not supported!
//
// The `options` parameter can be used to specify things things such as premultiplication of alpha.
load_texture_from_bytes :: proc(bytes: []u8, options: Load_Texture_Options = {}) -> Texture

// Load raw texture data. You need to specify the data, size and format of the texture yourself.
// This assumes that there is no header in the data. If your data has a header (you read the data
// from a file on disk), then please use `load_texture_from_bytes` instead.
load_texture_from_bytes_raw :: proc(bytes: []u8, width: int, height: int, format: Pixel_Format) -> Texture

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

//-----------------//
// RENDER TEXTURES //
//-----------------//

// Create a texture that you can render into. Meaning that you can draw into it instead of drawing
// onto the screen. Use `set_render_texture` to enable this Render Texture for drawing.
create_render_texture :: proc(width: int, height: int) -> Render_Texture

// Destroy a Render_Texture previously created using `create_render_texture`.
destroy_render_texture :: proc(render_texture: Render_Texture)

// Make all rendering go into a texture instead of onto the screen. Create the render texture using
// `create_render_texture`. Pass `nil` to resume drawing onto the screen.
set_render_texture :: proc(render_texture: Maybe(Render_Texture))

//-------//
// FONTS //
//-------//
load_font_from_file :: proc(filename: string) -> Font_Handle

load_font_from_bytes :: proc(data: []u8) -> Font_Handle

destroy_font :: proc(font: Font_Handle)

get_default_font :: proc() -> Font_Handle

//---------//
// SHADERS //
//---------//
load_shader_from_file :: proc(
	vertex_filename: string,
	fragment_filename: string,
	layout_formats: []Pixel_Format = {}
) -> Shader

load_shader_from_bytes :: proc(
	vertex_shader_bytes: []byte,
	fragment_shader_bytes: []byte,
	layout_formats: []Pixel_Format = {},
) -> Shader

destroy_shader :: proc(shader: Shader)

get_default_shader :: proc() -> Shader

set_shader :: proc(shader: Maybe(Shader))

set_shader_constant :: proc(shd: Shader, loc: Shader_Constant_Location, val: any)

override_shader_input :: proc(shader: Shader, input: int, val: any)

pixel_format_size :: proc(f: Pixel_Format) -> int

//-------------------------------//
// CAMERA AND COORDINATE SYSTEMS //
//-------------------------------//
set_camera :: proc(camera: Maybe(Camera))

screen_to_world :: proc(pos: Vec2, camera: Camera) -> Vec2

world_to_screen :: proc(pos: Vec2, camera: Camera) -> Vec2

get_camera_view_matrix :: proc(c: Camera) -> Mat4

get_camera_world_matrix :: proc(c: Camera) -> Mat4

//------//
// MISC //
//------//

// Choose how the alpha channel is used when mixing half-transparent color with what is already
// drawn. The default is the .Alpha mode, but you also have the option of using .Premultiply_Alpha.
set_blend_mode :: proc(mode: Blend_Mode)

set_scissor_rect :: proc(scissor_rect: Maybe(Rect))

// Restore the internal state using the pointer returned by `init`. Useful after reloading the
// library (for example, when doing code hot reload).
set_internal_state :: proc(state: ^State)

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

WHITE :: Color { 255, 255, 255, 255 }
BLACK :: Color { 0, 0, 0, 255 }
GRAY  :: Color { 127, 127, 127, 255 }
RED   :: Color { 198, 40, 90, 255 }
GREEN :: Color { 30, 240, 30, 255 }
YELLOW :: Color {240, 190, 0, 255 }
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
	Premultiplied_Alpha, // Requires the alpha-channel to be multiplied into texture RGB channels.
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
