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
	after_frame_present = wl_after_frame_present,
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
import "core:strings"
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

			case wl.zxdg_decoration_manager_v1_interface.name:
				s.decoration_manager = cast(^wl.zxdg_decoration_manager_v1)(wl.registry_bind(
					registry,
					name,
					&wl.zxdg_decoration_manager_v1_interface,
					version,
			))
			}
		},
	}

	display_registry := wl.display_get_registry(s.display)
	wl.add_listener(display_registry, &registry_listener, nil)
	wl.display_roundtrip(s.display)

	

	wl.add_listener(s.seat, &seat_listener, nil)
	wl.display_roundtrip(s.display)

	log.info("1")
	s.surface = wl.compositor_create_surface(s.compositor)
	log.info(s.surface)

	if s.surface == nil {
		log.info("hi")
	} else {
		log.info("ho")
	}

	log.ensure(s.surface != nil, "Error creating Wayland surface")
	log.info("2")
	
	// Makes sure the window does "pings" that keeps it alive.
	wl.add_listener(s.xdg_base, &wm_base_listener, nil)
	xdg_surface := wl.xdg_wm_base_get_xdg_surface(s.xdg_base, s.surface)

	// Top-level means an application at the top of the window hierarchy. The callback in the
	// toplevel listener effecively creates a window handle.
	toplevel := wl.xdg_surface_get_toplevel(xdg_surface)
	wl.add_listener(toplevel, &toplevel_listener, nil)
	wl.add_listener(xdg_surface, &window_listener, nil)
	wl.xdg_toplevel_set_title(toplevel, strings.clone_to_cstring(window_title))
	

    decoration := wl.zxdg_decoration_manager_v1_get_toplevel_decoration(s.decoration_manager, toplevel)
    wl.zxdg_toplevel_decoration_v1_set_mode(decoration, wl.ZXDG_TOPLEVEL_DECORATION_V1_MODE_SERVER_SIDE)

	wl.surface_commit(s.surface)
	wl.display_dispatch(s.display)


	wl_callback := wl.wl_surface_frame(s.surface)
	wl.wl_callback_add_listener(wl_callback, &frame_callback, nil)

	s.window = wl.egl_window_create(s.surface, i32(s.windowed_width), i32(s.windowed_height))

	s.window_handle = {
		display = s.display,
		window = s.window,
		surface = s.surface,
	}
}


seat_listener := wl.Seat_Listener {
	capabilities = proc "c" (data: rawptr, seat: ^wl.Seat, capabilities: wl.Seat_Capabilities) {
		context = s.odin_ctx
		log.info("here")

		if .Pointer in capabilities {
			if s.pointer != nil {
				wl.pointer_release(s.pointer)
			}

			s.pointer = wl.seat_get_pointer(seat)
			wl.add_listener(s.pointer, &pointer_listener, nil)
		} else if s.pointer != nil {
			wl.pointer_release(s.pointer)
			s.pointer = nil
		}

		if .Keyboard in capabilities {
			if s.keyboard != nil {
				wl.keyboard_release(s.keyboard)
			}

			s.keyboard = wl.seat_get_keyboard(seat)
			wl.add_listener(s.keyboard, &keyboard_listener, nil)
		} else if s.keyboard != nil {
			wl.keyboard_release(s.keyboard)
			s.keyboard = nil
		}
	},
	name = proc "c" (data: rawptr, seat: ^wl.Seat, name: cstring) {},
}

@(private="package")
frame_callback := wl.wl_callback_listener {
	done = proc "c" (data: rawptr, wl_callback: ^wl.wl_callback, callback_data: c.uint32_t) {
		wl.wl_callback_destroy(wl_callback)
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
		if s.configured && (s.width != int(width) || s.height != int(height)) {
			wl.egl_window_resize(s.window, c.int(width), c.int(height), 0, 0)

			if s.window_mode == .Windowed || s.window_mode == .Windowed_Resizable {
				s.windowed_width = int(width)
				s.windowed_height = int(height)
			}

			s.width = int(width)
			s.height = int(height)

			context = s.odin_ctx

			append(&s.events, Window_Event_Resize {
				width = s.width,
                height = s.height,
			})
		}
		s.configured = true
	},
	close = proc "c" (data: rawptr, xdg_toplevel: ^wl.xdg_toplevel) {
		context = s.odin_ctx
		append(&s.events, Window_Event_Close_Wanted{})
	},
	configure_bounds = proc "c" (data: rawptr, xdg_toplevel: ^wl.xdg_toplevel, width: c.int32_t, height: c.int32_t,) { },
	wm_capabilities = proc "c" (data: rawptr, xdg_toplevel: ^wl.xdg_toplevel, capabilities: ^wl.wl_array,) {},
}

window_listener := wl.xdg_surface_listener {
	configure = proc "c" (data: rawptr, surface: ^wl.xdg_surface, serial: c.uint32_t) {
		// context = runtime.default_context()
		// fmt.println("window configure")
		wl.xdg_surface_ack_configure(surface, serial)
	},
}

wm_base_listener := wl.XDG_WM_Base_Listener {
	ping = proc "c" (data: rawptr, xdg_wm_base: ^wl.XDG_WM_Base, serial: c.uint32_t) {
		wl.xdg_wm_base_pong(xdg_wm_base, serial)
	},
}

keyboard_listener := wl.Keyboard_Listener {
	keymap = proc "c" (data: rawptr, keyboard: ^wl.Keyboard, format: c.uint32_t, fd: c.int32_t, size: c.uint32_t,) {},
	enter = proc "c" (data: rawptr, keyboard: ^wl.Keyboard, serial: c.uint32_t, surface: ^wl.Surface, keys: ^wl.wl_array) {},
	leave = proc "c" (data: rawptr, keyboard: ^wl.Keyboard, serial: c.uint32_t, surface: ^wl.Surface) {},
	key = key_handler,
	modifiers = proc "c" (
		data: rawptr,
		wl_keyboard: ^wl.Keyboard,
		serial: c.uint32_t,
		mods_depressed: c.uint32_t,
		mods_latched: c.uint32_t,
		mods_locked: c.uint32_t,
		group: c.uint32_t,
	) {
	},
	repeat_info = proc "c" (
		data: rawptr,
		wl_keyboard: ^wl.Keyboard,
		rate: c.int32_t,
		delay: c.int32_t,
	) {},
}

key_handler :: proc "c" (
	data: rawptr,
	keyboard: ^wl.Keyboard,
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
			log.info(key)
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
	return Window_Handle(&s.window_handle)
}

wl_process_events :: proc() {
}

wl_after_frame_present :: proc() {
	wl.display_dispatch(s.display)
}

key_from_xkeycode :: proc(kc: u32) -> Keyboard_Key {
	if kc >= 255 {
		return .None
	}

	return KEY_FROM_XKEYCODE[kc]
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
	window: ^wl.egl_window,
	decoration_manager: ^wl.zxdg_decoration_manager_v1,

	xdg_base: ^wl.XDG_WM_Base,
	seat: ^wl.Seat,

	keyboard: ^wl.Keyboard,
	pointer: ^wl.Pointer,

	// True if toplevel_listener.configure has run
	configured: bool,

	window_handle: Window_Handle_Wayland,
}

@(private="package")
Window_Handle_Wayland :: struct {
	display: ^wl.Display,
	surface: ^wl.Surface,
	window: ^wl.egl_window,
}

s: ^WL_State

