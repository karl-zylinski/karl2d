// How we get an xdg_toplevel: through libdecor when it is available and the compositor won't
// decorate us itself, raw xdg-shell otherwise. Every touchpoint that differs between the two lives
// in this file, behind these five procs -- the rest of the Wayland backend never branches on it.
// Each of the five picks between a `_libdecor_` and a `_server_` implementation, named after the
// two values of KARL2D_LINUX_DECORATIONS.
#+build linux
package karl2d

import "core:c"
import "core:os"
import "core:strings"

import "log"
import ld "platform_bindings/linux/libdecor"
import wl "platform_bindings/linux/wayland"

WL_Shell :: struct {
	xdg_surface:    ^wl.XDG_Surface,
	toplevel:       ^wl.XDG_Toplevel,
	decoration:     ^wl.ZXDG_Toplevel_Decoration_V1,
	libdecor_ctx:   ^ld.Libdecor,

	// Non-nil only on the libdecor path. That is how the five procs below pick an implementation
	// after wl_shell_create has made the choice once.
	libdecor_frame: ^ld.Frame,
}

wl_shell_create :: proc(window_title: string, window_mode: Window_Mode) {
	if wl_shell_use_libdecor() {
		_libdecor_create(window_title, window_mode)
	} else {
		_server_create(window_title, window_mode)
	}
}

wl_shell_destroy :: proc() {
	if s.shell.libdecor_frame != nil {
		_libdecor_destroy()
	} else {
		_server_destroy()
	}
}

wl_shell_set_title :: proc(title: string) {
	if s.shell.libdecor_frame != nil {
		_libdecor_set_title(title)
	} else {
		_server_set_title(title)
	}
}

wl_shell_set_window_mode :: proc(window_mode: Window_Mode) {
	if s.shell.libdecor_frame != nil {
		_libdecor_set_window_mode(window_mode)
	} else {
		_server_set_window_mode(window_mode)
	}
}

