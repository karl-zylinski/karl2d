#+build linux
package karl2d

@(private="package")
LINUX_WINDOW_WAYLAND :: Linux_Window_Interface {
	state_size = wl_state_size,
	init = wl_init,
	shutdown = wl_shutdown,
	get_window_render_glue = wl_get_window_render_glue,
	get_events = wl_get_events,
	get_width = wl_get_width,
	get_height = wl_get_height,
	set_position = wl_set_position,
	set_size = wl_set_size,
	get_window_scale = wl_get_window_scale,
	set_window_mode = wl_set_window_mode,
	set_internal_state = wl_set_internal_state,
}

import "base:runtime"
import "core:fmt"
import "core:strings"
import "core:c"

import "log"
import wl "platform_bindings/linux/wayland"

_ :: log
_ :: fmt

@(private="package")

wl_state_size :: proc() -> int {
	return size_of(WL_State)
}

wl_init :: proc(
	window_state: rawptr,
	window_width: int,
	window_height: int,
	window_title: string,
	options: Init_Options,
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

	display_registry := wl.display_get_registry(s.display)
	wl.add_listener(display_registry, &registry_listener, nil)
	wl.display_roundtrip(s.display)

	wl.add_listener(s.seat, &seat_listener, nil)
	wl.display_roundtrip(s.display)

	s.surface = wl.compositor_create_surface(s.compositor)
	log.ensure(s.surface != nil, "Error creating Wayland surface")
	
	// Makes sure the window does "pings" that keeps it alive.
	wl.add_listener(s.xdg_base, &wm_base_listener, nil)
	xdg_surface := wl.xdg_wm_base_get_xdg_surface(s.xdg_base, s.surface)

	// Top-level means an application at the top of the window hierarchy. The callback in the
	// toplevel listener effecively creates a window handle.
	s.toplevel = wl.xdg_surface_get_toplevel(xdg_surface)
	wl.add_listener(s.toplevel, &toplevel_listener, nil)
	wl.add_listener(xdg_surface, &window_listener, nil)
	wl.xdg_toplevel_set_title(s.toplevel, strings.clone_to_cstring(window_title, frame_allocator))

    decoration := wl.zxdg_decoration_manager_v1_get_toplevel_decoration(s.decoration_manager, s.toplevel)

    // This adds titlebar and buttons to the window.
    wl.zxdg_toplevel_decoration_v1_set_mode(decoration, wl.ZXDG_TOPLEVEL_DECORATION_V1_MODE_SERVER_SIDE)

	fractional_scale := wl.wp_fractional_scale_manager_get_fractional_scale(s.fractional_scale_manager, s.surface)
	wl.add_listener(fractional_scale, &fractional_scale_listener, nil)

	wl.surface_commit(s.surface)
	wl.display_dispatch_pending(s.display)

	callback := wl.surface_frame(s.surface)
	wl.add_listener(callback, &frame_callback, nil)

	s.window = wl.egl_window_create(s.surface, i32(s.windowed_width), i32(s.windowed_height))

	when RENDER_BACKEND_NAME == "gl" {
		s.window_render_glue = make_linux_gl_wayland_glue(s.display, s.window, s.allocator)
	} else when RENDER_BACKEND_NAME == "nil" {
		s.window_render_glue = {}
	} else {
		#panic("Unsupported combo of Linux + X11 and render backend '" + RENDER_BACKEND_NAME + "'")
	}

	set_window_mode(options.window_mode)
}

registry_listener := wl.Registry_Listener {
	global = proc "c" (
		data: rawptr,
		registry: ^wl.Registry,
		name: u32,
		interface: cstring,
		version: u32,
	) {
		context = s.odin_ctx
		switch interface {
		case wl.compositor_interface.name:
			s.compositor = wl.registry_bind(
				wl.Compositor,
				registry,
				name,
				&wl.compositor_interface,
				version,
			)

		case wl.xdg_wm_base_interface.name:
			s.xdg_base = wl.registry_bind(
				wl.XDG_WM_Base,
				registry,
				name,
				&wl.xdg_wm_base_interface,
				version,
			)

		case wl.seat_interface.name:
			s.seat = wl.registry_bind(
				wl.Seat,
				registry,
				name,
				&wl.seat_interface,
				version,
			)

		case wl.zxdg_decoration_manager_v1_interface.name:
			s.decoration_manager = wl.registry_bind(
				wl.ZXDG_Decoration_Manager_V1,
				registry,
				name,
				&wl.zxdg_decoration_manager_v1_interface,
				version,
			)

		case wl.wp_fractional_scale_manager_v1_interface.name:
			s.fractional_scale_manager = wl.registry_bind(
				wl.WP_Fractional_Scale_Manager_V1,
				registry,
				name,
				&wl.wp_fractional_scale_manager_v1_interface,
				version,
			)
		}
	},
}

