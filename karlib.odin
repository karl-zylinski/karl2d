package karlib

// Opens a window and initializes some internal state. The internal state will use `allocator` for
// all dynamically allocated memory. The return value can be ignored unless you need to later call
// `set_state`.
init: proc(window_width: int, window_height: int, window_title: string,
           allocator := context.allocator, loc := #caller_location) -> ^State : _init

// Closes the window and cleans up the internal state.
shutdown: proc() : _shutdown

// Clear the backbuffer with supplied color.
clear: proc(color: Color) : _clear

// Call at start or end of frame to process all events that have arrived to the window.
//
// WARNING: Not calling this will make your program impossible to interact with.
process_events: proc() : _process_events

// Present the backbuffer. Call at end of frame to make everything you've drawn appear on the screen.
present: proc(do_flush := true) : _present

window_should_close : proc() -> bool : _window_should_close

// Can be used to restore the internal state using the pointer returned by `init`. Useful after
// reloading the library (for example, when doing code hot reload).
set_internal_state: proc(ks: ^State) : _set_internal_state

set_window_size: proc(width: int, height: int) : _set_window_size
set_window_position: proc(x: int, y: int) : _set_window_position

get_screen_width: proc() -> int : _get_screen_width
get_screen_height: proc() -> int : _get_screen_height

load_texture_from_file: proc(filename: string) -> Texture : _load_texture
// load_texture_from_bytes or buffer or something ()
destroy_texture: proc(tex: Texture) : _destroy_texture

set_camera: proc(camera: Maybe(Camera)) : _set_camera
set_scissor_rect: proc(scissor_rect: Maybe(Rect)) : _set_scissor_rect

draw_texture: proc(tex: Texture, pos: Vec2, tint := WHITE) : _draw_texture
draw_texture_rect: proc(tex: Texture, rect: Rect, pos: Vec2, tint := WHITE) : _draw_texture_rect
draw_texture_ex: proc(tex: Texture, src: Rect, dest: Rect, origin: Vec2, rotation: f32, tint := WHITE) : _draw_texture_ex
draw_rect: proc(rect: Rect, color: Color) : _draw_rectangle
draw_rect_outline: proc(rect: Rect, thickness: f32, color: Color) : _draw_rectangle_outline
draw_circle: proc(center: Vec2, radius: f32, color: Color) : _draw_circle
draw_line: proc(start: Vec2, end: Vec2, thickness: f32, color: Color) : _draw_line

// WARNING: Not proper text rendering yet... No font support etc
draw_text: proc(text: string, pos: Vec2, font_size: f32, color: Color) : _draw_text

screen_to_world: proc(pos: Vec2, camera: Camera) -> Vec2 : _screen_to_world

key_went_down: proc(key: Keyboard_Key) -> bool : _key_pressed
key_went_up: proc(key: Keyboard_Key) -> bool : _key_released
key_is_held: proc(key: Keyboard_Key) -> bool : _key_held

mouse_button_went_down: proc(button: Mouse_Button) -> bool : _mouse_button_pressed
mouse_button_went_up: proc(button: Mouse_Button) -> bool : _mouse_button_released
mouse_button_is_held: proc(button: Mouse_Button) -> bool : _mouse_button_held
get_mouse_wheel_delta: proc() -> f32 : _mouse_wheel_delta
get_mouse_position: proc() -> Vec2 : _mouse_position

Color :: [4]u8

Vec2 :: [2]f32

Vec2i :: [2]int

Rect :: struct {
	x, y: f32,
	w, h: f32,
}

Texture_Handle :: distinct int

Texture :: struct {
	id: Texture_Handle,
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