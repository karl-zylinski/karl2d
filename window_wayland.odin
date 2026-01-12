#+build linux
#+private file

package karl2d

@(private="package")
WINDOW_INTERFACE_WAYLAND :: Window_Interface {
	state_size = wl_state_size,
	init = wl_init,
	shutdown = wl_shutdown,
	window_handle = wl_window_handle,
	process_events = wl_process_events,
	get_events = wl_get_events,
	get_width = wl_get_width,
	get_height = wl_get_height,
	clear_events = wl_clear_events,
	set_position = wl_set_position,
	set_size = wl_set_size,
	get_window_scale = wl_get_window_scale,
	set_window_mode = wl_set_window_mode,
	is_gamepad_active = wl_is_gamepad_active,
	get_gamepad_axis = wl_get_gamepad_axis,
	set_gamepad_vibration = wl_set_gamepad_vibration,
	set_internal_state = wl_set_internal_state,
}

import "base:runtime"
import "log"
import "core:fmt"
import wl "linux/wayland"
import "core:c"

_ :: log
_ :: fmt

wl_state_size :: proc() -> int {
	return size_of(WL_State)
}

wl_init :: proc(
	window_state: rawptr,
	window_width: int,
	window_height: int,
	window_title: string,
	init_options: Init_Options,
	allocator: runtime.Allocator,
) {
	s = (^WL_State)(window_state)
	s.allocator = allocator
	s.windowed_width = window_width
	s.windowed_height = window_height
	s.width = window_width
	s.height = window_height
	s.odin_ctx = context

	s.display = wl.display_connect(nil)

	@static registry_listener := wl.Registry_Listener {
		global = proc "c" (
			data: rawptr,
			registry: ^wl.Registry,
			name: c.uint32_t,
			interface: cstring,
			version: c.uint32_t,
		) {
			context = s.odin_ctx
			switch interface {
			case wl.compositor_interface.name:
				s.compositor = (^wl.Compositor)(wl.registry_bind(
					registry,
					name,
					&wl.compositor_interface,
					version,
				))

			case wl.xdg_wm_base_interface.name:
				s.xdg_base = (^wl.XDG_WM_Base)(wl.registry_bind(
					registry,
					name,
					&wl.xdg_wm_base_interface,
					version,
				))

			case wl.seat_interface.name:
				s.seat = (^wl.Seat)(wl.registry_bind(
					registry,
					name,
					&wl.seat_interface,
					version,
				))
			}
		},
	}

	display_registry := wl.display_get_registry(s.display)
	wl.add_listener(display_registry, &registry_listener, nil)
	wl.display_roundtrip(s.display)

	@(static, rodata) seat_listener := wl.Seat_Listener {
		capabilities = proc "c" (data: rawptr, seat: ^wl.Seat, capabilities: wl.Seat_Capabilities) {
			context = s.odin_ctx
			log.info("here")

			if .Pointer in capabilities {
				if s.pointer != nil {
					wl.pointer_release(s.pointer)
					s.pointer = nil
				}

				s.pointer = wl.seat_get_pointer(seat)
				wl.add_listener(s.pointer, &pointer_listener, nil)
			} else if s.pointer != nil {
				wl.pointer_release(s.pointer)
				s.pointer = nil
			}

			/*if capabilities & wl_seat.capability_keyboard {
				if d.keyboard {
					wl_keyboard.release(d.keyboard);
					d.keyboard = null;
				}

				d.keyboard = wl_seat.get_keyboard(d.seat);
				wl_proxy_set_user_data(d.keyboard, d);
				wl_keyboard.add_listener(d.keyboard, *keyboard_listenter, d);
			} else if d.keyboard {
				wl_keyboard.release(d.keyboard);
				d.keyboard = null;
			}*/
		},
		name = proc "c" (data: rawptr, seat: ^wl.Seat, name: cstring) {},
	}

	wl.add_listener(s.seat, &seat_listener, nil)

	log.info("1")
	s.surface = wl.compositor_create_surface(s.compositor)
	log.ensure(s.surface != nil, "Error creating Wayland surface")
	log.info("2")
	
	// Makes sure the window does "pigns" that keeps it alive.
	//wl.add_listener(s.xdg_base, &wm_base_listener, nil)

	log.info("end")
}

