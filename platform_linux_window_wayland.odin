#+build linux
package karl2d

@(private="package")
LINUX_WINDOW_WAYLAND :: Linux_Window_Interface {
	state_size = wl_state_size,
	try_load = wl_try_load,
	init = wl_init,
	shutdown = wl_shutdown,
	get_window_render_glue = wl_get_window_render_glue,
	get_events = wl_get_events,
	set_title = wl_set_title,
	get_screen_width = wl_get_screen_width,
	get_screen_height = wl_get_screen_height,
	set_position = wl_set_position,
	get_position = wl_get_position,
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
	if missing, load_ok := wl.load(); !load_ok {
		return fmt.aprintf("Not using Wayland. Could not load %v.", missing,
			allocator = failure_reason_allocator), false
	}

	// The libraries being installed does not mean there is a compositor to talk to, so connect and
	// throw the connection away again. `wl_init` makes the one that gets used.
	display := wl.display_connect(nil)

	if display == nil {
		wl.unload()
		return "Not using Wayland. Could not connect to a compositor.", false
	}

	// A window has to get its decorations from somewhere. The same connection answers where from:
	// zxdg_decoration_manager_v1 is how a compositor offers to draw them, and its absence is how
	// GNOME says that clients are expected to decorate themselves.
	decorations_offered := false
	registry := wl.display_get_registry(display)
	wl.add_listener(registry, &decoration_probe_listener, &decorations_offered)
	wl.display_roundtrip(display)
	wl.destroy(registry)

	wl.display_disconnect(display)

	// Karl2D can draw its own, but only when asked to, so a compositor that offers nothing is
	// turned down here and the session falls through to X11.
	if !decorations_offered && !wl_custom_decorations_requested() {
		wl.unload()
		return "Not using Wayland. The compositor leaves window decorations to the client. Set " +
			"KARL2D_LINUX_DECORATIONS=custom to have Karl2D draw them.", false
	}

	if missing, load_ok := xkb.load(); !load_ok {
		wl.unload()
		return fmt.aprintf("Not using Wayland. Could not load %v.", missing,
			allocator = failure_reason_allocator), false
	}

	return "", true
}

