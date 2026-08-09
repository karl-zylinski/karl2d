#+build linux
package karl2d

@(private="package")
LINUX_WINDOW_WAYLAND :: Linux_Window_Interface {
	state_size = wl_state_size,
	init = wl_init,
	shutdown = wl_shutdown,
	get_window_render_glue = wl_get_window_render_glue,
	get_events = wl_get_events,
	set_title = wl_set_title,
	get_screen_width = wl_get_screen_width,
	get_screen_height = wl_get_screen_height,
	set_position = wl_set_position,
	set_screen_size = wl_set_screen_size,
	get_window_scale = wl_get_window_scale,
	set_window_mode = wl_set_window_mode,
	set_cursor_hidden = wl_set_cursor_hidden,
	is_cursor_hidden = wl_is_cursor_hidden,
	set_mouse_locked = wl_set_mouse_locked,
	is_mouse_locked = wl_is_mouse_locked,
	create_custom_cursor = wl_create_custom_cursor,
	set_cursor = wl_set_cursor,
	destroy_custom_cursor = wl_destroy_custom_cursor,
	set_internal_state = wl_set_internal_state,
}

import "base:runtime"
import "core:fmt"
import "core:strings"
import "core:c"
import "core:math"
import "core:sys/linux"
import hm "core:container/handle_map"

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
	screen_width: int,
	screen_height: int,
	window_title: string,
	options: Init_Options,
	allocator: runtime.Allocator,
) {
	s = (^WL_State)(window_state)
	s.allocator = allocator
	s.scale = 1
	s.odin_ctx = context
	hm.dynamic_init(&s.custom_cursors, allocator)

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

	if s.decoration_manager != nil {
		decoration := wl.zxdg_decoration_manager_v1_get_toplevel_decoration(s.decoration_manager, s.toplevel)

		// This adds titlebar and buttons to the window.
		wl.zxdg_toplevel_decoration_v1_set_mode(decoration, wl.ZXDG_TOPLEVEL_DECORATION_V1_MODE_SERVER_SIDE)
	}

	fractional_scale := wl.wp_fractional_scale_manager_get_fractional_scale(s.fractional_scale_manager, s.surface)
	wl.add_listener(fractional_scale, &fractional_scale_listener, nil)

	wl.surface_commit(s.surface)
	wl.display_dispatch_pending(s.display)
	wl.display_roundtrip(s.display)

	s.relative_pointer = wl.zwp_relative_pointer_manager_v1_get_relative_pointer(
		s.relative_pointer_manager,
		s.pointer,
	)

	wl.add_listener(s.relative_pointer, &relative_pointer_listener, nil)

	s.cursor_surface = wl.compositor_create_surface(s.compositor)
	s.cursor_viewport = wl.wp_viewporter_get_viewport(s.viewporter, s.cursor_surface)
	wl.wp_viewport_set_destination(s.cursor_viewport, 24, 24)

	// The cursor shape protocol lets the compositor render its own default cursor at the correct
	// size and DPI, so the theme is only needed as a fallback for compositors without it.
	if s.cursor_shape_device == nil {
		wl_load_cursor_theme()
	}

	unscaled_width := screen_width
	unscaled_height := screen_height

	scaled_width := int(f32(unscaled_width) * s.scale)
	scaled_height := int(f32(unscaled_height) * s.scale)

	callback := wl.surface_frame(s.surface)
	wl.add_listener(callback, &frame_callback, nil)

	s.viewport = wl.wp_viewporter_get_viewport(s.viewporter, s.surface)
	wl.wp_viewport_set_destination(s.viewport, i32(unscaled_width), i32(unscaled_height))
	s.window = wl.egl_window_create(s.surface, i32(scaled_width), i32(scaled_height))

	s.screen_width = scaled_width
	s.screen_height = scaled_height

	wl.surface_commit(s.surface)
	wl.display_dispatch_pending(s.display)
	wl.display_roundtrip(s.display)

	when RENDER_BACKEND_NAME == "gl" {
		s.window_render_glue = make_linux_gl_wayland_glue(s.display, s.window, s.allocator)
	} else when RENDER_BACKEND_NAME == "nil" {
		s.window_render_glue = {}
	} else {
		#panic("Unsupported combo of Linux + X11 and render backend '" + RENDER_BACKEND_NAME + "'")
	}

	wl_set_window_mode(options.window_mode)

	if options.disable_auto_scale_hint {
		log.warn("disable_auto_scale_hint not supported on linux/wayland")
	}
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

		case wl.wp_viewporter_interface.name:
			s.viewporter = wl.registry_bind(
				wl.WP_Viewporter,
				registry,
				name,
				&wl.wp_viewporter_interface,
				version,
			)

		case wl.zwp_relative_pointer_manager_v1_interface.name:
			s.relative_pointer_manager = wl.registry_bind(
				wl.ZWP_Relative_Pointer_Manager_V1,
				registry,
				name,
				&wl.zwp_relative_pointer_manager_v1_interface,
				version,
			)

		case wl.zwp_pointer_constraints_v1_interface.name:
			s.pointer_constraints = wl.registry_bind(
				wl.ZWP_Pointer_Constraints_V1,
				registry,
				name,
				&wl.zwp_pointer_constraints_v1_interface,
				version,
			)

		case wl.shm_interface.name:
			s.shm = wl.registry_bind(
				wl.SHM,
				registry,
				name,
				&wl.shm_interface,
				version,
			)

		case wl.wp_cursor_shape_manager_v1_interface.name:
			s.cursor_shape_manager = wl.registry_bind(
				wl.WP_Cursor_Shape_Manager_V1,
				registry,
				name,
				&wl.wp_cursor_shape_manager_v1_interface,
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
				if s.cursor_shape_device != nil {
					wl.cursor_shape_device_destroy(s.cursor_shape_device)
					s.cursor_shape_device = nil
				}
				wl.pointer_release(s.pointer)
			}

			s.pointer = wl.seat_get_pointer(seat)
			wl.add_listener(s.pointer, &pointer_listener, nil)
			if s.cursor_shape_manager != nil {
				s.cursor_shape_device = wl.cursor_shape_manager_get_pointer(
					s.cursor_shape_manager,
					s.pointer,
				)
			}
		} else if s.pointer != nil {
			if s.cursor_shape_device != nil {
				wl.cursor_shape_device_destroy(s.cursor_shape_device)
				s.cursor_shape_device = nil
			}
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
		w := int(width)
		h := int(height)

		context = s.odin_ctx

		if s.last_configure_width != w || s.last_configure_height != h  {
			if s.window_mode == .Windowed || s.window_mode == .Windowed_Resizable {
				s.last_configure_windowed_width = w
				s.last_configure_windowed_height = h
			}

			s.screen_width = int(f32(w) * s.scale)
			s.screen_height = int(f32(h) * s.scale)
			s.last_configure_width = w
			s.last_configure_height = h

			wl.egl_window_resize(s.window, i32(s.screen_width), i32(s.screen_height), 0, 0)
			wl.wp_viewport_set_destination(s.viewport, i32(w), i32(h))

			append(&s.events, Event_Screen_Resize {
				width = s.screen_width,
				height = s.screen_height,
			})
		}
		s.configured = true
	},
	close = proc "c" (data: rawptr, xdg_toplevel: ^wl.XDG_Toplevel) {
		context = s.odin_ctx
		append(&s.events, Event_Close_Window_Requested{})
	},
	configure_bounds = proc "c" (data: rawptr, xdg_toplevel: ^wl.XDG_Toplevel, width: c.int32_t, height: c.int32_t,) {},
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
		context = s.odin_ctx
		s.pointer_enter_serial = u32(serial)
		wl_apply_cursor()
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
			position = { math.floor(f32(surface_x >> 8) * s.scale), math.floor(f32(surface_y >> 8) * s.scale) }, 
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
		case wl.POINTER_BTN_LEFT: btn = .Left
		case wl.POINTER_BTN_MIDDLE: btn = .Middle
		case wl.POINTER_BTN_RIGHT: btn = .Right
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
			event_direction: f32 = value > 0 ? -1 : 1
			
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
		s.screen_width = int(f32(s.last_configure_width) * s.scale)
		s.screen_height = int(f32(s.last_configure_height) * s.scale)
		wl.egl_window_resize(s.window, i32(s.screen_width), i32(s.screen_height), 0, 0)

		// The cursor theme is loaded at a fixed physical size, so it needs reloading whenever
		// the scale changes. Only relevant without the cursor shape protocol - the compositor
		// handles its own DPI when we use that instead.
		if s.cursor_shape_device == nil {
			wl_load_cursor_theme()
		}

		// Makes any visible effect of the new scale (a rescaled custom cursor, or a reloaded
		// theme cursor) happen instantly rather than waiting for the next pointer move.
		wl_apply_cursor()

		append(&s.events, Event_Window_Scale_Changed {
			scale = scl,
			screen_width = s.screen_width,
			screen_height = s.screen_height,
		})
	},
}