wm_base_listener := wl.XDG_WM_Base_Listener {
	ping = proc "c" (data: rawptr, xdg_wm_base: ^wl.XDG_WM_Base, serial: c.uint32_t) {
		wl.xdg_wm_base_pong(xdg_wm_base, serial)
	},
}

pointer_listener := wl.Pointer_Listener {
	enter = proc "c" (
		data: rawptr,
		pointer: ^wl.Pointer,
		serial: c.uint32_t,
		surface: ^wl.Surface,
		surface_x: wl.Fixed,
		surface_y: wl.Fixed,
	) {

	},
	leave = proc "c" (
		data: rawptr,
		pointer: ^wl.Pointer,
		serial: c.uint32_t,
		surface: ^wl.Surface,
	) {

	},
	motion = proc "c" (
		data: rawptr,
		pointer: ^wl.Pointer,
		time: c.uint32_t,
		surface_x: wl.Fixed,
		surface_y: wl.Fixed,
	) {

	},
	button = proc "c" (
		data: rawptr,
		pointer: ^wl.Pointer,
		serial: c.uint32_t,
		time: c.uint32_t,
		button: c.uint32_t,
		state: c.uint32_t,
	) {

	},
	axis = proc "c" (
		data: rawptr,
		pointer: ^wl.Pointer,
		time: c.uint32_t,
		axis: c.uint32_t,
		value: wl.Fixed,
	) {

	},
	frame = proc "c" (data: rawptr, wl_pointer: ^wl.Pointer) {

	},
	axis_source = proc "c" (
		data: rawptr,
		pointer: ^wl.Pointer,
		axis_source: c.uint32_t,
	) {

	},
	axis_stop = proc "c" (
		data: rawptr,
		pointer: ^wl.Pointer,
		time: c.uint32_t,
		axis: c.uint32_t,
	) {

	},
	axis_discrete = proc "c" (
		data: rawptr,
		pointer: ^wl.Pointer,
		axis: c.uint32_t,
		discrete: c.int32_t,
	) {

	},
	axis_value120 = proc "c" (
		data: rawptr,
		pointer: ^wl.Pointer,
		axis: c.uint32_t,
		value120: c.int32_t,
	) {

	},
	axis_relative_direction = proc "c" (
		data: rawptr,
		pointer: ^wl.Pointer,
		axis: c.uint32_t,
		direction: c.uint32_t,
	) {

	},
}

wl_shutdown :: proc() {
	delete(s.events)
}

wl_window_handle :: proc() -> Window_Handle {
	return {}
}

wl_process_events :: proc() {
}

key_from_xkeycode :: proc(kc: u32) -> Keyboard_Key {
	if kc >= 255 {
		return .None
	}

	return .None
}

wl_get_events :: proc() -> []Window_Event {
	return s.events[:]
}

wl_get_width :: proc() -> int {
	return s.width
}

wl_get_height :: proc() -> int {
	return s.height
}

wl_clear_events :: proc() {
	runtime.clear(&s.events)
}

wl_set_position :: proc(x: int, y: int) {
}

wl_set_size :: proc(w, h: int) {
}

wl_get_window_scale :: proc() -> f32 {
	return 1
}

wl_set_window_mode :: proc(window_mode: Window_Mode) {
	
}

wl_is_gamepad_active :: proc(gamepad: int) -> bool {
	if gamepad < 0 || gamepad >= MAX_GAMEPADS {
		return false
	}

	return false
}

wl_get_gamepad_axis :: proc(gamepad: int, axis: Gamepad_Axis) -> f32 {
	if gamepad < 0 || gamepad >= MAX_GAMEPADS {
		return 0
	}

	return 0
}

wl_set_gamepad_vibration :: proc(gamepad: int, left: f32, right: f32) {
	if gamepad < 0 || gamepad >= MAX_GAMEPADS {
		return
	}
}

wl_set_internal_state :: proc(state: rawptr) {
	assert(state != nil)
	s = (^WL_State)(state)
}

WL_State :: struct {
	allocator: runtime.Allocator,
	width: int,
	height: int,
	windowed_width: int,
	windowed_height: int,
	events: [dynamic]Window_Event,
	window_mode: Window_Mode,

	odin_ctx: runtime.Context,
	
	display: ^wl.Display,
	surface: ^wl.Surface,
	compositor: ^wl.Compositor,

	xdg_base: ^wl.XDG_WM_Base,
	seat: ^wl.Seat,

	pointer: ^wl.Pointer,
}

s: ^WL_State