// Whether the player asked Karl2D to draw the window decorations rather than leave them to the
// compositor. Read once before `WL_State` exists, in `wl_try_load`, and once after, in `wl_init`.
wl_custom_decorations_requested :: proc() -> bool {
	return os.get_env("KARL2D_LINUX_DECORATIONS", frame_allocator) == "custom"
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

	// Collects all the globals.
	wl.display_roundtrip(s.display)

	wl.add_listener(s.seat, &seat_listener, nil)

	// Initializes pointer and keyboard based on seat capabilities.
	wl.display_roundtrip(s.display)

	// A missing decoration manager means the compositor draws nothing, and `wl_try_load` only lets
	// the session get this far in that case when Karl2D is drawing the decorations itself. Decided
	// before the window is set up, because the frame changes how big the window is asked to be.
	s.decorations.on = s.decoration_manager == nil || wl_custom_decorations_requested()

	if s.decorations.on && s.subcompositor == nil {
		log.error("Wayland compositor has no wl_subcompositor. The window will have no borders.")
	}

	// Sets default size that gets used if the compositor doesn't suggest a size.
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
	// toplevel listener effecively creates a window handle.
	s.toplevel = wl.xdg_surface_get_toplevel(s.xdg_surface)
	wl.add_listener(s.toplevel, &toplevel_listener, nil)
	wl.add_listener(s.xdg_surface, &window_listener, nil)
	wl.xdg_toplevel_set_title(s.toplevel, strings.clone_to_cstring(window_title, frame_allocator))

	wl_set_window_mode(options.window_mode)

	if s.decoration_manager != nil {
		decoration := wl.zxdg_decoration_manager_v1_get_toplevel_decoration(
			s.decoration_manager,
			s.toplevel,
		)

		// Which side draws the titlebar and the buttons. The compositor picks for itself if we
		// never say, so the client side has to be asked for as explicitly as the server side.
		mode: c.uint32_t = wl.ZXDG_TOPLEVEL_DECORATION_V1_MODE_SERVER_SIDE

		if s.decorations.on {
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

	// After the first configure, so that the frame is laid out around a window whose size the
	// compositor has already had its say about.
	if s.decorations.on {
		wldeco_create()
	}

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

// Used by `wl_try_load`, which runs before there is a `WL_State` to write into, so this reports
// through its `data` pointer instead of through `s`. It also binds nothing: the connection it
// looks at is thrown away again, and `registry_listener` binds the globals on the one that stays.
decoration_probe_listener := wl.Registry_Listener {
	global = proc "c" (
		data: rawptr,
		registry: ^wl.Registry,
		name: u32,
		interface: cstring,
		version: u32,
	) {
		if interface == wl.zxdg_decoration_manager_v1_interface.name {
			(^bool)(data)^ = true
		}
	},
	global_remove = proc "c" (data: rawptr, registry: ^wl.Registry, name: u32) {},
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

		// The compositor sizes the whole window, decorations included, while everything below is
		// about the game canvas inside them.
		if w != 0 {
			w = max(1, w - wldeco_extra_width())
		}

		if h != 0 {
			h = max(1, h - wldeco_extra_height())
		}

		new_width: int
		new_height: int

		if s.window_mode == .Windowed {
			// Fixed-size window: we dictate the size, the compositor doesn't.
			new_width = s.last_configure_windowed_width
			new_height = s.last_configure_windowed_height
		} else {
			// A zero axis means the compositor lets us pick that dimension.
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

			wldeco_layout()

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
		context = s.odin_ctx

		// We stop hearing about this key once we lose keyboard focus, so the synthesized repeat
		// would otherwise keep firing forever while the window is in the background.
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
		s.pointer_surface = surface
		wldeco_pointer_moved(f32(surface_x >> 8), f32(surface_y >> 8))
		wl_apply_cursor()
	},
	leave = proc "c" (
		data: rawptr,
		pointer: ^wl.Pointer,
		serial: c.uint32_t,
		surface: ^wl.Surface,
	) {
		context = s.odin_ctx
		s.pointer_surface = nil
	},
	motion = proc "c" (
		data: rawptr,
		pointer: ^wl.Pointer,
		time: c.uint32_t,
		surface_x: wl.Fixed,
		surface_y: wl.Fixed,
	) {
		context = s.odin_ctx

		if wldeco_has_pointer() {
			// Only the cursor changes on the frame, and only when the pointer crosses between the
			// part that moves the window and the edges that resize it.
			if wldeco_pointer_moved(f32(surface_x >> 8), f32(surface_y >> 8)) {
				wl_apply_cursor()
			}

			return
		}

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

		if wldeco_has_pointer() {
			if state == wl.POINTER_BUTTON_STATE_PRESSED {
				wldeco_pointer_pressed(u32(button), u32(serial))
			}

			return
		}

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

		if wldeco_has_pointer() {
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

		// The decoration buffers hold physical pixels, so a new scale means new buffers.
		wldeco_layout()

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
	wldeco_destroy()

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
	// the rate/delay reported by the keyboard's `repeat_info` event.
	if s.repeat_key != .None && s.repeat_rate > 0 {
		now := time.tick_now()
		interval := time.Second / time.Duration(s.repeat_rate)

		// Capped so that a long stall (a breakpoint, a slow loading frame) doesn't produce a huge
		// burst of repeats.
		REPEATS_PER_FRAME_MAX :: 32

		for _ in 0..<REPEATS_PER_FRAME_MAX {
			if time.tick_diff(s.repeat_next_tick, now) < 0 {
				break
			}

			append(&s.events, Event_Key_Repeat {
				key = s.repeat_key,
			})
			_wl_append_typed_runes(s.repeat_xkb_keycode)
			s.repeat_next_tick = time.tick_add(s.repeat_next_tick, interval)
		}

		// If we hit the cap then we're still behind, so skip the backlog instead of spreading it
		// out over the coming frames.
		if time.tick_diff(s.repeat_next_tick, now) >= 0 {
			s.repeat_next_tick = time.tick_add(now, interval)
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
	wldeco_layout()
}

wl_get_window_scale :: proc() -> f32 {
	return s.scale
}

wl_set_window_mode :: proc(window_mode: Window_Mode) {
	s.window_mode = window_mode
	 
	switch window_mode {
	case .Windowed:
		wl.xdg_toplevel_unset_fullscreen(s.toplevel)

		// A size limit covers the window, decorations included, so a fixed-size game asks for a
		// window that is its canvas plus the frame around it.
		w := i32(s.last_configure_windowed_width + wldeco_extra_width())
		h := i32(s.last_configure_windowed_height + wldeco_extra_height())
		wl.xdg_toplevel_set_max_size(s.toplevel, w, h)
		wl.xdg_toplevel_set_min_size(s.toplevel, w, h)

	case .Windowed_Resizable:
		wl.xdg_toplevel_unset_fullscreen(s.toplevel)
		wl.xdg_toplevel_set_max_size(s.toplevel, 0, 0)
		wl.xdg_toplevel_set_min_size(s.toplevel, 0, 0)

	case .Borderless_Fullscreen:
		wl.xdg_toplevel_set_fullscreen(s.toplevel, nil)
	}

	// The frame comes and goes with fullscreen, and the window is a different size with it than
	// without it.
	wldeco_layout()
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

	theme_size := max(1, int(math.round(THEME_CURSOR_SIZE * s.scale)))
	s.cursor_theme = wl.cursor_theme_load(nil, c.int(theme_size), s.shm)
}

// Sets the OS cursor from s.cursor_hidden and s.current_cursor. They share the same pointer
// cursor, so every entry point goes through this instead of setting it independently. The pointer
// re-entering the window does too, since the compositor forgets the cursor when it leaves.
wl_apply_cursor :: proc() {
	// The fractional scale listener can fire during wl_init, before the pointer and the cursor
	// surface exist. Passing a nil surface to the compositor would mean "hide the cursor", and
	// attaching a buffer to one would dereference a nil proxy inside libwayland.
	if s.pointer == nil || s.cursor_surface == nil {
		return
	}

	standard := Standard_Cursor.Default

	// The frame belongs to Karl2D, so the pointer over it shows what the frame wants there rather
	// than what the game asked for. A game that hides its cursor still gets one on its titlebar.
	if wldeco_has_pointer() {
		standard = wldeco_cursor()
	} else {
		if s.cursor_hidden {
			wl.pointer_set_cursor(s.pointer, s.pointer_enter_serial, nil, 0, 0)
			return
		}

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

	// The theme image is THEME_CURSOR_SIZE*scale physical pixels but the viewport set up in wl_init
	// maps it down to THEME_CURSOR_SIZE logical pixels, so the hotspot (in the image's own pixels)
	// has to be scaled down to match.
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

wl_create_custom_cursor :: proc(image: Image, hotspot: [2]int) -> (Custom_Cursor, bool) {
	stride := image.width * 4
	size := stride * image.height

	fd, fd_err := linux.memfd_create("cursor", {})
	if fd_err != .NONE {
		log.errorf("Failed to create Wayland cursor: memfd failed with %v", fd_err)
		return {}, false
	}

	// The compositor dups the fd in shm_create_pool, so we don't have to keep ours around.
	defer linux.close(fd)

	if trunc_err := linux.ftruncate(fd, i64(size)); trunc_err != .NONE {
		log.errorf("Failed to create Wayland cursor: ftruncate failed with %v", trunc_err)
		return {}, false
	}

	data, mmap_err := linux.mmap(0, uint(size), {.READ, .WRITE}, {.SHARED}, fd, 0)
	if mmap_err != .NONE {
		log.errorf("Failed to create Wayland cursor: mmap failed with %v", mmap_err)
		return {}, false
	}

	// Convert to ARGB and premultiply alpha
	pixel_data := ([^]u32)(data)
	for i in 0..<len(image.pixels) {
		col := image.pixels[i]
		a := u32(col.a)
		r := u32(col.r) * a / 255
		g := u32(col.g) * a / 255
		b := u32(col.b) * a / 255
		pixel_data[i] = a << 24 | r << 16 | g << 8 | b
	}

	pool := wl.shm_create_pool(s.shm, c.int32_t(fd), c.int32_t(size))

	buffer := wl.shm_pool_create_buffer(
		pool, 0,
		c.int32_t(image.width), c.int32_t(image.height), c.int32_t(stride),
		wl.SHM_FORMAT_ARGB8888,
	)

	// The pool can go away immediately: the mapping stays alive until every buffer made from it
	// has been destroyed.
	wl.shm_pool_destroy(pool)

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

	wl_apply_cursor_scale(&cursor)

	handle, add_err := hm.add(&s.custom_cursors, cursor)

	if add_err != nil {
		log.errorf("Failed to create cursor. Error: %v", add_err)
		wl.wp_viewport_destroy(cursor.viewport)
		wl.surface_destroy(cursor.surface)
		wl.buffer_destroy(cursor.buffer)
		linux.munmap(cursor.data, uint(cursor.data_size))
		return {}, false
	}

	return handle, true
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
	wl.buffer_destroy(cd.buffer)
	linux.munmap(cd.data, uint(cd.data_size))
	hm.remove(&s.custom_cursors, custom_cursor)

	// Falls back to the default if that was the cursor on screen.
	wl_apply_cursor()
}

wl_set_internal_state :: proc(state: rawptr) {
	assert(state != nil)
	s = (^WL_State)(state)
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
	buffer: ^wl.Buffer,
	data: rawptr,
	data_size: int,

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

	// The frame Karl2D draws itself. See platform_linux_window_wayland_decorations.odin.
	decorations: WL_Decorations,
	fractional_scale_manager: ^wl.WP_Fractional_Scale_Manager_V1,

	xdg_base: ^wl.XDG_WM_Base,
	xdg_surface: ^wl.XDG_Surface,
	seat: ^wl.Seat,
	scale: f32,

	keyboard: ^wl.Keyboard,
	pointer: ^wl.Pointer,
	pointer_enter_serial: u32,

	// The surface the pointer is over, from the last enter event. It is one of the decorations
	// rather than the game canvas whenever the pointer is on the frame Karl2D draws.
	pointer_surface: ^wl.Surface,
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

