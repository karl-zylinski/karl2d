package wayland

import "core:c"

foreign import lib "system:wayland-client"
foreign import lib_egl "system:wayland-egl"

@(default_calling_convention = "c", link_prefix = "wl_")
foreign lib {
	display_connect :: proc(name: cstring) -> ^Display ---
	display_dispatch :: proc(display: ^Display) -> c.int ---
	display_flush :: proc(display: ^Display) -> c.int ---
	display_dispatch_pending :: proc(display: ^Display) -> c.int ---
	proxy_marshal_flags :: proc(
		display: ^Proxy,
		opcode: u32,
		interface: ^Interface,
		version: u32,
		flags: u32,
		#c_vararg _: ..any,
	) -> ^Proxy ---
	proxy_get_version :: proc(display: ^Proxy) ->u32 ---
	display_roundtrip :: proc(display: ^Display) -> c.int ---
	proxy_add_listener :: proc(display: ^Proxy, implementation: rawptr, userdata: rawptr) -> c.int ---
	proxy_destroy :: proc(display: ^Proxy) ---
}

@(default_calling_convention = "c", link_prefix = "wl_")
foreign lib_egl {
	egl_window_create :: proc(surface: ^Surface, width: c.int, height: c.int) -> ^EGL_Window ---
	egl_window_resize :: proc(window: ^EGL_Window, width: c.int, height: c.int, dx: c.int, dy: c.int) ---
	egl_window_destroy :: proc(window: ^EGL_Window) ---
}

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
