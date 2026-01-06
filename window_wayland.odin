#+build linux
#+private file

package karl2d

@(private="package")
WINDOW_INTERFACE_WAYLAND :: Window_Interface {
	state_size = wayland_state_size,
	init = wayland_init,
	shutdown = wayland_shutdown,
	window_handle = wayland_window_handle,
	process_events = wayland_process_events,
	get_events = wayland_get_events,
	get_width = wayland_get_width,
	get_height = wayland_get_height,
	clear_events = wayland_clear_events,
	set_position = wayland_set_position,
	set_size = wayland_set_size,
	get_window_scale = wayland_get_window_scale,
	set_window_mode = wayland_set_window_mode,
	is_gamepad_active = wayland_is_gamepad_active,
	get_gamepad_axis = wayland_get_gamepad_axis,
	set_gamepad_vibration = wayland_set_gamepad_vibration,
	set_internal_state = wayland_set_internal_state,
}

import "base:runtime"
import "core:log"
import "core:fmt"
import wl "linux/wayland"

_ :: log
_ :: fmt

wayland_state_size :: proc() -> int {
	return size_of(Wayland_State)
}

wayland_init :: proc(
	window_state: rawptr,
	window_width: int,
	window_height: int,
	window_title: string,
	init_options: Init_Options,
	allocator: runtime.Allocator,
) {
	s = (^Wayland_State)(window_state)
	s.allocator = allocator
	s.windowed_width = window_width
	s.windowed_height = window_height

	s.window_handle = Window_Handle_Linux_Wayland {
		// display = s.display,
		// screen = X.DefaultScreen(s.display),
		// window = s.window,
	}

	wayland_set_window_mode(init_options.window_mode)
}

wayland_shutdown :: proc() {
	// X.DestroyWindow(s.display, s.window)
}

wayland_window_handle :: proc() -> Window_Handle {
	return Window_Handle(&s.window_handle)
}

wayland_process_events :: proc() {
}

@rodata
KEY_FROM_XKEYCODE := [255]Keyboard_Key {
	8 = .Space,
	9 = .Escape,
	10 = .N1,
	11 = .N2,
	12 = .N3,
	13 = .N4,
	14 = .N5,
	15 = .N6,
	16 = .N7,
	17 = .N8,
	18 = .N9,
	19 = .N0,
	20 = .Minus,
	21 = .Equal,
	22 = .Backspace,
	23 = .Tab,
	24 = .Q,
	25 = .W,
	26 = .E,
	27 = .R,
	28 = .T,
	29 = .Y,
	30 = .U,
	31 = .I,
	32 = .O,
	33 = .P,
	34 = .Left_Bracket,
	35 = .Right_Bracket,
	36 = .Enter,
	37 = .Left_Control,
	38 = .A,
	39 = .S,
	40 = .D,
	41 = .F,
	42 = .G,
	43 = .H,
	44 = .J,
	45 = .K,
	46 = .L,
	47 = .Semicolon,
	48 = .Apostrophe,
	49 = .Backtick,
	50 = .Left_Shift,
	51 = .Backslash,
	52 = .Z,
	53 = .X,
	54 = .C,
	55 = .V,
	56 = .B,
	57 = .N,
	58 = .M,
	59 = .Comma,
	60 = .Period,
	61 = .Slash,
	62 = .Right_Shift,
	63 = .NP_Multiply,
	64 = .Left_Alt,
	65 = .Space,
	66 = .Caps_Lock,
	67 = .F1,
	68 = .F2,
	69 = .F3,
	70 = .F4,
	71 = .F5,
	72 = .F6,
	73 = .F7,
	74 = .F8,
	75 = .F9,
	76 = .F10,
	77 = .Num_Lock,
	78 = .Scroll_Lock,
	82 = .NP_Subtract,
	86 = .NP_Add,
	95 = .F11,
	96 = .F12,
	104 = .NP_Enter,
	105 = .Right_Control,
	106 = .NP_Divide,
	107 = .Print_Screen,
	108 = .Right_Alt,
	110 = .Home,
	111 = .Up,
	112 = .Page_Up,
	113 = .Left,
	114 = .Right,
	115 = .End,
	116 = .Down,
	117 = .Page_Down,
	118 = .Insert,
	119 = .Delete,
	125 = .NP_Equal,
	127 = .Pause,
	129 = .NP_Decimal,
	133 = .Left_Super,
	134 = .Right_Super,
	135 = .Menu,
}

key_from_xkeycode :: proc(kc: u32) -> Keyboard_Key {
	if kc >= 255 {
		return .None
	}

	return KEY_FROM_XKEYCODE[u8(kc)]
}

wayland_get_events :: proc() -> []Window_Event {
	return s.events[:]
}

wayland_get_width :: proc() -> int {
	return s.width
}

wayland_get_height :: proc() -> int {
	return s.height
}

wayland_clear_events :: proc() {
	runtime.clear(&s.events)
}

wayland_set_position :: proc(x: int, y: int) {
}

wayland_set_size :: proc(w, h: int) {
}

wayland_get_window_scale :: proc() -> f32 {
	return 1
}

enter_borderless_fullscreen :: proc() {
}

leave_borderless_fullscreen :: proc() {
}

wayland_set_window_mode :: proc(window_mode: Window_Mode) {
}

wayland_is_gamepad_active :: proc(gamepad: int) -> bool {
	if gamepad < 0 || gamepad >= MAX_GAMEPADS {
		return false
	}

	return false
}

wayland_get_gamepad_axis :: proc(gamepad: int, axis: Gamepad_Axis) -> f32 {
	if gamepad < 0 || gamepad >= MAX_GAMEPADS {
		return 0
	}

	return 0
}

wayland_set_gamepad_vibration :: proc(gamepad: int, left: f32, right: f32) {
	if gamepad < 0 || gamepad >= MAX_GAMEPADS {
		return
	}
}

wayland_set_internal_state :: proc(state: rawptr) {
	assert(state != nil)
	s = (^Wayland_State)(state)
}

Wayland_State :: struct {
	allocator: runtime.Allocator,
	width: int,
	height: int,
	windowed_width: int,
	windowed_height: int,
	events: [dynamic]Window_Event,
	display: ^wl.wl_display,
	compositor: ^wl.wl_compositor,
	xdg_base: ^wl.xdg_wm_base,
	window_handle: Window_Handle_Linux,
	window_mode: Window_Mode,
}

s: ^Wayland_State

@(private="package")
Window_Handle_Linux_Wayland :: struct {
	// display: ^X.Display,
	// window: X.Window,
	// screen: i32,
}