seat_listener := wl.Seat_Listener {
	capabilities = proc "c" (data: rawptr, seat: ^wl.Seat, capabilities: wl.Seat_Capabilities) {
		context = s.odin_ctx

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

frame_callback := wl.Callback_Listener {
	done = proc "c" (data: rawptr, callback: ^wl.Callback, callback_data: c.uint32_t) {
		wl.destroy(callback)
	},
}

toplevel_listener := wl.XDG_Toplevel_Listener {
	configure = proc "c" (
		data: rawptr,
		xdg_toplevel: ^wl.XDG_Toplevel,
		width: c.int32_t,
		height: c.int32_t,
		states: ^wl.Array,
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

			append(&s.events, Event_Resize {
				width = s.width,
                height = s.height,
			})
		}
		s.configured = true
	},
	close = proc "c" (data: rawptr, xdg_toplevel: ^wl.XDG_Toplevel) {
		context = s.odin_ctx
		append(&s.events, Event_Close_Window_Requested{})
	},
	configure_bounds = proc "c" (data: rawptr, xdg_toplevel: ^wl.XDG_Toplevel, width: c.int32_t, height: c.int32_t,) { },
	wm_capabilities = proc "c" (data: rawptr, xdg_toplevel: ^wl.XDG_Toplevel, capabilities: ^wl.Array,) {},
}

window_listener := wl.XDG_Surface_Listener {
	configure = proc "c" (data: rawptr, surface: ^wl.XDG_Surface, serial: c.uint32_t) {
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
	enter = proc "c" (data: rawptr, keyboard: ^wl.Keyboard, serial: c.uint32_t, surface: ^wl.Surface, keys: ^wl.Array) {},
	leave = proc "c" (data: rawptr, keyboard: ^wl.Keyboard, serial: c.uint32_t, surface: ^wl.Surface) {},
	key = key_handler,
	modifiers = proc "c" (
		data: rawptr,
		keyboard: ^wl.Keyboard,
		serial: c.uint32_t,
		mods_depressed: c.uint32_t,
		mods_latched: c.uint32_t,
		mods_locked: c.uint32_t,
		group: c.uint32_t,
	) {
	},
	repeat_info = proc "c" (
		data: rawptr,
		keyboard: ^wl.Keyboard,
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

	switch state {
	case wl.KEYBOARD_KEY_STATE_RELEASED:
		key := key_from_xkeycode(keycode)

		if key != .None {
			append(&s.events, Event_Key_Went_Up {
				key = key,
			})
		}
		
	case wl.KEYBOARD_KEY_STATE_PRESSED:
		key := key_from_xkeycode(keycode)

		if key != .None {
			append(&s.events, Event_Key_Went_Down {
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
		context = s.odin_ctx

		// surface_x and surface_y are fixed point 24.8 variables. 
		// Just bitshift them to remove the decimal part and obtain 
		// a screen coordinate
		append(&s.events, Event_Mouse_Move {
			position = { f32(surface_x >> 8), f32(surface_y >> 8) }, 
		})
	},
	button = proc "c" (
		data: rawptr,
		pointer: ^wl.Pointer,
		serial: c.uint32_t,
		time: c.uint32_t,
		button: c.uint32_t,
		state: c.uint32_t,
	) {
		context = s.odin_ctx

		btn: Mouse_Button
		switch button {
		case 0: btn = .Left
		case 1: btn = .Middle
		case 2: btn = .Right
		}
	
		switch state {
		case wl.POINTER_BUTTON_STATE_RELEASED:
			append(&s.events, Event_Mouse_Button_Went_Up {
				button = btn,
			})
		case wl.POINTER_BUTTON_STATE_PRESSED: 
			append(&s.events, Event_Mouse_Button_Went_Down {
				button = btn,
			})
		}
	},
	axis = proc "c" (
		data: rawptr,
		pointer: ^wl.Pointer,
		time: c.uint32_t,
		axis: c.uint32_t,
		value: wl.Fixed,
	) {
		context = s.odin_ctx

		// Vertical scroll
		if axis == 0 {
			event_direction: f32 = value > 0 ? 1 : -1
			
			append(&s.events, Event_Mouse_Wheel {
				delta = event_direction,
			})
		}
	},
	frame = proc "c" (data: rawptr, pointer: ^wl.Pointer) {},
	axis_source = proc "c" (
		data: rawptr,
		pointer: ^wl.Pointer,
		axis_source: c.uint32_t,
	) {},
	axis_stop = proc "c" (
		data: rawptr,
		pointer: ^wl.Pointer,
		time: c.uint32_t,
		axis: c.uint32_t,
	) {},
	axis_discrete = proc "c" (
		data: rawptr,
		pointer: ^wl.Pointer,
		axis: c.uint32_t,
		discrete: c.int32_t,
	) {},
	axis_value120 = proc "c" (
		data: rawptr,
		pointer: ^wl.Pointer,
		axis: c.uint32_t,
		value120: c.int32_t,
	) {},
	axis_relative_direction = proc "c" (
		data: rawptr,
		pointer: ^wl.Pointer,
		axis: c.uint32_t,
		direction: c.uint32_t,
	) {},
}

fractional_scale_listener := wl.WP_Fractional_Scale_V1_Listener {
	preferred_scale = proc "c" (
		data: rawptr,
		self: ^wl.WP_Fractional_Scale_V1,
		scale: u32,
	) {
		context = s.odin_ctx
		scl := f32(scale)/120
		s.scale = scl

		// Disabled because we don't yet make the base scale of the
		// window correct.
		/*append(&s.events, Event_Window_Scale_Changed {
			scale = scl,
		})*/
	},
}

wl_shutdown :: proc() {
	delete(s.events)
}

wl_get_window_render_glue :: proc() -> Window_Render_Glue {
	return s.window_render_glue
}

wl_get_events :: proc(events: ^[dynamic]Event) {
	wl.display_dispatch_pending(s.display)
	append(events, ..s.events[:])
	runtime.clear(&s.events)
}

wl_get_width :: proc() -> int {
	return s.width
}

wl_get_height :: proc() -> int {
	return s.height
}

wl_set_position :: proc(x: int, y: int) {
	log.error("set_position not implemented when using wayland")
}

wl_set_size :: proc(w, h: int) {
	if s.window_mode == .Borderless_Fullscreen {
		return
	}

	s.windowed_width = w
	s.windowed_height = h
	wl.egl_window_resize(s.window, i32(w), i32(h), 0, 0)
}

wl_get_window_scale :: proc() -> f32 {
	// Disabled for now, as we don't make the base scale of the window correct yet.
	return 1
}

wl_set_window_mode :: proc(window_mode: Window_Mode) {
	s.window_mode = window_mode
	 
	switch window_mode {
	case .Windowed:
		wl.xdg_toplevel_unset_fullscreen(s.toplevel)
		w := i32(s.windowed_width)
		h := i32(s.windowed_height)
		wl.xdg_toplevel_set_max_size(s.toplevel, w, h)
		wl.xdg_toplevel_set_min_size(s.toplevel, w, h)

	case .Windowed_Resizable:
		wl.xdg_toplevel_unset_fullscreen(s.toplevel)
		wl.xdg_toplevel_set_max_size(s.toplevel, 0, 0)
		wl.xdg_toplevel_set_min_size(s.toplevel, 0, 0)

	case .Borderless_Fullscreen:
		wl.xdg_toplevel_set_fullscreen(s.toplevel, nil)
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
	events: [dynamic]Event,
	window_mode: Window_Mode,

	odin_ctx: runtime.Context,
	
	display: ^wl.Display,
	surface: ^wl.Surface,
	compositor: ^wl.Compositor,
	window: ^wl.EGL_Window,
	toplevel: ^wl.XDG_Toplevel,
	decoration_manager: ^wl.ZXDG_Decoration_Manager_V1,
	fractional_scale_manager: ^wl.WP_Fractional_Scale_Manager_V1,

	xdg_base: ^wl.XDG_WM_Base,
	seat: ^wl.Seat,
	scale: f32,

	keyboard: ^wl.Keyboard,
	pointer: ^wl.Pointer,

	// True if toplevel_listener.configure has run
	configured: bool,

	window_render_glue: Window_Render_Glue,
}

s: ^WL_State

