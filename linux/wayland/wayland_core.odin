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
	proxy_marshal_flags :: proc(display: ^Proxy, opcode:u32, interface: ^wl_interface, version:u32, flags:u32, #c_vararg _: ..any) -> ^Proxy ---
	proxy_get_version :: proc(display: ^Proxy) ->u32 ---
	display_roundtrip :: proc(display: ^Display) -> c.int ---
	proxy_add_listener :: proc(display: ^Proxy, implementation: ^Implementation, userdata: rawptr) -> c.int ---
	proxy_destroy :: proc(display: ^Proxy) ---
}

@(default_calling_convention = "c", link_prefix = "wl_")
foreign lib_egl {
	egl_window_create :: proc(surface: ^Surface, width: c.int, height: c.int) -> ^egl_window ---
	egl_window_resize :: proc(window: ^egl_window, width: c.int, height: c.int, dx: c.int, dy: c.int) ---
	egl_window_destroy :: proc(window: ^egl_window) ---
}

egl_window :: struct {}

Fixed :: c.int32_t
wl_array :: struct {
	size:  c.size_t,
	alloc: c.size_t,
	data:  rawptr,
}

wl_list :: struct {
	prev: ^wl_list,
	next: ^wl_list,
}

wl_event_queue :: struct {
	event_list: wl_list,
	proxy_list: wl_list,
	display:    ^Display,
	name:       cstring,
}

// struct wl_message {
// 	/** Message name */
// 	const char *name;
// 	/** Message signature */
// 	const char *signature;
// 	/** Object argument interfaces */
// 	const struct wl_interface **types;
// };

wl_message :: struct {
	name:      cstring,
	signature: cstring,
	types:     [^]^wl_interface,
}

wl_interface :: struct {
	name:         cstring,
	version:      c.int,
	method_count: c.int,
	methods:      ^wl_message,
	event_count:  c.int,
	events:       ^wl_message,
}


// what?
Implementation :: #type proc "c" ()

wl_object :: struct {
	interface:      ^wl_interface,
	implementation: ^Implementation,
	id:            u32,
}


Proxy :: struct {}

Display :: struct {
	using proxy:    Proxy,
}

// Opaque struct, do not implement anything
//wl_display :: struct {}

_wl_protocol_error :: struct {
	code:     u32,
	interface: ^wl_interface,
	id:       u32,
}

WL_MARSHAL_FLAG_DESTROY :: 1 // Originally is (1 << 0) for some god forsaken reason
