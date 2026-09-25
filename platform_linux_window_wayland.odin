#+build linux
#+private file
package karl2d

@(private="package")
LINUX_WINDOW_WAYLAND :: Linux_Window_Interface {
	state_size = wl_state_size,
	try_load = wl_try_load,
	init = wl_init,
	shutdown = wl_shutdown,
	get_window_render_glue = wl_get_window_render_glue,
	get_events = wl_get_events,
	before_present = wl_before_present,
	set_title = wl_set_title,
	get_screen_width = wl_get_screen_width,
	get_screen_height = wl_get_screen_height,
	set_position = wl_set_position,
	get_position = wl_get_position,
	set_screen_size = wl_set_screen_size,
	get_window_scale = wl_get_window_scale,
	set_window_mode = wl_set_window_mode,
	set_window_icon = wl_set_window_icon,
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
import "core:os"
import "core:sys/linux"
import "core:time"
import hm "core:container/handle_map"

import "log"
import wl "platform_bindings/linux/wayland"
import xkb "platform_bindings/linux/xkbcommon"

_ :: log
_ :: fmt

// What size the theme cursor ends up on screen, in logical pixels. The theme is loaded at
// THEME_CURSOR_SIZE*scale physical pixels and a viewport scales it back down to this.
THEME_CURSOR_SIZE :: 24

@(private="package")

wl_state_size :: proc() -> int {
	return size_of(WL_State)
}

wl_try_load :: proc(
	failure_reason_allocator: runtime.Allocator,
) -> (
	failure_reason: string,
	ok: bool,
) {
	// Load the wayland shared library
	if missing, load_ok := wl.load(); !load_ok {
		return fmt.aprintf("Not using Wayland. Could not load %v.", missing,
			allocator = failure_reason_allocator), false
	}

	// The wayland library being installed does not mean there is a compositor to talk to. Connect
	// and throw the connection away again. `wl_init` will reconnect if wayland gets used.
	display := wl.display_connect(nil)

	if display == nil {
		wl.unload()
		return "Not using Wayland. Could not connect to a compositor.", false
	}

	wl.display_disconnect(display)

	if missing, load_ok := xkb.load(); !load_ok {
		wl.unload()
		return fmt.aprintf("Not using Wayland. Could not load %v.", missing,
			allocator = failure_reason_allocator), false
	}

	return "", true
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

	s.xkb_context = xkb.context_new(.No_Flags)

	s.display = wl.display_connect(nil)

	display_registry := wl.display_get_registry(s.display)
	wl.add_listener(display_registry, &registry_listener, nil)

	// registry_listener will collect a lot of object. This will make sure that listener runs.
	wl.display_roundtrip(s.display)
	wl.add_listener(s.seat, &seat_listener, nil)

	// Initializes pointer and keyboard based on seat capabilities.
	wl.display_roundtrip(s.display)

	// Some systems, like GNOME, don't support the decoration manager (server-side decorations). In
	// that case we will draw them ourselves using the `wlcsd_` calls in this file.
	custom_decorations_requested := os.get_env("KARL2D_LINUX_DECORATIONS", frame_allocator) == "custom"
	use_custom_decorations := s.decoration_manager == nil || custom_decorations_requested

	// Sets default size that gets used if the compositor doesn't suggest a size. Used by
	// `configure` of `toplevel_listener`.
	s.last_configure_width = screen_width
	s.last_configure_height = screen_height
	s.last_configure_windowed_width = screen_width
	s.last_configure_windowed_height = screen_height

	s.surface = wl.compositor_create_surface(s.compositor)
	log.ensure(s.surface != nil, "Error creating Wayland surface")
	
	// Makes sure the window does "pings" that keeps it alive.
	wl.add_listener(s.xdg_base, &wm_base_listener, nil)
	s.xdg_surface = wl.xdg_wm_base_get_xdg_surface(s.xdg_base, s.surface)

	// Top-level means an application at the top of the window hierarchy. The callback in the
	// top-level listener effectively creates a window handle.
	s.toplevel = wl.xdg_surface_get_toplevel(s.xdg_surface)
	wl.add_listener(s.toplevel, &toplevel_listener, nil)
	wl.add_listener(s.xdg_surface, &window_listener, nil)

	// Initialize the custom decorations before anything that draws or sizes the frame, since all
	// of that goes through them. The first configure lays them out again around whatever size the
	// compositor settles on.
	if use_custom_decorations {
		s.csd = wlcsd_init(
			s.surface,
			s.xdg_surface,
			s.viewporter,
			s.seat,
			s.compositor,
			s.subcompositor,
			s.toplevel,
			s.last_configure_width,
			s.last_configure_height,
			options.window_mode,
			allocator,
		)
	}

	wl_set_title(window_title)
	wl_set_window_mode(options.window_mode)

	if s.decoration_manager != nil {
		decoration := wl.zxdg_decoration_manager_v1_get_toplevel_decoration(
			s.decoration_manager,
			s.toplevel,
		)

		// This controls if we get titlebar and buttons. This is important even if using client-side
		// decorations. For example, if you force client-side decorations (using environment
		// variable `KARL2D_LINUX_DECORATIONS=custom`) then the server-side decorations may still
		// paint its own titlebar and buttons. You'd get two titlebars!
		mode := u32(wl.ZXDG_TOPLEVEL_DECORATION_V1_MODE_SERVER_SIDE)

		if s.csd != nil {
			mode = wl.ZXDG_TOPLEVEL_DECORATION_V1_MODE_CLIENT_SIDE
		}

		wl.zxdg_toplevel_decoration_v1_set_mode(decoration, mode)
	}

	if s.fractional_scale_manager != nil {
		fractional_scale := wl.wp_fractional_scale_manager_get_fractional_scale(
			s.fractional_scale_manager,
			s.surface,
		)

		wl.add_listener(fractional_scale, &fractional_scale_listener, nil)
	}

	if s.relative_pointer_manager != nil && s.pointer != nil {
		s.relative_pointer = wl.zwp_relative_pointer_manager_v1_get_relative_pointer(
			s.relative_pointer_manager,
			s.pointer,
		)

		wl.add_listener(s.relative_pointer, &relative_pointer_listener, nil)
	} else {
		log.warn("Relative pointer not available: mouse locking will not work")
	}

	s.cursor_surface = wl.compositor_create_surface(s.compositor)
	s.cursor_viewport = wl.wp_viewporter_get_viewport(s.viewporter, s.cursor_surface)
	wl.wp_viewport_set_destination(s.cursor_viewport, THEME_CURSOR_SIZE, THEME_CURSOR_SIZE)

	// The cursor shape protocol lets the compositor render its own default cursor at the correct
	// size and DPI, so the theme is only needed as a fallback for compositors without it.
	if s.cursor_shape_device == nil {
		wl_load_cursor_theme()
	}

	s.viewport = wl.wp_viewporter_get_viewport(s.viewporter, s.surface)

	wl.surface_commit(s.surface)

	// Wait for the first configure: it's what creates the EGL window.
	for !s.configured {
		if wl.display_dispatch(s.display) < 0 {
			break
		}
	}

	log.ensure(s.window != nil, "Wayland compositor never sent an initial configure")

	when RENDER_BACKEND_NAME == "gl" {
		s.window_render_glue = make_linux_gl_wayland_glue(s.display, s.surface, s.window, s.allocator)
	} else when RENDER_BACKEND_NAME == "nil" {
		s.window_render_glue = {}
	} else {
		#panic("Unsupported combo of Linux + Wayland and render backend '" + RENDER_BACKEND_NAME + "'")
	}

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

		case wl.subcompositor_interface.name:
			s.subcompositor = wl.registry_bind(
				wl.Subcompositor,
				registry,
				name,
				&wl.subcompositor_interface,
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

		case wl.xdg_toplevel_icon_manager_v1_interface.name:
			s.toplevel_icon_manager = wl.registry_bind(
				wl.XDG_Toplevel_Icon_Manager_V1,
				registry,
				name,
				&wl.xdg_toplevel_icon_manager_v1_interface,
				version,
			)
		}
	},
	global_remove = proc "c" (data: rawptr, registry: ^wl.Registry, name: u32) {},
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

		if s.csd != nil {
			active := false
			maximized := false

			if states != nil && states.data != nil {
				states_data := ([^]u32)(states.data)[:states.size/size_of(u32)]
				for state in states_data {
					switch state {
					case wl.XDG_TOPLEVEL_STATE_ACTIVATED:
						active = true

					case wl.XDG_TOPLEVEL_STATE_MAXIMIZED:
						maximized = true
					}
				}
			}

			wlcsd_set_toplevel_state(s.csd, active, maximized)

			if h > 0 && s.window_mode != .Borderless_Fullscreen {
				h = max(1, h - WLCSD_TITLEBAR_HEIGHT)
			}
		}

		new_width: int
		new_height: int

		if s.window_mode == .Windowed {
			// Fixed-size window: The user decides the size
			new_width = s.last_configure_windowed_width
			new_height = s.last_configure_windowed_height
		} else {
			// Zero means the compositor lets us pick that dimension.
			new_width = w != 0 ? w : s.last_configure_windowed_width
			new_height = h != 0 ? h : s.last_configure_windowed_height
		}

		window_resized := new_width != s.last_configure_width || new_height != s.last_configure_height

		if window_resized || !s.configured {
			s.screen_width = int(f32(new_width) * s.scale)
			s.screen_height = int(f32(new_height) * s.scale)

			if !s.configured {
				s.window = wl.egl_window_create(s.surface, i32(s.screen_width), i32(s.screen_height))
			} else {
				wl.egl_window_resize(s.window, i32(s.screen_width), i32(s.screen_height), 0, 0)
			}

			wl.wp_viewport_set_destination(s.viewport, i32(new_width), i32(new_height))
			s.last_configure_width = new_width
			s.last_configure_height = new_height

			if s.window_mode == .Windowed || s.window_mode == .Windowed_Resizable {
				s.last_configure_windowed_width = new_width
				s.last_configure_windowed_height = new_height
			}

			if s.csd != nil {
				wlcsd_set_window_size(s.csd, s.last_configure_width, s.last_configure_height)
				wlcsd_mark_dirty(s.csd)
			}

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
	leave = proc "c" (data: rawptr, keyboard: ^wl.Keyboard, serial: c.uint32_t, surface: ^wl.Surface) {
		// Avoids key repeats happening forever, that state is cleared while the window is inactive.
		s.repeat_key = .None
	},
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
		if s.xkb_state == nil {
			return
		}

		xkb.state_update_mask(s.xkb_state, mods_depressed, mods_latched, mods_locked, 0, 0, group)
	},
	repeat_info = proc "c" (
		data: rawptr,
		keyboard: ^wl.Keyboard,
		rate: c.int32_t,
		delay: c.int32_t,
	) {
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
		s.pointer_x = surface_x
		s.pointer_y = surface_y

		if s.csd != nil {
			wlcsd_set_pointer_surface(s.csd, surface)

			if wlcsd_pointer_over_frame(s.csd) {
				wlcsd_pointer_moved(
					s.csd,
					wl.fixed_to_f32(surface_x),
					wl.fixed_to_f32(surface_y),
				)
			}
		}

		wl_apply_cursor()
	},
	leave = proc "c" (
		data: rawptr,
		pointer: ^wl.Pointer,
		serial: c.uint32_t,
		surface: ^wl.Surface,
	) {
		context = s.odin_ctx

		if s.csd != nil {
			if wlcsd_pointer_over_frame(s.csd) {
				wlcsd_pointer_left(s.csd)
			}
			
			wlcsd_set_pointer_surface(s.csd, nil)
		}
	},
	motion = proc "c" (
		data: rawptr,
		pointer: ^wl.Pointer,
		time: c.uint32_t,
		surface_x: wl.Fixed,
		surface_y: wl.Fixed,
	) {
		context = s.odin_ctx

		s.pointer_x = surface_x
		s.pointer_y = surface_y

		if s.csd != nil && wlcsd_pointer_over_frame(s.csd) {
			local_x := wl.fixed_to_f32(surface_x)
			local_y := wl.fixed_to_f32(surface_y)
			wlcsd_pointer_moved(s.csd, local_x, local_y)

			if wlcsd_cursor(s.csd, local_x, local_y) != s.last_csd_cursor {
				wl_apply_cursor()
			}

			return
		}

		append(&s.events, Event_Mouse_Move {
			position = {
				math.floor(wl.fixed_to_f32(surface_x) * s.scale),
				math.floor(wl.fixed_to_f32(surface_y) * s.scale),
			},
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

		if s.csd != nil && wlcsd_pointer_over_frame(s.csd) {
			csd_button, csd_button_pressed := wlcsd_pointer_button(
				s.csd,
				u32(button),
				u32(state),
				u32(time),
				u32(serial),
				wl.fixed_to_f32(s.pointer_x),
				wl.fixed_to_f32(s.pointer_y),
			)

			if csd_button_pressed {
				switch csd_button {
				case .Close:
					append(&s.events, Event_Close_Window_Requested{})

				case .Maximize:
					if s.csd.maximized {
						wl.xdg_toplevel_unset_maximized(s.toplevel)
					} else {
						wl.xdg_toplevel_set_maximized(s.toplevel)
					}

				case .Minimize:
					wl.xdg_toplevel_set_minimized(s.toplevel)
				}
			}

			return
		}

		btn: Mouse_Button
		switch button {
		case wl.BTN_LEFT: btn = .Left
		case wl.BTN_MIDDLE: btn = .Middle
		case wl.BTN_RIGHT: btn = .Right
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

		if s.csd != nil && wlcsd_pointer_over_frame(s.csd) {
			return
		}

		// Wayland measures down and right as positive, so the vertical axis needs flipping.
		switch axis {
		case wl.POINTER_AXIS_VERTICAL_SCROLL:
			append(&s.events, Event_Mouse_Wheel {
				delta = f32(math.sign(value)) * -1,
			})

		case wl.POINTER_AXIS_HORIZONTAL_SCROLL:
			append(&s.events, Event_Mouse_Wheel_Horizontal {
				delta = f32(math.sign(value)),
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

		if s.configured {
			wl.egl_window_resize(s.window, i32(s.screen_width), i32(s.screen_height), 0, 0)
		}

		if s.csd != nil {
			wlcsd_mark_dirty(s.csd)
		}

		// The cursor theme is loaded at a fixed physical size, so it needs reloading whenever
		// the scale changes.
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
	if s.csd != nil {
		wlcsd_destroy(s.csd)
	}

	for it := hm.dynamic_iterator_make(&s.custom_cursors); cd, _ in hm.dynamic_iterate(&it) {
		wl.wp_viewport_destroy(cd.viewport)
		wl.surface_destroy(cd.surface)
		wl_destroy_shared_memory_image(cd.image)
	}
	
	hm.dynamic_destroy(&s.custom_cursors)

	wl_destroy_toplevel_icon(s.toplevel_icon)
	s.toplevel_icon = {}

	if s.toplevel_icon_manager != nil {
		wl.xdg_toplevel_icon_manager_v1_destroy(s.toplevel_icon_manager)
		s.toplevel_icon_manager = nil
	}

	if s.cursor_shape_device != nil {
		wl.cursor_shape_device_destroy(s.cursor_shape_device)
		s.cursor_shape_device = nil
	}

	if s.cursor_shape_manager != nil {
		wl.cursor_shape_manager_destroy(s.cursor_shape_manager)
		s.cursor_shape_manager = nil
	}

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

wl_before_present :: proc() {
	if s.csd != nil {
		wlcsd_paint(s.csd, s.scale)
	}
}

wl_get_events :: proc(events: ^[dynamic]Event) {
	wl.display_dispatch_pending(s.display)

	// No key repeat events in wayland, we make them ourselves using timers using info reported by
	// `repeat_info`.
	if s.repeat_key != .None && s.repeat_rate > 0 {
		now := time.tick_now()
		interval := time.Second / time.Duration(s.repeat_rate)

		// Capped so that a long stall (a breakpoint, a slow loading frame) doesn't produce a huge
		// burst of repeats.
		REPEATS_PER_FRAME_MAX :: 32

		repeats := 0

		for time.tick_diff(s.repeat_next_tick, now) >= 0 {
			append(&s.events, Event_Key_Repeat {
				key = s.repeat_key,
			})
			
			_wl_append_typed_runes(s.repeat_xkb_keycode)
			s.repeat_next_tick = time.tick_add(s.repeat_next_tick, interval)
			repeats += 1

			// Cap hit: Skip remaining repeats instead of spreading them across frames.
			if repeats == REPEATS_PER_FRAME_MAX {
				s.repeat_next_tick = time.tick_add(now, interval)
				break
			}
		}
	}

	append(events, ..s.events[:])
	runtime.clear(&s.events)
}

wl_set_title :: proc(title: string) {
	// Sets title in window list. Sets title on titlebar if using server-side decorations.
	wl.xdg_toplevel_set_title(s.toplevel, strings.clone_to_cstring(title, frame_allocator))

	if s.csd != nil {
		wlcsd_set_title(s.csd, title)
	}
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

wl_get_position :: proc() -> Vec2 {
	log.error("get_position not implemented when using wayland")
	return {}
}

wl_set_screen_size :: proc(w, h: int) {
	s.screen_width = int(f32(w) * s.scale)
	s.screen_height = int(f32(h) * s.scale)
	s.last_configure_width = w
	s.last_configure_height = h

	if s.window_mode == .Windowed || s.window_mode == .Windowed_Resizable {
		s.last_configure_windowed_width = w
		s.last_configure_windowed_height = h
	}

	if s.configured {
		wl.egl_window_resize(s.window, i32(s.screen_width), i32(s.screen_height), 0, 0)
	}

	wl.wp_viewport_set_destination(s.viewport, i32(w), i32(h))

	if s.csd != nil {
		wlcsd_set_window_size(s.csd, s.last_configure_width, s.last_configure_height)
		wlcsd_mark_dirty(s.csd)
	}
}

wl_get_window_scale :: proc() -> f32 {
	return s.scale
}

wl_set_window_mode :: proc(window_mode: Window_Mode) {
	s.window_mode = window_mode
	 
	switch window_mode {
	case .Windowed:
		wl.xdg_toplevel_unset_fullscreen(s.toplevel)

		w := s.last_configure_windowed_width
		h := s.last_configure_windowed_height

		if s.csd != nil {
			h += WLCSD_TITLEBAR_HEIGHT
		}

		wl.xdg_toplevel_set_max_size(s.toplevel, i32(w), i32(h))
		wl.xdg_toplevel_set_min_size(s.toplevel, i32(w), i32(h))

	case .Windowed_Resizable:
		wl.xdg_toplevel_unset_fullscreen(s.toplevel)
		wl.xdg_toplevel_set_max_size(s.toplevel, 0, 0)
		wl.xdg_toplevel_set_min_size(s.toplevel, 0, 0)

	case .Borderless_Fullscreen:
		wl.xdg_toplevel_set_fullscreen(s.toplevel, nil)
	}

	// The frame comes and goes with fullscreen, and the window is a different size with it than
	// without it.
	if s.csd != nil {
		wlcsd_set_window_mode(s.csd, s.window_mode)
		wlcsd_mark_dirty(s.csd)
	}
}

wl_set_window_icon :: proc(image: Image) -> bool {
	if s.csd != nil {
		wlcsd_set_icon(s.csd, image)

		// It's OK to not have a top-level icon manager if we use CSD. But if it does exist then we
		// can still set the icon on it, which may affect the taskbar etc.
		if s.toplevel_icon_manager == nil {
			return true
		}
	}

	if s.toplevel_icon_manager == nil {
		return false
	}

	// The protocol only takes square buffers. A non-square image goes in the middle of one.
	size := max(image.width, image.height)
	dest, dest_ok := wl_create_shared_memory_image("karl2d-icon", size, size)

	if !dest_ok {
		return false
	}

	// Convert to ARGB and premultiply alpha. A fresh shm buffer is all zeroes, so any padding
	// around a non-square image is already transparent.
	offset_x := (size - image.width)/2
	offset_y := (size - image.height)/2

	for y in 0..<image.height {
		for x in 0..<image.width {
			col := image.pixels[y*image.width + x]
			a := u32(col.a)
			r := u32(col.r) * a / 255
			g := u32(col.g) * a / 255
			b := u32(col.b) * a / 255
			dest.pixels[(offset_y + y)*size + offset_x + x] = a << 24 | r << 16 | g << 8 | b
		}
	}

	icon := WL_Toplevel_Icon {
		icon = wl.xdg_toplevel_icon_manager_v1_create_icon(s.toplevel_icon_manager),
		image = dest,
	}

	// Scale 1 means this isn't a HiDPI variant. The compositor scales our one buffer to any size.
	wl.xdg_toplevel_icon_v1_add_buffer(icon.icon, dest.buffer, 1)
	wl.xdg_toplevel_icon_manager_v1_set_icon(s.toplevel_icon_manager, s.toplevel, icon.icon)

	wl_destroy_toplevel_icon(s.toplevel_icon)
	s.toplevel_icon = icon
	return true
}

wl_destroy_toplevel_icon :: proc(icon: WL_Toplevel_Icon) {
	if icon.icon != nil {
		wl.xdg_toplevel_icon_v1_destroy(icon.icon)
	}

	wl_destroy_shared_memory_image(icon.image)
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
		// Only used when pointer is locked! Makes mouse move events and teleports it back to center
		if s.locked_pointer == nil {
			return
		}

		context = s.odin_ctx
		cx := f32(s.screen_width / 2)
		cy := f32(s.screen_height / 2)
		fdx := wl.fixed_to_f32(dx_unaccel)
		fdy := wl.fixed_to_f32(dy_unaccel)

		append(&s.events, Event_Mouse_Move {
			position = {cx + fdx, cy + fdy},
		})

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

		// Makes sure we have the correct "previous position".
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

// Use as a fallback when wp_cursor_shape_manager_v1 is missing. Scales the cursor by the DPI scale.
// Since the scale is explicitly used, this is re-run when the scale changes.
wl_load_cursor_theme :: proc() {
	if s.cursor_theme != nil {
		wl.cursor_theme_destroy(s.cursor_theme)
	}

	theme_size := max(1, int(math.round(THEME_CURSOR_SIZE * s.scale)))
	s.cursor_theme = wl.cursor_theme_load(nil, c.int(theme_size), s.shm)
}

// Sets cursor based on both `s.cursor_hidden` and `s.current_cursor`. Re-entering window reruns
// this proc, since it is forgotten when the cursor leaves the window.
wl_apply_cursor :: proc() {
	if s.pointer == nil || s.cursor_surface == nil {
		return
	}

	cursor := s.current_cursor

	// Let CSD frame dictate cursor if we are over the frame.
	if s.csd != nil && wlcsd_pointer_over_frame(s.csd) {
		s.last_csd_cursor = wlcsd_cursor(
			s.csd,
			wl.fixed_to_f32(s.pointer_x),
			wl.fixed_to_f32(s.pointer_y),
		)

		cursor = s.last_csd_cursor
	} else {
		if s.cursor_hidden {
			wl.pointer_set_cursor(s.pointer, s.pointer_enter_serial, nil, 0, 0)
			return
		}
	}
	
	// For showing default cursor when the custom cursor is actually destroyed.
	if cc, is_custom := cursor.(Custom_Cursor); is_custom {
		if !hm.is_valid(&s.custom_cursors, cc) {
			cursor = Standard_Cursor.Default
		}
	}

	switch cur in cursor {
	case Custom_Cursor:
		if cc := hm.get(&s.custom_cursors, cur); cc != nil {
			// The scale can change while the game runs, for instance when the window is dragged to a
			// monitor with different DPI settings.
			if cc.built_for_scale != s.scale {
				wl_apply_cursor_scale(cc)
			}
			
			wl.pointer_set_cursor(
				s.pointer,
				s.pointer_enter_serial,
				cc.surface,
				c.int32_t(math.round(f32(cc.hotspot.x) / s.scale)),
				c.int32_t(math.round(f32(cc.hotspot.y) / s.scale)),
			)
		}
	case Standard_Cursor:
		if s.cursor_shape_device != nil {
			wl.cursor_shape_device_set_shape(
				s.cursor_shape_device,
				s.pointer_enter_serial,
				wl_standard_cursor_shape(cur),
			)
			break
		}

		if s.cursor_theme == nil {
			break
		}

		name, fallback := linux_standard_cursor_names(cur)
		theme_cursor := wl.cursor_theme_get_cursor(s.cursor_theme, name)

		if theme_cursor == nil {
			theme_cursor = wl.cursor_theme_get_cursor(s.cursor_theme, fallback)
		}

		// The theme has no cursor under either name. Leave the current one.
		if theme_cursor == nil || theme_cursor.image_count == 0 {
			break
		}

		image := theme_cursor.images[0]
		buf := wl.cursor_image_get_buffer(image)

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
}

@(private="package")
WL_Shared_Memory_Image :: struct {
	buffer: ^wl.Buffer,
	pixels: []u32,
	width: int,
	height: int,
}

// Creates a `width` x `height` ARGB buffer that the compositor can use. The compositor is a
// separate process, so this uses handles and stuff to make it possible to for it to read it.
//
// `name` shows up in /proc/.../fd for debugging.
@(private="package")
wl_create_shared_memory_image :: proc(
	name: cstring,
	width: int,
	height: int,
) -> (
	_image: WL_Shared_Memory_Image,
	_ok: bool,
) {
	stride := width*4
	size := stride*height

	fd, fd_err := linux.memfd_create(name, {})
	if fd_err != .NONE {
		log.errorf("Failed creating shm buffer '%s': memfd failed with %v", name, fd_err)
		return
	}

	// The compositor dups the fd in shm_create_pool, so we don't have to keep ours around.
	defer linux.close(fd)

	if trunc_err := linux.ftruncate(fd, i64(size)); trunc_err != .NONE {
		log.errorf("Failed creating shm buffer '%s': ftruncate failed with %v", name, trunc_err)
		return
	}

	data, mmap_err := linux.mmap(0, uint(size), {.READ, .WRITE}, {.SHARED}, fd, 0)
	if mmap_err != .NONE {
		log.errorf("Failed creating shm buffer '%s': mmap failed with %v", name, mmap_err)
		return
	}

	pool := wl.shm_create_pool(s.shm, c.int32_t(fd), c.int32_t(size))

	buffer := wl.shm_pool_create_buffer(
		pool,
		0,
		c.int32_t(width),
		c.int32_t(height),
		c.int32_t(stride),
		wl.SHM_FORMAT_ARGB8888,
	)

	// The pool can go away immediately: the mapping stays alive until every buffer made from it
	// has been destroyed.
	wl.shm_pool_destroy(pool)

	image := WL_Shared_Memory_Image {
		buffer = buffer,
		pixels = ([^]u32)(data)[:width*height],
		width = width,
		height = height,
	}

	return image, true
}

@(private="package")
wl_destroy_shared_memory_image :: proc(image: WL_Shared_Memory_Image) {
	if image.buffer != nil {
		wl.buffer_destroy(image.buffer)
	}

	if image.pixels != nil {
		linux.munmap(raw_data(image.pixels), uint(len(image.pixels)*size_of(u32)))
	}
}

wl_create_custom_cursor :: proc(image: Image, hotspot: [2]int) -> (Custom_Cursor, bool) {
	dest, dest_ok := wl_create_shared_memory_image("cursor", image.width, image.height)

	if !dest_ok {
		return {}, false
	}

	// Convert to ARGB and premultiply alpha
	for i in 0..<len(image.pixels) {
		col := image.pixels[i]
		a := u32(col.a)
		r := u32(col.r) * a / 255
		g := u32(col.g) * a / 255
		b := u32(col.b) * a / 255
		dest.pixels[i] = a << 24 | r << 16 | g << 8 | b
	}

	surface := wl.compositor_create_surface(s.compositor)
	wl.surface_attach(surface, dest.buffer, 0, 0)

	cursor := WL_Cursor {
		surface  = surface,
		hotspot  = hotspot,
		width    = image.width,
		height   = image.height,
		image    = dest,
		viewport = wl.wp_viewporter_get_viewport(s.viewporter, surface),
	}

	wl_apply_cursor_scale(&cursor)

	handle, add_err := hm.add(&s.custom_cursors, cursor)

	if add_err != nil {
		log.errorf("Failed to create cursor. Error: %v", add_err)
		wl.wp_viewport_destroy(cursor.viewport)
		wl.surface_destroy(cursor.surface)
		wl_destroy_shared_memory_image(cursor.image)
		return {}, false
	}

	return handle, true
}

// The image used by cursors are scaled the window scale. But the size given to compositor needs to
// be the unscaled size. So this unscales the cursor and uses a wayland viewport to scale it.
wl_apply_cursor_scale :: proc(cursor: ^WL_Cursor) {
	// A destination of zero is a protocol error, so tiny cursors stay at one logical pixel.
	dest_width := max(1, int(math.round(f32(cursor.width) / s.scale)))
	dest_height := max(1, int(math.round(f32(cursor.height) / s.scale)))

	wl.wp_viewport_set_destination(cursor.viewport, i32(dest_width), i32(dest_height))
	wl.surface_commit(cursor.surface)

	cursor.built_for_scale = s.scale
}

wl_set_cursor :: proc(cursor: Cursor) {
	// Reject a stale handle, so a programming error leaves the cursor alone.
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
	wl_destroy_shared_memory_image(cd.image)
	hm.remove(&s.custom_cursors, custom_cursor)

	// Falls back to the default if that was the cursor on screen.
	wl_apply_cursor()
}

wl_set_internal_state :: proc(state: rawptr) {
	assert(state != nil)
	s = (^WL_State)(state)
}

WL_Toplevel_Icon :: struct {
	icon: ^wl.XDG_Toplevel_Icon_V1,
	image: WL_Shared_Memory_Image,
}

WL_Cursor :: struct {
	handle: Custom_Cursor,
	surface: ^wl.Surface,
	hotspot: [2]int,

	// Size of the image in physical pixels.
	width: int,
	height: int,

	// The compositor may read from the buffer at any point while it is attached to the surface, so
	// the buffer and its mapping have to stay alive for as long as the cursor does.
	image: WL_Shared_Memory_Image,

	// Scales the surface down from physical to logical pixels, see `wl_apply_cursor_scale`.
	viewport: ^wl.WP_Viewport,
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
	subcompositor: ^wl.Subcompositor,
	window: ^wl.EGL_Window,
	toplevel: ^wl.XDG_Toplevel,
	viewporter: ^wl.WP_Viewporter,
	viewport: ^wl.WP_Viewport,
	decoration_manager: ^wl.ZXDG_Decoration_Manager_V1,

	// Client Side Decorations: Custom decorations that we paint ourselves on for example GNOME.
	csd: ^WLCSD_State,

	// If `csd` is not nil, then this stores the most recent cursor that it returned.
	last_csd_cursor: Standard_Cursor,

	fractional_scale_manager: ^wl.WP_Fractional_Scale_Manager_V1,

	xdg_base: ^wl.XDG_WM_Base,
	xdg_surface: ^wl.XDG_Surface,
	seat: ^wl.Seat,
	scale: f32,

	keyboard: ^wl.Keyboard,
	pointer: ^wl.Pointer,
	pointer_enter_serial: u32,

	pointer_x: wl.Fixed,
	pointer_y: wl.Fixed,
	cursor_hidden: bool,
	shm: ^wl.SHM,
	cursor_surface: ^wl.Surface,
	cursor_theme: ^wl.Cursor_Theme,

	// Scales the theme cursor surface down to THEME_CURSOR_SIZE. See wl_load_cursor_theme and
	// wl_apply_cursor.
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

	toplevel_icon_manager: ^wl.XDG_Toplevel_Icon_Manager_V1,
	toplevel_icon: WL_Toplevel_Icon,

	// True if toplevel_listener.configure has run
	configured: bool,

	window_render_glue: Window_Render_Glue,

	// Used to translate key presses into typed text, taking the current keyboard layout into
	// account. `xkb_keymap`/`xkb_state` are (re)created whenever the compositor sends us a new
	// keymap.
	xkb_context: ^xkb.Context,
	xkb_keymap: ^xkb.Keymap,
	xkb_state: ^xkb.State,

	// Key repeat is handled manually by our code, see `wl_get_events`.
	repeat_rate: c.int32_t,
	repeat_delay: c.int32_t,
	repeat_key: Keyboard_Key,
	repeat_xkb_keycode: c.uint32_t,
	repeat_next_tick: time.Tick,
}

s: ^WL_State
