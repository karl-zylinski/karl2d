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
	set_cursor_locked = wl_set_cursor_locked,
	is_cursor_locked = wl_is_cursor_locked,
	set_internal_state = wl_set_internal_state,
}

import "base:runtime"
import "core:fmt"
import "core:strings"
import "core:c"
import "core:math"
import "core:sys/linux"
import "core:time"

import "log"
import wl "platform_bindings/linux/wayland"
import xkb "platform_bindings/linux/xkbcommon"

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

	s.xkb_context = xkb.context_new(.No_Flags)

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
	s.cursor_theme = wl.cursor_theme_load(nil, 24, s.shm)

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
	keymap = proc "c" (
		data: rawptr,
		keyboard: ^wl.Keyboard,
		format: u32,
		fd: c.int32_t,
		size: u32,
	) {
		context = s.odin_ctx
		defer linux.close(linux.Fd(fd))

		if format != wl.KEYBOARD_KEYMAP_FORMAT_XKB_V1 {
			log.error("Unsupported Wayland keymap format, typed text input won't work")
			return
		}

		mapped, mmap_err := linux.mmap(0, uint(size), {.READ}, {.PRIVATE}, linux.Fd(fd))

		if mmap_err != .NONE {
			log.error("Failed mapping Wayland keymap into memory, typed text input won't work")
			return
		}

		defer linux.munmap(mapped, uint(size))

		// The mapped memory holds a NUL-terminated string, so it's safe to treat as a cstring.
		keymap := xkb.keymap_new_from_string(s.xkb_context, cstring(mapped), .Text_V1, .No_Flags)

		if keymap == nil {
			log.error("Failed parsing Wayland keymap, typed text input won't work")
			return
		}

		if s.xkb_state != nil {
			xkb.state_unref(s.xkb_state)
		}

		if s.xkb_keymap != nil {
			xkb.keymap_unref(s.xkb_keymap)
		}

		s.xkb_keymap = keymap
		s.xkb_state = xkb.state_new(keymap)
	},
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
		context = s.odin_ctx

		if s.xkb_state == nil {
			return
		}

		// The last three arguments here are for depressed/latched/locked *layout* -- we only care
		// about the active layout group, so we leave depressed/latched layout at 0.
		xkb.state_update_mask(s.xkb_state, mods_depressed, mods_latched, mods_locked, 0, 0, group)
	},
	repeat_info = proc "c" (
		data: rawptr,
		keyboard: ^wl.Keyboard,
		rate: c.int32_t,
		delay: c.int32_t,
	) {
		context = s.odin_ctx
		s.repeat_rate = rate
		s.repeat_delay = delay
	},
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

		if s.repeat_xkb_keycode == keycode {
			s.repeat_key = .None
		}

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

		_wl_append_typed_runes(keycode)

		if key != .None && s.repeat_rate > 0 {
			s.repeat_key = key
			s.repeat_xkb_keycode = keycode
			delay := time.Millisecond * time.Duration(s.repeat_delay)
			s.repeat_next_tick = time.tick_add(time.tick_now(), delay)
		}
	}
}

_wl_append_typed_runes :: proc(keycode: c.uint32_t) {
	if s.xkb_state == nil {
		return
	}

	buf: [32]u8
	n := xkb.state_key_get_utf8(
		s.xkb_state, xkb.Keycode(keycode), raw_data(buf[:]), c.size_t(len(buf)),
	)

	if n <= 0 {
		return
	}

	for r in string(buf[:min(int(n), len(buf))]) {
		if is_typable_rune(r) {
			append(&s.events, Event_Typed_Rune { typed = r })
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
		apply_cursor_visibility()
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

		append(&s.events, Event_Window_Scale_Changed {
			scale = scl,
			screen_width = s.screen_width,
			screen_height = s.screen_height,
		})
	},
}

wl_shutdown :: proc() {
	delete(s.events)

	if s.xkb_state != nil {
		xkb.state_unref(s.xkb_state)
	}

	if s.xkb_keymap != nil {
		xkb.keymap_unref(s.xkb_keymap)
	}

	if s.xkb_context != nil {
		xkb.context_unref(s.xkb_context)
	}
}

wl_get_window_render_glue :: proc() -> Window_Render_Glue {
	return s.window_render_glue
}

wl_get_events :: proc(events: ^[dynamic]Event) {
	wl.display_dispatch_pending(s.display)

	// Wayland compositors don't send repeat events -- we have to synthesize them ourselves from
	// the rate/delay reported by the keyboard's `repeat_info` event. Capped at a fixed number of
	// iterations so a long-paused/stalled frame can't spin here forever.
	if s.repeat_key != .None && s.repeat_rate > 0 {
		now := time.tick_now()
		interval := time.Second / time.Duration(s.repeat_rate)

		for i := 0; i < 32 && time.tick_diff(s.repeat_next_tick, now) >= 0; i += 1 {
			append(&s.events, Event_Key_Repeat {
				key = s.repeat_key,
			})
			_wl_append_typed_runes(s.repeat_xkb_keycode)
			s.repeat_next_tick = time.tick_add(s.repeat_next_tick, interval)
		}
	}

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
	apply_cursor_visibility()
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

wl_set_cursor_locked :: proc(locked: bool) {
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

wl_is_cursor_locked :: proc() -> bool {
	return s.locked_pointer != nil
}

apply_cursor_visibility :: proc() {
	if s.pointer == nil {
		return
	}

	if s.cursor_hidden {
		wl.pointer_set_cursor(s.pointer, s.pointer_enter_serial, nil, 0, 0)
	} else {
		// Restore the default cursor. This would also happen if you leave and re-enter wind.
		// This makes it happen instantly.
		cursor := wl.cursor_theme_get_cursor(s.cursor_theme, "left_ptr")

		if cursor != nil && cursor.image_count > 0 {
			image := cursor.images[0]
			buf := wl.cursor_image_get_buffer(image)
			
			wl.pointer_set_cursor(
				s.pointer,
				s.pointer_enter_serial,
				s.cursor_surface,
				i32(image.hotspot_x),
				i32(image.hotspot_y),
			)

			wl.surface_attach(s.cursor_surface, buf, 0, 0)
			wl.surface_commit(s.cursor_surface)
		}
	}
}

wl_set_internal_state :: proc(state: rawptr) {
	assert(state != nil)
	s = (^WL_State)(state)
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

	pointer_constraints: ^wl.ZWP_Pointer_Constraints_V1,
	relative_pointer_manager: ^wl.ZWP_Relative_Pointer_Manager_V1,
	locked_pointer: ^wl.ZWP_Locked_Pointer_V1,
	relative_pointer: ^wl.ZWP_Relative_Pointer_V1,

	// True if toplevel_listener.configure has run
	configured: bool,

	window_render_glue: Window_Render_Glue,

	// Used to translate key presses into typed text, taking the current keyboard layout into
	// account. `xkb_keymap`/`xkb_state` are (re)created whenever the compositor sends us a new
	// keymap.
	xkb_context: ^xkb.Context,
	xkb_keymap: ^xkb.Keymap,
	xkb_state: ^xkb.State,

	// Key repeat is synthesized by us -- see `wl_get_events` -- since Wayland compositors don't
	// send repeat events themselves.
	repeat_rate: c.int32_t,
	repeat_delay: c.int32_t,
	repeat_key: Keyboard_Key,
	repeat_xkb_keycode: c.uint32_t,
	repeat_next_tick: time.Tick,
}

s: ^WL_State

