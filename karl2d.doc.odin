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

// Returns true if the program wants to shut down. This happens when for example pressing the close
// button on the window. The application can decide if it wants to shut down or if it wants to show
// some kind of confirmation dialogue and shut down later.
//
// Commonly used for creating the "main loop" of a game.
shutdown_wanted :: proc() -> bool

// Closes the window and cleans up the internal state.
shutdown :: proc()

// Clear the backbuffer with supplied color.
clear :: proc(color: Color)

// Present the backbuffer. Call at end of frame to make everything you've drawn appear on the screen.
present :: proc()

// Call at start or end of frame to process all events that have arrived to the window.
//
// WARNING: Not calling this will make your program impossible to interact with.
process_events :: proc()

get_screen_width :: proc() -> int

get_screen_height :: proc() -> int

set_window_position :: proc(x: int, y: int)

set_window_size :: proc(width: int, height: int)

set_window_flags :: proc(flags: Window_Flags)

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
draw_current_batch :: proc()

//-------//
// INPUT //
//-------//

// Returns true if a keyboard key went down between the current and the previous frame. Set when
// 'process_events' runs (probably once per frame).
key_went_down :: proc(key: Keyboard_Key) -> bool

// Returns true if a keyboard key went up (was released) between the current and the previous frame.
// Set when 'process_events' runs (probably once per frame).
key_went_up :: proc(key: Keyboard_Key) -> bool

// Returns true if a keyboard is currently being held down. Set when 'process_events' runs (probably
// once per frame).
key_is_held :: proc(key: Keyboard_Key) -> bool

mouse_button_went_down :: proc(button: Mouse_Button) -> bool

mouse_button_went_up :: proc(button: Mouse_Button) -> bool

mouse_button_is_held :: proc(button: Mouse_Button) -> bool

get_mouse_wheel_delta :: proc() -> f32

get_mouse_position :: proc() -> Vec2

gamepad_button_went_down :: proc(gamepad: int, button: Gamepad_Button) -> bool

gamepad_button_went_up :: proc(gamepad: int, button: Gamepad_Button) -> bool

gamepad_button_is_held :: proc(gamepad: int, button: Gamepad_Button) -> bool

//---------//
// DRAWING //
//---------//
draw_rect :: proc(r: Rect, c: Color)

draw_rect_ex :: proc(r: Rect, origin: Vec2, rot: f32, c: Color)

draw_rect_outline :: proc(r: Rect, thickness: f32, color: Color)

draw_circle :: proc(center: Vec2, radius: f32, color: Color, segments := 16)

draw_line :: proc(start: Vec2, end: Vec2, thickness: f32, color: Color)

draw_texture :: proc(tex: Texture, pos: Vec2, tint := WHITE)

draw_texture_rect :: proc(tex: Texture, rect: Rect, pos: Vec2, tint := WHITE)

draw_texture_ex :: proc(tex: Texture, src: Rect, dst: Rect, origin: Vec2, rotation: f32, tint := WHITE)

draw_text :: proc(text: string, pos: Vec2, font_size: f32, color: Color)

//--------------------//
// TEXTURE MANAGEMENT //
//--------------------//
load_texture_from_file :: proc(filename: string) -> Texture

destroy_texture :: proc(tex: Texture)

//---------//
// SHADERS //
//---------//
load_shader :: proc(shader_source: string, layout_formats: []Pixel_Format = {}) -> Shader

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
	format: Pixel_Format,
}

Shader_Constant_Location :: struct {
	buffer_idx: u32,
	offset: u32,
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
}

Handle :: hm.Handle
Texture_Handle :: distinct Handle
TEXTURE_NONE :: Texture_Handle {}

MAX_GAMEPADS :: 4

// This keeps track of the internal state of the library. Usually, you do not need to poke at it.
// It is created and kept as a global variable when 'init' is called. However, 'init' also returns
// the pointer to it, so you can later use 'set_internal_state' to restore it (after for example hot
// reload).
State :: struct {
	allocator: runtime.Allocator,
	custom_context: runtime.Context,
	win: Window_Interface,
	window_state: rawptr,
	rb: Render_Backend_Interface,
	rb_state: rawptr,
	
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
	width: int,
	height: int,

	shape_drawing_texture: Texture_Handle,
	batch_camera: Maybe(Camera),
	batch_shader: Maybe(Shader),
	batch_scissor: Maybe(Rect),
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
