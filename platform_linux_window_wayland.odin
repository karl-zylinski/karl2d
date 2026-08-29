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
import "core:c"
import "core:math"
import "core:os"
import "core:strings"
import "core:sys/linux"
import "core:time"
import hm "core:container/handle_map"

import "log"
import ld "platform_bindings/linux/libdecor"
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

	// Collects all the globals.
	wl.display_roundtrip(s.display)

	wl.add_listener(s.seat, &seat_listener, nil)

	// Initializes pointer and keyboard based on seat capabilities.
	wl.display_roundtrip(s.display)

	// Sets default size that gets used if the compositor doesn't suggest a size.
	s.last_configure_width = screen_width
	s.last_configure_height = screen_height
	s.last_configure_windowed_width = screen_width
	s.last_configure_windowed_height = screen_height

	s.surface = wl.compositor_create_surface(s.compositor)
	log.ensure(s.surface != nil, "Error creating Wayland surface")
	
	// Makes sure the window does "pings" that keeps it alive.
	wl.add_listener(s.xdg_base, &wm_base_listener, nil)

	s.window_mode = options.window_mode
	_shell_create(window_title, options.window_mode)

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

	// Wait for the first configure, which _shell_create asked for. It's what creates the EGL
	// window.
	for !s.configured {
		if !_shell_dispatch(blocking = true) {
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

		wl_apply_content_size(new_width, new_height)
		s.configured = true
	},
	close = proc "c" (data: rawptr, xdg_toplevel: ^wl.XDG_Toplevel) {
		context = s.odin_ctx
		append(&s.events, Event_Close_Window_Requested{})
	},
	configure_bounds = proc "c" (data: rawptr, xdg_toplevel: ^wl.XDG_Toplevel, width: c.int32_t, height: c.int32_t,) {},
	wm_capabilities = proc "c" (data: rawptr, xdg_toplevel: ^wl.XDG_Toplevel, capabilities: ^wl.Array,) {},
}

// Both shell paths hand us a content size -- neither ever calls set_window_geometry, so this is
// all there is to applying one: create the EGL window on the first configure, resize it and the
// viewport on every later one, and record the new size. A no-op when the size didn't change and
// this isn't the first configure.
wl_apply_content_size :: proc(new_width: int, new_height: int) {
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

		append(&s.events, Event_Screen_Resize {
			width = s.screen_width,
			height = s.screen_height,
		})
	}
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

// How we get an xdg_toplevel: through libdecor when it is available and the compositor won't
// decorate us itself, raw xdg-shell otherwise. Everything that differs between the two lives behind
// these five procs -- nothing else in this file branches on it. Each one picks between a
// `_shell_libdecor_` and a `_shell_server_` implementation, named after the two values of
// KARL2D_LINUX_DECORATIONS.

_shell_create :: proc(window_title: string, window_mode: Window_Mode) {
	if _shell_use_libdecor() {
		_shell_libdecor_create(window_title, window_mode)
	} else {
		_shell_server_create(window_title, window_mode)
	}
}

_shell_destroy :: proc() {
	if s.libdecor_frame != nil {
		_shell_libdecor_destroy()
	} else {
		_shell_server_destroy()
	}
}

_shell_set_title :: proc(title: string) {
	if s.libdecor_frame != nil {
		_shell_libdecor_set_title(title)
	} else {
		_shell_server_set_title(title)
	}
}

_shell_set_window_mode :: proc(window_mode: Window_Mode) {
	if s.libdecor_frame != nil {
		_shell_libdecor_set_window_mode(window_mode)
	} else {
		_shell_server_set_window_mode(window_mode)
	}
}

// blocking = true is only used to wait out the first configure in wl_init. blocking = false is the
// per-frame pump in wl_get_events.
_shell_dispatch :: proc(blocking: bool) -> bool {
	if s.libdecor_frame != nil {
		return _shell_libdecor_dispatch(blocking)
	}

	return _shell_server_dispatch(blocking)
}

// Prefers server-side decorations: KDE, sway and any other compositor with
// zxdg_decoration_manager_v1 stay on the raw xdg-shell path they use today, and libdecor is only
// loaded as a fallback for compositors like GNOME's Mutter that never advertise that global.
// KARL2D_LINUX_DECORATIONS overrides this for debugging on real hardware without a rebuild:
// "server" always uses server-side (or undecorated) raw xdg-shell, "libdecor" always uses libdecor.
//
// Accepted limitation: a compositor that advertises the decoration manager and then answers
// CLIENT_SIDE stays undecorated, because by then the toplevel already exists and switching shells
// would mean tearing it down. No known compositor does this.
_shell_use_libdecor :: proc() -> bool {
	want_libdecor := s.decoration_manager == nil

	preference := os.get_env("KARL2D_LINUX_DECORATIONS", frame_allocator)

	switch preference {
	case "":
		// Automatic choice above stands.
	case "server":
		want_libdecor = false
	case "libdecor":
		want_libdecor = true
	case:
		log.warnf(
			"Ignoring KARL2D_LINUX_DECORATIONS=%v. It has to be \"server\" or \"libdecor\".",
			preference,
		)
	}

	if !want_libdecor {
		return false
	}

	if missing, ok := ld.load(); !ok {
		log.warnf("Not using libdecor. Could not load %v.", missing)
		return false
	}

	return true
}

