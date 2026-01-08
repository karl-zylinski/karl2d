#+build linux
#+private file

package karl2d

import "core:strings"
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
import "core:c"
import wl "linux/wayland"
import egl "vendor:egl"

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

	s.width = window_width
	s.height = window_height

	// We need to instantiate this so we can register the top level toplevel_listener
	// It will be there that we deal with resizing
	s.window_handle = Window_Handle_Linux_Wayland {
		ready = false,
	}

	display := wl.display_connect(nil)
	s.display = display

	// Get registry, add a global listener and get things started
	// Do a roundtrip in order to get registry info and populate the wayland part of state
	registry := wl.wl_display_get_registry(display)
	wl.wl_registry_add_listener(registry, &registry_listener, s)
	wl.display_roundtrip(display)

	// Configure seat listener responsible for things like mouse and keyboard input
	wl.wl_seat_add_listener(s.seat, &seat_listener, nil)

	// Create the surface
	surface := wl.wl_compositor_create_surface(s.compositor)
	if surface == nil {
		panic("Error creating wl_surface")
	}
	s.surface = surface

	// Register the listener to respond to pings
	// Without this the compositor will consider the window/client dead and 
	// try to kill it as an unresponsive application
	wl.xdg_wm_base_add_listener(s.xdg_base, &wm_base_listener, nil)

	// Create a XDG surface (i.e a Window...) and set the role top
	// "top-level" and add the listeners
	xdg_surface := wl.xdg_wm_base_get_xdg_surface(s.xdg_base, surface)
	toplevel := wl.xdg_surface_get_toplevel(xdg_surface)
	s.toplevel = toplevel
	wl.xdg_toplevel_add_listener(toplevel, &toplevel_listener, nil)
	wl.xdg_surface_add_listener(xdg_surface, &window_listener, nil)
	wl.xdg_toplevel_set_title(toplevel, strings.clone_to_cstring(window_title))
    decoration := wl.zxdg_decoration_manager_v1_get_toplevel_decoration(s.decoration, toplevel)
    wl.zxdg_toplevel_decoration_v1_set_mode(decoration, wl.ZXDG_TOPLEVEL_DECORATION_V1_MODE_SERVER_SIDE)

	wl.wl_surface_commit(surface)
	wl.display_dispatch(s.display)

	wl_callback := wl.wl_surface_frame(surface)
	wl.wl_callback_add_listener(wl_callback, &frame_callback, nil)

	egl_window := wl.egl_window_create(surface, i32(s.windowed_width), i32(s.windowed_height))

	whl := &s.window_handle.(Window_Handle_Linux_Wayland) 
	whl.redraw = true
	whl.display = display
	whl.surface = surface
	whl.egl_window = egl_window

	// whl.egl_display = egl_display
	// whl.egl_config = egl_config
	// whl.egl_surface = egl_surface
	// whl.egl_context = egl_context

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
	w := i32(s.windowed_width) 
	h := i32(s.windowed_height) 
	wl.xdg_toplevel_set_max_size(s.toplevel, w, h)
	wl.xdg_toplevel_set_min_size(s.toplevel, w, h)
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
	seat: ^wl.wl_seat,
	surface: ^wl.wl_surface,
	toplevel: ^wl.xdg_toplevel,
    decoration: ^wl.zxdg_decoration_manager_v1,
	window_handle: Window_Handle_Linux,
	window_mode: Window_Mode,
}

s: ^Wayland_State

@(private="package")
Window_Handle_Linux_Wayland :: struct {
	ready: bool,
	redraw: bool,
	display: ^wl.wl_display,
	surface: ^wl.wl_surface,
	egl_display: egl.Display,
	egl_window: ^wl.egl_window,
	egl_surface: egl.Surface,
	egl_config: egl.Config,
	egl_context: egl.Context,
	// window: X.Window,
	// screen: i32,
}

registry_listener := wl.wl_registry_listener {
	global        = global,
	global_remove = global_remove,
}

display_listener := wl.wl_display_listener{}