wl_shutdown :: proc() {
	for it := hm.dynamic_iterator_make(&s.custom_cursors); cd, _ in hm.dynamic_iterate(&it) {
		wl.wp_viewport_destroy(cd.viewport)
		wl.surface_destroy(cd.surface)
		wl.buffer_destroy(cd.buffer)
		linux.munmap(cd.data, uint(cd.data_size))
	}
	hm.dynamic_destroy(&s.custom_cursors)

	// The cursor shape protocol is optional, so these are nil on compositors that lack it.
	if s.cursor_shape_device != nil {
		wl.cursor_shape_device_destroy(s.cursor_shape_device)
		s.cursor_shape_device = nil
	}

	if s.cursor_shape_manager != nil {
		wl.cursor_shape_manager_destroy(s.cursor_shape_manager)
		s.cursor_shape_manager = nil
	}

	// The theme is only loaded on compositors without the cursor shape protocol.
	if s.cursor_theme != nil {
		wl.cursor_theme_destroy(s.cursor_theme)
		s.cursor_theme = nil
	}

	if s.cursor_viewport != nil {
		wl.wp_viewport_destroy(s.cursor_viewport)
		s.cursor_viewport = nil
	}

	if s.cursor_surface != nil {
		wl.surface_destroy(s.cursor_surface)
		s.cursor_surface = nil
	}

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

wl_set_title :: proc(title: string) {
	wl.xdg_toplevel_set_title(s.toplevel, strings.clone_to_cstring(title, frame_allocator))
}

wl_get_screen_width :: proc() -> int {
	return s.screen_width
}

wl_get_screen_height :: proc() -> int {
	return s.screen_height
}

wl_set_position :: proc(x: int, y: int) {
	log.error("set_position not implemented when using wayland")
}

wl_set_screen_size :: proc(w, h: int) {
	s.screen_width = int(f32(w) * s.scale)
	s.screen_height = int(f32(h) * s.scale)
	s.last_configure_width = w
	s.last_configure_height = h

	wl.egl_window_resize(s.window, i32(s.screen_width), i32(s.screen_height), 0, 0)
	wl.wp_viewport_set_destination(s.viewport, i32(w), i32(h))
}

wl_get_window_scale :: proc() -> f32 {
	return s.scale
}

wl_set_window_mode :: proc(window_mode: Window_Mode) {
	s.window_mode = window_mode
	 
	switch window_mode {
	case .Windowed:
		wl.xdg_toplevel_unset_fullscreen(s.toplevel)
		w := i32(s.last_configure_windowed_width)
		h := i32(s.last_configure_windowed_height)
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

wl_set_cursor_hidden :: proc(hidden: bool) {
	s.cursor_hidden = hidden
	wl_apply_cursor()
}

wl_is_cursor_hidden :: proc() -> bool {
	return s.cursor_hidden
}

locked_pointer_listener := wl.ZWP_Locked_Pointer_V1_Listener {
	locked = proc "c"(data: rawptr, lp: ^wl.ZWP_Locked_Pointer_V1) {
		context = s.odin_ctx
		s.locked_pointer = lp
		cx := f32(s.screen_width / 2)
		cy := f32(s.screen_height / 2)
		append(&s.events, Event_Mouse_Teleported { position = {cx, cy} })
	},
	unlocked = proc "c"(data: rawptr, lp: ^wl.ZWP_Locked_Pointer_V1) {
		context = s.odin_ctx
		s.locked_pointer = nil
	},
}


relative_pointer_listener := wl.ZWP_Relative_Pointer_V1_Listener {
	relative_motion = proc "c" (
		data: rawptr,
		rp: ^wl.ZWP_Relative_Pointer_V1,
		t_hi, t_lo: c.uint32_t,
		dx, dy, dx_unaccel, dy_unaccel: wl.Fixed,
	) {
		// Only used when pointer is locked
		if s.locked_pointer == nil {
			return
		}
		context = s.odin_ctx
		cx := f32(s.screen_width / 2)
		cy := f32(s.screen_height / 2)
		fdx := f32(dx_unaccel >> 8)
		fdy := f32(dy_unaccel >> 8)
		// Move relative to center, matching the warp-based platforms
		append(&s.events, Event_Mouse_Move {
			position = {cx + fdx, cy + fdy},
		})
		// Teleport back so next delta is also relative to center
		append(&s.events, Event_Mouse_Teleported { position = {cx, cy} })
	},
}

wl_set_mouse_locked :: proc(locked: bool) {
	if locked {
		if s.locked_pointer != nil {
			return
		}

		s.locked_pointer = wl.zwp_pointer_constraints_v1_lock_pointer(
			s.pointer_constraints, s.surface, s.pointer, nil,
			wl.ZWP_POINTER_CONSTRAINTS_V1_LIFETIME_PERSISTENT,
		)
		wl.add_listener(s.locked_pointer, &locked_pointer_listener, nil)

		// Synthetic teleport to center, so karl2d has the correct "previous position".
		cx := f32(s.screen_width / 2)
		cy := f32(s.screen_height / 2)
		append(&s.events, Event_Mouse_Teleported { position = {cx, cy} })
	} else {
		if s.locked_pointer == nil {
			return
		}

		wl.zwp_locked_pointer_v1_destroy(s.locked_pointer)
		s.locked_pointer = nil
	}
}

wl_is_mouse_locked :: proc() -> bool {
	return s.locked_pointer != nil
}

// Loads the cursor theme sized for the current DPI scale, destroying the previous one if this is
// a reload. Only used as a fallback for compositors without wp_cursor_shape_manager_v1, since a
// themed cursor image is a fixed physical size and has to be reloaded whenever the scale changes.
wl_load_cursor_theme :: proc() {
	if s.cursor_theme != nil {
		wl.cursor_theme_destroy(s.cursor_theme)
	}

	theme_size := max(1, int(math.round(24 * s.scale)))
	s.cursor_theme = wl.cursor_theme_load(nil, c.int(theme_size), s.shm)
}

// Sets the OS cursor from s.cursor_hidden and s.current_cursor. wl_set_cursor_hidden,
// wl_set_cursor and wl_destroy_custom_cursor all go through this instead of touching the
// pointer's cursor independently and clobbering each other. The pointer re-entering the window
// also goes through it, since the compositor forgets the cursor whenever the pointer leaves and
// comes back - this makes that happen instantly rather than showing the OS's own default cursor
// for a moment.
wl_apply_cursor :: proc() {
	// The fractional scale listener can fire during wl_init, before the pointer and the cursor
	// surface exist. Passing a nil surface to the compositor would mean "hide the cursor", and
	// attaching a buffer to one would dereference a nil proxy inside libwayland.
	if s.pointer == nil || s.cursor_surface == nil {
		return
	}

	if s.cursor_hidden {
		wl.pointer_set_cursor(s.pointer, s.pointer_enter_serial, nil, 0, 0)
		return
	}

	standard := Standard_Cursor.Default

	switch cur in s.current_cursor {
	case Standard_Cursor:
		standard = cur

	case Custom_Cursor:
		if cd := hm.get(&s.custom_cursors, cur); cd != nil {
			wl_point_at_cursor(cd, s.pointer_enter_serial)
			return
		}
		// Otherwise it was destroyed while on screen; fall through to the default cursor below.
	}

	// A standard cursor. Prefer the cursor shape protocol, which lets the compositor render it at
	// the correct size and DPI itself; the themed surface below is only a fallback for compositors
	// that don't support it.
	if s.cursor_shape_device != nil {
		wl.cursor_shape_device_set_shape(
			s.cursor_shape_device,
			s.pointer_enter_serial,
			wl_standard_cursor_shape(standard),
		)
		return
	}

	if s.cursor_theme == nil {
		return
	}

	name, fallback := linux_standard_cursor_names(standard)
	theme_cursor := wl.cursor_theme_get_cursor(s.cursor_theme, name)

	if theme_cursor == nil {
		theme_cursor = wl.cursor_theme_get_cursor(s.cursor_theme, fallback)
	}

	// The theme has no cursor under either name. Leaving whatever is already up is the best we can
	// do: the pointer keeps the cursor it had rather than blinking out of existence.
	if theme_cursor == nil || theme_cursor.image_count == 0 {
		return
	}

	image := theme_cursor.images[0]
	buf := wl.cursor_image_get_buffer(image)

	// The theme image is loaded at 24*scale physical pixels but the viewport set up in wl_init
	// maps it down to a fixed 24x24 logical size, so the hotspot (in the image's own pixels) has
	// to be scaled down to match.
	wl.pointer_set_cursor(
		s.pointer,
		s.pointer_enter_serial,
		s.cursor_surface,
		c.int32_t(math.round(f32(image.hotspot_x) / s.scale)),
		c.int32_t(math.round(f32(image.hotspot_y) / s.scale)),
	)

	wl.surface_attach(s.cursor_surface, buf, 0, 0)
	wl.surface_commit(s.cursor_surface)
}

wl_create_custom_cursor :: proc(image: Image, hotspot: [2]int) -> Custom_Cursor {
	stride := image.width * 4
	size := stride * image.height

	fd, err_fd := linux.memfd_create("cursor", {})
	if err_fd != .NONE {
		log.errorf("Failed to create Wayland cursor: memfd failed with %v", err_fd)
		return {}
	}

	// The compositor dups the fd in shm_create_pool, so we don't have to keep ours around.
	defer linux.close(fd)

	if err_trunc := linux.ftruncate(fd, i64(size)); err_trunc != .NONE {
		log.errorf("Failed to create Wayland cursor: ftruncate failed with %v", err_trunc)
		return {}
	}

	data, err_mmap := linux.mmap(0, uint(size), {.READ, .WRITE}, {.SHARED}, fd, 0)
	if err_mmap != .NONE {
		log.errorf("Failed to create Wayland cursor: mmap failed with %v", err_mmap)
		return {}
	}

	// Convert to ARGB and premultiply alpha
	pixel_data := ([^]u32)(data)
	for i in 0 ..< len(image.pixels) {
		col := image.pixels[i]
		a := u32(col.a)
		r := u32(col.r) * a / 255
		g := u32(col.g) * a / 255
		b := u32(col.b) * a / 255
		pixel_data[i] = a << 24 | r << 16 | g << 8 | b
	}

	// The pool can go away immediately: the mapping stays alive until every buffer made from it
	// has been destroyed.
	pool := wl.shm_create_pool(s.shm, c.int32_t(fd), c.int32_t(size))
	defer wl.shm_pool_destroy(pool)

	buffer := wl.shm_pool_create_buffer(
		pool, 0,
		c.int32_t(image.width), c.int32_t(image.height), c.int32_t(stride),
		wl.SHM_FORMAT_ARGB8888,
	)

	surface := wl.compositor_create_surface(s.compositor)
	wl.surface_attach(surface, buffer, 0, 0)

	cursor := WL_Cursor {
		surface   = surface,
		hotspot   = hotspot,
		width     = image.width,
		height    = image.height,
		buffer    = buffer,
		data      = data,
		data_size = size,
		viewport  = wl.wp_viewporter_get_viewport(s.viewporter, surface),
	}

	// Sets the viewport destination and commits the surface.
	wl_apply_cursor_scale(&cursor)

	handle, add_err := hm.add(&s.custom_cursors, cursor)

	if add_err != nil {
		log.errorf("Failed to create cursor. Error: %v", add_err)
		wl.wp_viewport_destroy(cursor.viewport)
		wl.surface_destroy(cursor.surface)
		wl.buffer_destroy(cursor.buffer)
		linux.munmap(cursor.data, uint(cursor.data_size))
		return {}
	}

	return handle
}

// A cursor image is sized in physical pixels, like everything else in Karl2D, but a Wayland surface
// is sized in logical pixels. Without this a 128x128 cursor would cover 256x256 physical pixels on
// a 2x display, i.e. twice the size of a 128x128 sprite drawn by the game.
//
// The viewport makes the compositor scale the buffer down to the logical size that the image's
// physical size corresponds to. We use a viewport rather than `wl_surface.set_buffer_scale`
// because the latter only takes integers, so it cannot express a fractional scale, and because it
// raises a protocol error unless the buffer size divides evenly by the scale, which would kill the
// game for something as arbitrary as an odd-sized cursor image.
wl_apply_cursor_scale :: proc(cursor: ^WL_Cursor) {
	// A destination of zero is a protocol error, so tiny cursors stay at one logical pixel.
	dest_width := max(1, int(math.round(f32(cursor.width) / s.scale)))
	dest_height := max(1, int(math.round(f32(cursor.height) / s.scale)))

	wl.wp_viewport_set_destination(cursor.viewport, i32(dest_width), i32(dest_height))
	wl.surface_commit(cursor.surface)

	cursor.built_for_scale = s.scale
}

// Puts `cursor` on screen. `serial` must come from the most recent pointer enter event. Used both
// when the game sets a cursor and when the pointer re-enters the window, which is its own path
// through the compositor and needs the same scaling applied.
wl_point_at_cursor :: proc(cursor: ^WL_Cursor, serial: u32) {
	// The scale can change while the game runs, for instance when the window is dragged to a
	// monitor with different DPI settings.
	if cursor.built_for_scale != s.scale {
		wl_apply_cursor_scale(cursor)
	}

	// The hotspot is in surface-local (logical) coordinates, but Karl2D takes it in physical
	// pixels, like the image it belongs to.
	wl.pointer_set_cursor(
		s.pointer,
		serial,
		cursor.surface,
		c.int32_t(math.round(f32(cursor.hotspot.x) / s.scale)),
		c.int32_t(math.round(f32(cursor.hotspot.y) / s.scale)),
	)
}

wl_set_cursor :: proc(cursor: Cursor) {
	// Reject a stale handle before storing it, so the cursor on screen is left alone on a
	// programming error rather than silently reverting to the default.
	if handle, is_custom := cursor.(Custom_Cursor); is_custom {
		if hm.get(&s.custom_cursors, handle) == nil {
			log.errorf("Trying to set invalid cursor %v. It may have been destroyed.", handle)
			return
		}
	}

	s.current_cursor = cursor
	wl_apply_cursor()
}

wl_standard_cursor_shape :: proc(standard: Standard_Cursor) -> wl.WP_Cursor_Shape {
	switch standard {
	case .Default:     return .Default
	case .Text:        return .Text
	case .Hand:        return .Pointer
	case .Crosshair:   return .Crosshair
	case .Wait:        return .Wait
	case .Progress:    return .Progress
	case .Resize_EW:   return .Ew_Resize
	case .Resize_NS:   return .Ns_Resize
	case .Resize_NESW: return .Nesw_Resize
	case .Resize_NWSE: return .Nwse_Resize
	case .Move:        return .Move
	case .Not_Allowed: return .Not_Allowed
	}

	return .Default
}

wl_destroy_custom_cursor :: proc(custom_cursor: Custom_Cursor) {
	cd := hm.get(&s.custom_cursors, custom_cursor)

	if cd == nil {
		log.errorf(
			"Trying to destroy invalid cursor %v. It may already be destroyed.",
			custom_cursor,
		)
		return
	}

	// Detach from the surface before the buffer and its memory go away.
	wl.wp_viewport_destroy(cd.viewport)
	wl.surface_destroy(cd.surface)
	wl.buffer_destroy(cd.buffer)
	linux.munmap(cd.data, uint(cd.data_size))
	hm.remove(&s.custom_cursors, custom_cursor)

	// If that was the cursor on screen it no longer resolves, so re-applying falls back to the
	// default. Cheap enough to do unconditionally.
	wl_apply_cursor()
}

wl_set_internal_state :: proc(state: rawptr) {
	assert(state != nil)
	s = (^WL_State)(state)
}

WL_Cursor :: struct {
	handle:   Custom_Cursor,
	surface:  ^wl.Surface,
	hotspot:  [2]int,

	// Size of the image in physical pixels.
	width:    int,
	height:   int,

	// The compositor may read from the buffer at any point while it is attached to the surface, so
	// the buffer and its mapping have to stay alive for as long as the cursor does.
	buffer:    ^wl.Buffer,
	data:      rawptr,
	data_size: int,

	// Scales the surface down from physical to logical pixels, see `wl_apply_cursor_scale`.
	viewport:        ^wl.WP_Viewport,
	built_for_scale: f32,
}

WL_State :: struct {
	allocator: runtime.Allocator,

	screen_width: int,
	screen_height: int,

	// The last width/height we've gotten from wayland: Keeping this separate from screen_width and
	// screen_height simplifies state management a bit.
	last_configure_width: int,
	last_configure_height: int,
	last_configure_windowed_width: int,
	last_configure_windowed_height: int,

	events: [dynamic]Event,
	window_mode: Window_Mode,

	odin_ctx: runtime.Context,
	
	display: ^wl.Display,
	surface: ^wl.Surface,
	compositor: ^wl.Compositor,
	window: ^wl.EGL_Window,
	toplevel: ^wl.XDG_Toplevel,
	viewporter: ^wl.WP_Viewporter,
	viewport: ^wl.WP_Viewport,
	decoration_manager: ^wl.ZXDG_Decoration_Manager_V1,
	fractional_scale_manager: ^wl.WP_Fractional_Scale_Manager_V1,

	xdg_base: ^wl.XDG_WM_Base,
	seat: ^wl.Seat,
	scale: f32,

	keyboard: ^wl.Keyboard,
	pointer: ^wl.Pointer,
	pointer_enter_serial: u32,
	cursor_hidden: bool,
	shm: ^wl.SHM,
	cursor_surface: ^wl.Surface,
	cursor_theme: ^wl.Cursor_Theme,

	// Scales the theme cursor surface down to a fixed 24x24 logical size. See wl_load_cursor_theme
	// and wl_apply_cursor.
	cursor_viewport: ^wl.WP_Viewport,

	pointer_constraints: ^wl.ZWP_Pointer_Constraints_V1,
	relative_pointer_manager: ^wl.ZWP_Relative_Pointer_Manager_V1,
	locked_pointer: ^wl.ZWP_Locked_Pointer_V1,
	relative_pointer: ^wl.ZWP_Relative_Pointer_V1,

	custom_cursors: hm.Dynamic_Handle_Map(WL_Cursor, Custom_Cursor),

	// The cursor most recently passed to wl_set_cursor. The zero value is Standard_Cursor.Default.
	current_cursor: Cursor,

	cursor_shape_manager: ^wl.WP_Cursor_Shape_Manager_V1,
	cursor_shape_device:  ^wl.WP_Cursor_Shape_Device_V1,

	// True if toplevel_listener.configure has run
	configured: bool,

	window_render_glue: Window_Render_Glue,
}

s: ^WL_State