// The libdecor path. libdecor is not a decoration library so much as a shell library: it takes the
// wl_surface and creates the xdg_surface and xdg_toplevel itself, so none of those objects are ours
// to touch here.

_shell_libdecor_create :: proc(window_title: string, window_mode: Window_Mode) {
	s.libdecor_ctx = ld.context_new(s.display, &libdecor_interface)
	s.libdecor_frame = ld.decorate(s.libdecor_ctx, s.surface, &libdecor_frame_interface, nil)
	ld.frame_set_title(s.libdecor_frame, strings.clone_to_cstring(window_title, frame_allocator))

	_shell_libdecor_set_window_mode(window_mode)

	// frame_map commits the surface, which asks the compositor for the first configure. No commit
	// of our own may land between here and that configure -- libdecor owns the surface's initial
	// commit sequence.
	ld.frame_map(s.libdecor_frame)
}

_shell_libdecor_destroy :: proc() {
	ld.frame_unref(s.libdecor_frame)
	s.libdecor_frame = nil
	ld.context_unref(s.libdecor_ctx)
	s.libdecor_ctx = nil

	// The library itself stays loaded, same as ALSA: unloading it at shutdown buys nothing and
	// runs whatever the plugin registered on the way out.
}

_shell_libdecor_set_title :: proc(title: string) {
	ld.frame_set_title(s.libdecor_frame, strings.clone_to_cstring(title, frame_allocator))
}

_shell_libdecor_set_window_mode :: proc(window_mode: Window_Mode) {
	switch window_mode {
	case .Windowed:
		ld.frame_unset_fullscreen(s.libdecor_frame)
		w := c.int(s.last_configure_windowed_width)
		h := c.int(s.last_configure_windowed_height)

		// Zero means unconstrained, so equal limits are what pin the size.
		ld.frame_set_min_content_size(s.libdecor_frame, w, h)
		ld.frame_set_max_content_size(s.libdecor_frame, w, h)

		// Otherwise the frame still offers resize edges and cursors for a size it cannot actually
		// change.
		ld.frame_unset_capabilities(s.libdecor_frame, ld.CAPABILITY_RESIZE)

	case .Windowed_Resizable:
		ld.frame_unset_fullscreen(s.libdecor_frame)
		ld.frame_set_min_content_size(s.libdecor_frame, 0, 0)
		ld.frame_set_max_content_size(s.libdecor_frame, 0, 0)
		ld.frame_set_capabilities(s.libdecor_frame, ld.CAPABILITY_RESIZE)

	case .Borderless_Fullscreen:
		ld.frame_set_fullscreen(s.libdecor_frame, nil)
	}
}

// libdecor_dispatch has to be used here instead of display_dispatch(_pending): it is the app
// main-loop pump and dispatches the default queue itself, so calling both would process events
// twice.
_shell_libdecor_dispatch :: proc(blocking: bool) -> bool {
	timeout_ms: c.int = blocking ? -1 : 0
	return ld.dispatch(s.libdecor_ctx, timeout_ms) >= 0
}

libdecor_interface := ld.Interface {
	error = proc "c" (ctx: ^ld.Libdecor, error: c.uint32_t, message: cstring) {
		context = s.odin_ctx
		log.errorf("libdecor error %v: %v", error, message)
	},
}

libdecor_frame_interface := ld.Frame_Interface {
	configure = proc "c" (frame: ^ld.Frame, configuration: ^ld.Configuration, user_data: rawptr) {
		context = s.odin_ctx

		content_w, content_h: c.int

		if !ld.configuration_get_content_size(configuration, frame, &content_w, &content_h) {
			// The compositor left the size to us.
			content_w = c.int(s.last_configure_windowed_width)
			content_h = c.int(s.last_configure_windowed_height)
		}

		new_width: int
		new_height: int

		if s.window_mode == .Windowed {
			// Fixed-size window: we dictate the size, the compositor doesn't.
			new_width = s.last_configure_windowed_width
			new_height = s.last_configure_windowed_height
		} else {
			new_width = int(content_w)
			new_height = int(content_h)
		}

		wl_apply_content_size(new_width, new_height)

		state := ld.state_new(c.int(new_width), c.int(new_height))
		ld.frame_commit(frame, state, configuration)
		ld.state_free(state)

		s.configured = true
	},
	close = proc "c" (frame: ^ld.Frame, user_data: rawptr) {
		context = s.odin_ctx
		append(&s.events, Event_Close_Window_Requested{})
	},
	// libdecor's decorations are synchronized subsurfaces of our surface, so when the frame changes
	// without us rendering (a focus or title change) nothing appears until we commit the parent
	// surface ourselves.
	commit = proc "c" (frame: ^ld.Frame, user_data: rawptr) {
		context = s.odin_ctx
		wl.surface_commit(s.surface)
	},
	dismiss_popup = proc "c" (frame: ^ld.Frame, seat_name: cstring, user_data: rawptr) {},
}