global :: proc "c" (
	data: rawptr,
	registry: ^wl.wl_registry,
	name: c.uint32_t,
	interface: cstring,
	version: c.uint32_t,
) {
	if interface == wl.wl_compositor_interface.name {
		state: ^Wayland_State = cast(^Wayland_State)data
		state.compositor = cast(^wl.wl_compositor)(wl.wl_registry_bind(
				registry,
				name,
				&wl.wl_compositor_interface,
				version,
			))
	}

	if interface == wl.xdg_wm_base_interface.name {
		state: ^Wayland_State = cast(^Wayland_State)data
		state.xdg_base = cast(^wl.xdg_wm_base)(wl.wl_registry_bind(
				registry,
				name,
				&wl.xdg_wm_base_interface,
				version,
			))
	}
	if interface == wl.wl_seat_interface.name {
		state: ^Wayland_State = cast(^Wayland_State)data
		state.seat = cast(^wl.wl_seat)(wl.wl_registry_bind(
				registry,
				name,
				&wl.wl_seat_interface,
				version,
			))
	}
	if interface == wl.zxdg_decoration_manager_v1_interface.name {
		state: ^Wayland_State = cast(^Wayland_State)data
		state.decoration = cast(^wl.zxdg_decoration_manager_v1)(wl.wl_registry_bind(
				registry,
				name,
				&wl.zxdg_decoration_manager_v1_interface,
				version,
			))
	}
}

global_remove :: proc "c" (data: rawptr, registry: ^wl.wl_registry, name: c.uint32_t) {
}

done :: proc "c" (data: rawptr, wl_callback: ^wl.wl_callback, callback_data: c.uint32_t) {
	wh := s.window_handle.(Window_Handle_Linux_Wayland)
	wh.redraw = true
	s.window_handle = wh

	wl.wl_callback_destroy(wl_callback)
}

window_listener := wl.xdg_surface_listener {
	configure = proc "c" (data: rawptr, surface: ^wl.xdg_surface, serial: c.uint32_t) {
		// context = runtime.default_context()
		// fmt.println("window configure")
		wl.xdg_surface_ack_configure(surface, serial)
		wl.wl_surface_damage(s.surface, 0, 0, i32(s.width), i32(s.height))
		wl.wl_surface_commit(s.surface)
	},
}

toplevel_listener := wl.xdg_toplevel_listener {
	configure = proc "c" (
		data: rawptr,
		xdg_toplevel: ^wl.xdg_toplevel,
		width: c.int32_t,
		height: c.int32_t,
		states: ^wl.wl_array,
	) {
		context = runtime.default_context()
		// fmt.println("top level configure")
		sw := i32(s.windowed_width)
		sh := i32(s.windowed_height)
		whl := s.window_handle.(Window_Handle_Linux_Wayland)
		if (sw != width || sh != height) && (sw > 0 && sh > 0) && (whl.ready) {
			fmt.println(width, height)
			wl.egl_window_resize(whl.egl_window, c.int(width), c.int(height), 0, 0)
			s.windowed_width = int(width)
			s.windowed_height = int(height)
			s.width = int(width)
			s.height = int(height)
			/// SHOULD EMIT A VALID WINDOW EVENT
			// append(
			// 	&cc.platform_state.input.events,
			// 	WindowResize{new_width = width, new_height = height},
			// )
		}
		whl.ready = true
		s.window_handle = whl
	},
	close = proc "c" (data: rawptr, xdg_toplevel: ^wl.xdg_toplevel) {},
	configure_bounds = proc "c" (data: rawptr, xdg_toplevel: ^wl.xdg_toplevel, width: c.int32_t, height: c.int32_t,) { },
	wm_capabilities = proc "c" (data: rawptr, xdg_toplevel: ^wl.xdg_toplevel, capabilities: ^wl.wl_array,) {},
}

wm_base_listener := wl.xdg_wm_base_listener {
	ping = proc "c" (data: rawptr, xdg_wm_base: ^wl.xdg_wm_base, serial: c.uint32_t) {
		wl.xdg_wm_base_pong(xdg_wm_base, serial)
	},
}

@(private="package")
frame_callback := wl.wl_callback_listener {
	done = done,
}

seat_listener := wl.wl_seat_listener {
	capabilities = proc "c" (data: rawptr, wl_seat: ^wl.wl_seat, capabilities: c.uint32_t) {
		context = runtime.default_context()
		pointer := wl.wl_seat_get_pointer(s.seat)
		wl.wl_pointer_add_listener(pointer, &pointer_listener, nil)
		keyboard := wl.wl_seat_get_keyboard(s.seat)
		wl.wl_keyboard_add_listener(keyboard, &keyboard_listener, nil)
	},
	name = proc "c" (data: rawptr, wl_seat: ^wl.wl_seat, name: cstring) {},
}

