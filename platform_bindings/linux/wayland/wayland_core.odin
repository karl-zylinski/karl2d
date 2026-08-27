// Loaded with dlopen instead of a static foreign import. Karl2D compiles in both the X11 and the
// Wayland backend and only one of them runs, so linking these libraries unconditionally would
// require every machine to have them installed.
package wayland

import "core:c"
import "../dynload"

display_connect: proc "c" (name: cstring) -> ^Display

display_disconnect: proc "c" (display: ^Display) -> bool

display_dispatch: proc "c" (display: ^Display) -> c.int

display_flush: proc "c" (display: ^Display) -> c.int

display_dispatch_pending: proc "c" (display: ^Display) -> c.int

proxy_marshal_flags: proc "c" (
	proxy:     ^Proxy,
	opcode:    u32,
	interface: ^Interface,
	version:   u32,
	flags:     u32,
	#c_vararg _: ..any,
) -> ^Proxy

proxy_get_version: proc "c" (proxy: ^Proxy) -> u32

display_roundtrip: proc "c" (display: ^Display) -> c.int

proxy_add_listener: proc "c" (proxy: ^Proxy, implementation: rawptr, userdata: rawptr) -> c.int

proxy_destroy: proc "c" (proxy: ^Proxy)

egl_window_create: proc "c" (surface: ^Surface, width: c.int, height: c.int) -> ^EGL_Window

egl_window_resize: proc "c" (
	window: ^EGL_Window,
	width:  c.int,
	height: c.int,
	dx:     c.int,
	dy:     c.int,
)

egl_window_destroy: proc "c" (window: ^EGL_Window)

EGL_Window :: struct {}

Fixed :: c.int32_t

Array :: struct {
	size:  c.size_t,
	alloc: c.size_t,
	data:  rawptr,
}

Message :: struct {
	name:      cstring,
	signature: cstring,
	types:     [^]^Interface,
}

Interface :: struct {
	name:         cstring,
	version:      c.int,
	method_count: c.int,
	methods:      ^Message,
	event_count:  c.int,
	events:       ^Message,
}

Proxy :: struct {}

Display :: struct {
	using proxy: Proxy,
}

MARSHAL_FLAG_DESTROY :: 1

LIB_WAYLAND_CLIENT :: "libwayland-client.so.0"
LIB_WAYLAND_EGL     :: "libwayland-egl.so.1"
LIB_WAYLAND_CURSOR  :: "libwayland-cursor.so.0"

load :: proc() -> (err: dynload.Error, what: string) {
	client_symbols := []dynload.Symbol {
		{"wl_display_connect", &display_connect},
		{"wl_display_disconnect", &display_disconnect},
		{"wl_display_dispatch", &display_dispatch},
		{"wl_display_flush", &display_flush},
		{"wl_display_dispatch_pending", &display_dispatch_pending},
		{"wl_proxy_marshal_flags", &proxy_marshal_flags},
		{"wl_proxy_get_version", &proxy_get_version},
		{"wl_display_roundtrip", &display_roundtrip},
		{"wl_proxy_add_listener", &proxy_add_listener},
		{"wl_proxy_destroy", &proxy_destroy},
	}

	err, what = dynload.load(LIB_WAYLAND_CLIENT, client_symbols)

	if err != .None {
		return
	}

	egl_symbols := []dynload.Symbol {
		{"wl_egl_window_create", &egl_window_create},
		{"wl_egl_window_resize", &egl_window_resize},
		{"wl_egl_window_destroy", &egl_window_destroy},
	}

	err, what = dynload.load(LIB_WAYLAND_EGL, egl_symbols)

	if err != .None {
		return
	}

	cursor_symbols := []dynload.Symbol {
		{"wl_cursor_theme_load", &cursor_theme_load},
		{"wl_cursor_theme_destroy", &cursor_theme_destroy},
		{"wl_cursor_theme_get_cursor", &cursor_theme_get_cursor},
		{"wl_cursor_image_get_buffer", &cursor_image_get_buffer},
	}

	return dynload.load(LIB_WAYLAND_CURSOR, cursor_symbols)
}