// The raw xdg-shell path. We own the shell objects and ask the compositor to decorate them, which
// it does on KDE and sway. Where zxdg_decoration_manager_v1 is missing and libdecor could not be
// loaded either, this is also the undecorated path.

_shell_server_create :: proc(window_title: string, window_mode: Window_Mode) {
	s.xdg_surface = wl.xdg_wm_base_get_xdg_surface(s.xdg_base, s.surface)

	// Top-level means an application at the top of the window hierarchy. The callback in the
	// toplevel listener effectively creates a window handle.
	s.toplevel = wl.xdg_surface_get_toplevel(s.xdg_surface)
	wl.add_listener(s.toplevel, &toplevel_listener, nil)
	wl.add_listener(s.xdg_surface, &window_listener, nil)
	wl.xdg_toplevel_set_title(s.toplevel, strings.clone_to_cstring(window_title, frame_allocator))

	_shell_server_set_window_mode(window_mode)

	if s.decoration_manager != nil {
		s.decoration = wl.zxdg_decoration_manager_v1_get_toplevel_decoration(
			s.decoration_manager,
			s.toplevel,
		)

		// This adds titlebar and buttons to the window.
		wl.zxdg_toplevel_decoration_v1_set_mode(
			s.decoration,
			wl.ZXDG_TOPLEVEL_DECORATION_V1_MODE_SERVER_SIDE,
		)
	}

	// Committing with no buffer attached is what asks the compositor for the first configure.
	wl.surface_commit(s.surface)
}

_shell_server_destroy :: proc() {
	// Before the toplevel: the decoration protocol raises `orphaned` if its xdg_toplevel goes
	// first.
	if s.decoration != nil {
		wl.zxdg_toplevel_decoration_v1_destroy(s.decoration)
		s.decoration = nil
	}

	if s.toplevel != nil {
		wl.xdg_toplevel_destroy(s.toplevel)
		s.toplevel = nil
	}

	if s.xdg_surface != nil {
		wl.xdg_surface_destroy(s.xdg_surface)
		s.xdg_surface = nil
	}
}

_shell_server_set_title :: proc(title: string) {
	wl.xdg_toplevel_set_title(s.toplevel, strings.clone_to_cstring(title, frame_allocator))
}

_shell_server_set_window_mode :: proc(window_mode: Window_Mode) {
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

_shell_server_dispatch :: proc(blocking: bool) -> bool {
	if blocking {
		return wl.display_dispatch(s.display) >= 0
	}

	wl.display_dispatch_pending(s.display)
	return true
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
	_shell_destroy()

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
	_shell_dispatch(blocking = false)

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
	_shell_set_title(title)
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
}

wl_get_window_scale :: proc() -> f32 {
	return s.scale
}

wl_set_window_mode :: proc(window_mode: Window_Mode) {
	s.window_mode = window_mode
	_shell_set_window_mode(window_mode)
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
	window: ^wl.EGL_Window,
	viewporter: ^wl.WP_Viewporter,
	viewport: ^wl.WP_Viewport,
	decoration_manager: ^wl.ZXDG_Decoration_Manager_V1,
	fractional_scale_manager: ^wl.WP_Fractional_Scale_Manager_V1,

	xdg_base: ^wl.XDG_WM_Base,

	// The shell objects. Which of them exist depends on which shell `_shell_create` picked: the
	// raw path owns xdg_surface/toplevel/decoration, libdecor owns its own copies of the first two
	// and we never see them. `libdecor_frame` being non-nil is what the `_shell_` procs branch on.
	xdg_surface: ^wl.XDG_Surface,
	toplevel: ^wl.XDG_Toplevel,
	decoration: ^wl.ZXDG_Toplevel_Decoration_V1,
	libdecor_ctx: ^ld.Libdecor,
	libdecor_frame: ^ld.Frame,

	seat: ^wl.Seat,
	scale: f32,

	keyboard: ^wl.Keyboard,
	pointer: ^wl.Pointer,
	pointer_enter_serial: u32,
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