keyboard_listener := wl.wl_keyboard_listener {
	keymap = proc "c" (data: rawptr, keyboard: ^wl.wl_keyboard, format: c.uint32_t, fd: c.int32_t, size: c.uint32_t,) {},
	enter = proc "c" (data: rawptr, keyboard: ^wl.wl_keyboard, serial: c.uint32_t, surface: ^wl.wl_surface, keys: ^wl.wl_array) {},
	leave = proc "c" (data: rawptr, keyboard: ^wl.wl_keyboard, serial: c.uint32_t, surface: ^wl.wl_surface) {},
	key = key_handler,
	modifiers = proc "c" (
		data: rawptr,
		wl_keyboard: ^wl.wl_keyboard,
		serial: c.uint32_t,
		mods_depressed: c.uint32_t,
		mods_latched: c.uint32_t,
		mods_locked: c.uint32_t,
		group: c.uint32_t,
	) {
	},
	repeat_info = proc "c" (
		data: rawptr,
		wl_keyboard: ^wl.wl_keyboard,
		rate: c.int32_t,
		delay: c.int32_t,
	) {},
}

key_handler :: proc "c" (
	data: rawptr,
	keyboard: ^wl.wl_keyboard,
	serial: c.uint32_t,
	t: c.uint32_t,
	key: c.uint32_t,
	state: c.uint32_t,
) {
	context = runtime.default_context()

	// Wayland emits evdev events, and the keycodes are shifted 
	// from the expected xkb events... Just add 8 to it.
	keycode := key + 8

	if state == 0 {
		key := key_from_xkeycode(keycode)

		if key != .None {
			append(&s.events, Window_Event_Key_Went_Up {
				key = key,
			})
		}
	}

	if state == 1 {
		key := key_from_xkeycode(keycode)

		if key != .None {
			append(&s.events, Window_Event_Key_Went_Down {
				key = key,
			})
		}
	}
}

pointer_listener := wl.wl_pointer_listener {
	enter = proc "c" (
		data: rawptr,
		wl_pointer: ^wl.wl_pointer,
		serial: c.uint32_t,
		surface: ^wl.wl_surface,
		surface_x: wl.wl_fixed_t,
		surface_y: wl.wl_fixed_t,
	) {
	},
	leave = proc "c" (
		data: rawptr,
		wl_pointer: ^wl.wl_pointer,
		serial: c.uint32_t,
		surface: ^wl.wl_surface,
	) {
	},
	motion = proc "c" (
		data: rawptr,
		wl_pointer: ^wl.wl_pointer,
		time: c.uint32_t,
		surface_x: wl.wl_fixed_t,
		surface_y: wl.wl_fixed_t,
	) {
		context = runtime.default_context()
		// surface_x and surface_y are fixed point 24.8 variables. 
		// Just bitshift them to remove the decimal part and obtain 
		// a screen coordinate
		append(&s.events, Window_Event_Mouse_Move {
			position = { f32(surface_x >> 8), f32(surface_y >> 8) }, 
		})
	},
	button = proc "c" (
		data: rawptr,
		wl_pointer: ^wl.wl_pointer,
		serial: c.uint32_t,
		time: c.uint32_t,
		button: c.uint32_t,
		state: c.uint32_t,
	) {
		context = runtime.default_context()

		btn: Mouse_Button
		switch button {
		case 0: btn = .Left
		case 1: btn = .Middle
		case 2: btn = .Right
		}
	
		switch state {
		case 0:
			append(&s.events, Window_Event_Mouse_Button_Went_Up {
				button = btn,
			})
		case 1: 
			append(&s.events, Window_Event_Mouse_Button_Went_Down {
				button = btn,
			})
		}
	},
	axis = proc "c" (
		data: rawptr,
		wl_pointer: ^wl.wl_pointer,
		time: c.uint32_t,
		axis: c.uint32_t,
		value: wl.wl_fixed_t,
	) {
		context = runtime.default_context()
		event_direction: f32 = value > 0 ? 1 : -1
		append(&s.events, Window_Event_Mouse_Wheel {
			delta = event_direction,
		})
	},
	frame = proc "c" (data: rawptr, wl_pointer: ^wl.wl_pointer) {},
	axis_source = proc "c" (data: rawptr, wl_pointer: ^wl.wl_pointer, axis_source: c.uint32_t) {},
	axis_stop = proc "c" (
		data: rawptr,
		wl_pointer: ^wl.wl_pointer,
		time: c.uint32_t,
		axis: c.uint32_t,
	) {},
	axis_discrete = proc "c" (
		data: rawptr,
		wl_pointer: ^wl.wl_pointer,
		axis: c.uint32_t,
		discrete: c.int32_t,
	) {},
	axis_value120 = proc "c" (
		data: rawptr,
		wl_pointer: ^wl.wl_pointer,
		axis: c.uint32_t,
		value120: c.int32_t,
	) {},
	axis_relative_direction = proc "c" (
		data: rawptr,
		wl_pointer: ^wl.wl_pointer,
		axis: c.uint32_t,
		direction: c.uint32_t,
	) {},
}