// blocking = true is only used to wait out the first configure in wl_init. blocking = false is the
// per-frame pump in wl_get_events.
wl_shell_dispatch :: proc(blocking: bool) -> bool {
	if s.shell.libdecor_frame != nil {
		return _libdecor_dispatch(blocking)
	}

	return _server_dispatch(blocking)
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
wl_shell_use_libdecor :: proc() -> bool {
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

_libdecor_create :: proc(window_title: string, window_mode: Window_Mode) {
	s.shell.libdecor_ctx = ld.context_new(s.display, &libdecor_interface)
	s.shell.libdecor_frame = ld.decorate(
		s.shell.libdecor_ctx,
		s.surface,
		&libdecor_frame_interface,
		nil,
	)

	ld.frame_set_title(
		s.shell.libdecor_frame,
		strings.clone_to_cstring(window_title, frame_allocator),
	)

	_libdecor_set_window_mode(window_mode)

	// frame_map commits the surface, which asks the compositor for the first configure. No commit
	// of our own may land between here and that configure -- libdecor owns the surface's initial
	// commit sequence.
	ld.frame_map(s.shell.libdecor_frame)
}

_libdecor_destroy :: proc() {
	ld.frame_unref(s.shell.libdecor_frame)
	s.shell.libdecor_frame = nil
	ld.context_unref(s.shell.libdecor_ctx)
	s.shell.libdecor_ctx = nil

	// The library itself stays loaded, same as ALSA: unloading it at shutdown buys nothing and
	// runs whatever the plugin registered on the way out.
}

_libdecor_set_title :: proc(title: string) {
	ld.frame_set_title(s.shell.libdecor_frame, strings.clone_to_cstring(title, frame_allocator))
}

_libdecor_set_window_mode :: proc(window_mode: Window_Mode) {
	switch window_mode {
	case .Windowed:
		ld.frame_unset_fullscreen(s.shell.libdecor_frame)
		w := c.int(s.last_configure_windowed_width)
		h := c.int(s.last_configure_windowed_height)

		// Zero means unconstrained, so equal limits are what pin the size.
		ld.frame_set_min_content_size(s.shell.libdecor_frame, w, h)
		ld.frame_set_max_content_size(s.shell.libdecor_frame, w, h)

		// Otherwise the frame still offers resize edges and cursors for a size it cannot actually
		// change.
		ld.frame_unset_capabilities(s.shell.libdecor_frame, ld.CAPABILITY_RESIZE)

	case .Windowed_Resizable:
		ld.frame_unset_fullscreen(s.shell.libdecor_frame)
		ld.frame_set_min_content_size(s.shell.libdecor_frame, 0, 0)
		ld.frame_set_max_content_size(s.shell.libdecor_frame, 0, 0)
		ld.frame_set_capabilities(s.shell.libdecor_frame, ld.CAPABILITY_RESIZE)

	case .Borderless_Fullscreen:
		ld.frame_set_fullscreen(s.shell.libdecor_frame, nil)
	}
}

// libdecor_dispatch has to be used here instead of display_dispatch(_pending): it is the app
// main-loop pump and dispatches the default queue itself, so calling both would process events
// twice.
_libdecor_dispatch :: proc(blocking: bool) -> bool {
	timeout_ms: c.int = blocking ? -1 : 0
	return ld.dispatch(s.shell.libdecor_ctx, timeout_ms) >= 0
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
	// libdecor's decorations are synchronized subsurfaces of our surface, so when the frame
	// changes without us rendering (a focus or title change) nothing appears until we commit the
	// parent surface ourselves.
	commit = proc "c" (frame: ^ld.Frame, user_data: rawptr) {
		context = s.odin_ctx
		wl.surface_commit(s.surface)
	},
	dismiss_popup = proc "c" (frame: ^ld.Frame, seat_name: cstring, user_data: rawptr) {},
}

// The raw xdg-shell path. We own the shell objects and ask the compositor to decorate them, which
// it does on KDE and sway. Where zxdg_decoration_manager_v1 is missing and libdecor could not be
// loaded either, this is also the undecorated path.

_server_create :: proc(window_title: string, window_mode: Window_Mode) {
	xdg_surface := wl.xdg_wm_base_get_xdg_surface(s.xdg_base, s.surface)
	s.shell.xdg_surface = xdg_surface

	// Top-level means an application at the top of the window hierarchy. The callback in the
	// toplevel listener effectively creates a window handle.
	s.shell.toplevel = wl.xdg_surface_get_toplevel(xdg_surface)
	wl.add_listener(s.shell.toplevel, &toplevel_listener, nil)
	wl.add_listener(xdg_surface, &window_listener, nil)
	wl.xdg_toplevel_set_title(
		s.shell.toplevel,
		strings.clone_to_cstring(window_title, frame_allocator),
	)

	_server_set_window_mode(window_mode)

	if s.decoration_manager != nil {
		s.shell.decoration = wl.zxdg_decoration_manager_v1_get_toplevel_decoration(
			s.decoration_manager,
			s.shell.toplevel,
		)

		// This adds titlebar and buttons to the window.
		wl.zxdg_toplevel_decoration_v1_set_mode(
			s.shell.decoration,
			wl.ZXDG_TOPLEVEL_DECORATION_V1_MODE_SERVER_SIDE,
		)
	}

	// Committing with no buffer attached is what asks the compositor for the first configure.
	wl.surface_commit(s.surface)
}

_server_destroy :: proc() {
	// Before the toplevel: the decoration protocol raises `orphaned` if its xdg_toplevel goes
	// first.
	if s.shell.decoration != nil {
		wl.zxdg_toplevel_decoration_v1_destroy(s.shell.decoration)
		s.shell.decoration = nil
	}

	if s.shell.toplevel != nil {
		wl.xdg_toplevel_destroy(s.shell.toplevel)
		s.shell.toplevel = nil
	}

	if s.shell.xdg_surface != nil {
		wl.xdg_surface_destroy(s.shell.xdg_surface)
		s.shell.xdg_surface = nil
	}
}

_server_set_title :: proc(title: string) {
	wl.xdg_toplevel_set_title(s.shell.toplevel, strings.clone_to_cstring(title, frame_allocator))
}

_server_set_window_mode :: proc(window_mode: Window_Mode) {
	switch window_mode {
	case .Windowed:
		wl.xdg_toplevel_unset_fullscreen(s.shell.toplevel)
		w := i32(s.last_configure_windowed_width)
		h := i32(s.last_configure_windowed_height)
		wl.xdg_toplevel_set_max_size(s.shell.toplevel, w, h)
		wl.xdg_toplevel_set_min_size(s.shell.toplevel, w, h)

	case .Windowed_Resizable:
		wl.xdg_toplevel_unset_fullscreen(s.shell.toplevel)
		wl.xdg_toplevel_set_max_size(s.shell.toplevel, 0, 0)
		wl.xdg_toplevel_set_min_size(s.shell.toplevel, 0, 0)

	case .Borderless_Fullscreen:
		wl.xdg_toplevel_set_fullscreen(s.shell.toplevel, nil)
	}
}

_server_dispatch :: proc(blocking: bool) -> bool {
	if blocking {
		return wl.display_dispatch(s.display) >= 0
	}

	wl.display_dispatch_pending(s.display)
	return true
}
