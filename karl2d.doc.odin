// This file is purely documentational and never built.
#+ignore
package karl2d

Handle :: hm.Handle

Texture_Handle :: distinct Handle

TEXTURE_NONE :: Texture_Handle {}

// Opens a window and initializes some internal state. The internal state will use `allocator` for
// all dynamically allocated memory. The return value can be ignored unless you need to later call
// `set_state`.
init :: proc(window_width: int, window_height: int, window_title: string,
             allocator := context.allocator, loc := #caller_location) -> ^State

VERTEX_BUFFER_MAX :: 1000000

make_default_projection :: proc(w, h: int) -> matrix[4,4]f32

DEFAULT_SHADER_SOURCE :: #load("shader.hlsl")

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

/* Flushes the current batch. This sends off everything to the GPU that has been queued in the
current batch. Normally, you do not need to do this manually. It is done automatically when these
procedures run:
	present
	set_camera
	set_shader

TODO: complete this list and motivate why it needs to happen on those procs (or do that in the
docs for those procs).
*/
draw_current_batch :: proc()

// Can be used to restore the internal state using the pointer returned by `init`. Useful after
// reloading the library (for example, when doing code hot reload).
set_internal_state :: proc(state: ^State)

get_screen_width :: proc() -> int

get_screen_height :: proc() -> int

key_went_down :: proc(key: Keyboard_Key) -> bool

key_went_up :: proc(key: Keyboard_Key) -> bool

key_is_held :: proc(key: Keyboard_Key) -> bool

shutdown_wanted :: proc() -> bool

set_window_position :: proc(x: int, y: int)

set_window_size :: proc(width: int, height: int)

set_camera :: proc(camera: Maybe(Camera))

load_texture_from_file :: proc(filename: string) -> Texture

destroy_texture :: proc(tex: Texture)

draw_rect :: proc(r: Rect, c: Color)

draw_rect_ex :: proc(r: Rect, origin: Vec2, rot: f32, c: Color)

draw_rect_outline :: proc(r: Rect, thickness: f32, color: Color)

draw_circle :: proc(center: Vec2, radius: f32, color: Color, segments := 16)

draw_line :: proc(start: Vec2, end: Vec2, thickness: f32, color: Color)

draw_texture :: proc(tex: Texture, pos: Vec2, tint := WHITE)

draw_texture_rect :: proc(tex: Texture, rect: Rect, pos: Vec2, tint := WHITE)

draw_texture_ex :: proc(tex: Texture, src: Rect, dst: Rect, origin: Vec2, rotation: f32, tint := WHITE)

load_shader :: proc(shader_source: string, layout_formats: []Shader_Input_Format = {}) -> Shader

get_shader_input_default_type :: proc(name: string, type: Shader_Input_Type) -> Shader_Default_Inputs

get_shader_input_format :: proc(name: string, type: Shader_Input_Type) -> Shader_Input_Format

destroy_shader :: proc(shader: Shader)

set_shader :: proc(shader: Maybe(Shader))

maybe_handle_equal :: proc(m1: Maybe($T), m2: Maybe(T)) -> bool

set_shader_constant :: proc(shd: Shader, loc: Shader_Constant_Location, val: $T)

set_shader_constant_mat4 :: proc(shader: Shader, loc: Shader_Constant_Location, val: matrix[4,4]f32)

set_shader_constant_f32 :: proc(shader: Shader, loc: Shader_Constant_Location, val: f32)

set_shader_constant_vec2 :: proc(shader: Shader, loc: Shader_Constant_Location, val: Vec2)

get_default_shader :: proc() -> Shader

set_scissor_rect :: proc(scissor_rect: Maybe(Rect))

screen_to_world :: proc(pos: Vec2, camera: Camera) -> Vec2

draw_text :: proc(text: string, pos: Vec2, font_size: f32, color: Color)

mouse_button_went_down :: proc(button: Mouse_Button) -> bool

mouse_button_went_up :: proc(button: Mouse_Button) -> bool

mouse_button_is_held :: proc(button: Mouse_Button) -> bool

get_mouse_wheel_delta :: proc() -> f32

get_mouse_position :: proc() -> Vec2

_batch_vertex :: proc(v: Vec2, uv: Vec2, color: Color)

shader_input_format_size :: proc(f: Shader_Input_Format) -> int

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

