// How we get an xdg_toplevel: through libdecor when it is available and the compositor won't
// decorate us itself, raw xdg-shell otherwise. Every touchpoint that differs between the two lives
// in this file, behind these five procs -- the rest of the Wayland backend never branches on it.
#+build linux
package karl2d

import "core:strings"
import wl "platform_bindings/linux/wayland"

WL_Shell :: struct {
	xdg_surface: ^wl.XDG_Surface,
	toplevel:    ^wl.XDG_Toplevel,
}

wl_shell_create :: proc(window_title: string, window_mode: Window_Mode) {
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

	wl_shell_set_window_mode(window_mode)

	if s.decoration_manager != nil {
		s.decoration = wl.zxdg_decoration_manager_v1_get_toplevel_decoration(
			s.decoration_manager,
			s.shell.toplevel,
		)

		// This adds titlebar and buttons to the window.
		wl.zxdg_toplevel_decoration_v1_set_mode(
			s.decoration,
			wl.ZXDG_TOPLEVEL_DECORATION_V1_MODE_SERVER_SIDE,
		)
	}
}

wl_shell_destroy :: proc() {
	if s.shell.toplevel != nil {
		wl.xdg_toplevel_destroy(s.shell.toplevel)
		s.shell.toplevel = nil
	}

	if s.shell.xdg_surface != nil {
		wl.xdg_surface_destroy(s.shell.xdg_surface)
		s.shell.xdg_surface = nil
	}
}

wl_shell_set_title :: proc(title: string) {
	wl.xdg_toplevel_set_title(s.shell.toplevel, strings.clone_to_cstring(title, frame_allocator))
}

wl_shell_set_window_mode :: proc(window_mode: Window_Mode) {
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

// blocking = true is only used to wait out the first configure in wl_init. blocking = false is the
// per-frame pump in wl_get_events.
wl_shell_dispatch :: proc(blocking: bool) -> bool {
	if blocking {
		return wl.display_dispatch(s.display) >= 0
	}

	wl.display_dispatch_pending(s.display)
	return true
}
