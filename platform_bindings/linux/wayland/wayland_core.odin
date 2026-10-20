// Partial Wayland bindings. The libraries are loaded at runtime, so that machines that only have
// X11 do not need them installed.
//
// Each interface is bound at a version no higher than what these bindings implement. Binding at a
// higher version makes the compositor send events that are not in our event tables, which makes
// libwayland abort the process.
package karl2d_wayland

import "core:c"
import "core:dynlib"

display_connect: proc "c" (name: cstring) -> ^Display

display_disconnect: proc "c" (display: ^Display)

display_dispatch: proc "c" (display: ^Display) -> c.int

display_flush: proc "c" (display: ^Display) -> c.int

display_dispatch_pending: proc "c" (display: ^Display) -> c.int

display_get_fd: proc "c" (display: ^Display) -> c.int

display_create_queue: proc "c" (display: ^Display) -> ^Event_Queue

event_queue_destroy: proc "c" (queue: ^Event_Queue)

display_dispatch_queue_pending: proc "c" (display: ^Display, queue: ^Event_Queue) -> c.int

display_prepare_read_queue: proc "c" (display: ^Display, queue: ^Event_Queue) -> c.int

display_read_events: proc "c" (display: ^Display) -> c.int

display_cancel_read: proc "c" (display: ^Display)

proxy_marshal_flags: proc "c" (
	proxy: ^Proxy,
	opcode: u32,
	interface: ^Interface,
	version: u32,
	flags: u32,
	#c_vararg _: ..any,
) -> ^Proxy

proxy_get_version: proc "c" (proxy: ^Proxy) -> u32

display_roundtrip: proc "c" (display: ^Display) -> c.int

proxy_add_listener: proc "c" (proxy: ^Proxy, implementation: rawptr, userdata: rawptr) -> c.int

proxy_destroy: proc "c" (proxy: ^Proxy)

proxy_create_wrapper: proc "c" (proxy: ^Proxy) -> ^Proxy

proxy_wrapper_destroy: proc "c" (proxy_wrapper: ^Proxy)

proxy_set_queue: proc "c" (proxy: ^Proxy, queue: ^Event_Queue)

egl_window_create: proc "c" (surface: ^Surface, width: c.int, height: c.int) -> ^EGL_Window

egl_window_resize: proc "c" (
	window: ^EGL_Window,
	width: c.int,
	height: c.int,
	dx: c.int,
	dy: c.int,
)

EGL_Window :: struct {}

Fixed :: c.int32_t

FIXED_ONE :: 256

fixed_to_f32 :: proc "contextless" (f: Fixed) -> f32 {
	return f32(f) / FIXED_ONE
}

Array :: struct {
	size: c.size_t,
	alloc: c.size_t,
	data: rawptr,
}

Message :: struct {
	name: cstring,
	signature: cstring,
	types: [^]^Interface,
}

Interface :: struct {
	name: cstring,
	version: c.int,
	method_count: c.int,
	methods: ^Message,
	event_count: c.int,
	events: ^Message,
}

Proxy :: struct {}

Event_Queue :: struct {}

Display :: struct {
	using proxy: Proxy,
}

MARSHAL_FLAG_DESTROY :: 1

LIB_WAYLAND_CLIENT :: "libwayland-client.so.0"
LIB_WAYLAND_EGL :: "libwayland-egl.so.1"
LIB_WAYLAND_CURSOR :: "libwayland-cursor.so.0"

Symbol :: struct {
	name: string,
	ptr: rawptr,
}

@(private)
lib_client: dynlib.Library

@(private)
lib_egl: dynlib.Library

@(private)
lib_cursor: dynlib.Library

@(private)
load_symbols :: proc(
	library_name: string,
	symbols: []Symbol,
) -> (lib: dynlib.Library, missing: string, ok: bool) {
	lib_ok: bool
	lib, lib_ok = dynlib.load_library(library_name)

	if !lib_ok {
		return nil, library_name, false
	}

	for s in symbols {
		addr, addr_ok := dynlib.symbol_address(lib, s.name)

		if !addr_ok {
			dynlib.unload_library(lib)
			return nil, s.name, false
		}

		(^rawptr)(s.ptr)^ = addr
	}

	return lib, "", true
}

load :: proc() -> (missing: string, ok: bool) {
	client_symbols := []Symbol {
		{"wl_display_connect", &display_connect},
		{"wl_display_disconnect", &display_disconnect},
		{"wl_display_dispatch", &display_dispatch},
		{"wl_display_flush", &display_flush},
		{"wl_display_dispatch_pending", &display_dispatch_pending},
		{"wl_display_get_fd", &display_get_fd},
		{"wl_display_create_queue", &display_create_queue},
		{"wl_event_queue_destroy", &event_queue_destroy},
		{"wl_display_dispatch_queue_pending", &display_dispatch_queue_pending},
		{"wl_display_prepare_read_queue", &display_prepare_read_queue},
		{"wl_display_read_events", &display_read_events},
		{"wl_display_cancel_read", &display_cancel_read},
		{"wl_proxy_marshal_flags", &proxy_marshal_flags},
		{"wl_proxy_get_version", &proxy_get_version},
		{"wl_display_roundtrip", &display_roundtrip},
		{"wl_proxy_add_listener", &proxy_add_listener},
		{"wl_proxy_destroy", &proxy_destroy},
		{"wl_proxy_create_wrapper", &proxy_create_wrapper},
		{"wl_proxy_wrapper_destroy", &proxy_wrapper_destroy},
		{"wl_proxy_set_queue", &proxy_set_queue},
	}

	lib_client, missing, ok = load_symbols(LIB_WAYLAND_CLIENT, client_symbols)

	if !ok {
		return
	}

	egl_symbols := []Symbol {
		{"wl_egl_window_create", &egl_window_create},
		{"wl_egl_window_resize", &egl_window_resize},
	}

	lib_egl, missing, ok = load_symbols(LIB_WAYLAND_EGL, egl_symbols)

	if !ok {
		unload()
		return
	}

	cursor_symbols := []Symbol {
		{"wl_cursor_theme_load", &cursor_theme_load},
		{"wl_cursor_theme_destroy", &cursor_theme_destroy},
		{"wl_cursor_theme_get_cursor", &cursor_theme_get_cursor},
		{"wl_cursor_image_get_buffer", &cursor_image_get_buffer},
	}

	lib_cursor, missing, ok = load_symbols(LIB_WAYLAND_CURSOR, cursor_symbols)

	if !ok {
		unload()
		return
	}

	return "", true
}

unload :: proc() {
	if lib_cursor != nil {
		dynlib.unload_library(lib_cursor)
		lib_cursor = nil
	}

	if lib_egl != nil {
		dynlib.unload_library(lib_egl)
		lib_egl = nil
	}

	if lib_client != nil {
		dynlib.unload_library(lib_client)
		lib_client = nil
	}
}
