package wayland

import "core:c"

foreign import lib "system:wayland-client"
foreign import lib_egl "system:wayland-egl"

@(default_calling_convention = "c", link_prefix = "wl_")
foreign lib {
	display_connect :: proc(_: cstring) -> ^wl_display ---
	display_dispatch :: proc(_: ^wl_display) -> c.int ---
	display_flush :: proc(_: ^wl_display) -> c.int ---
	display_dispatch_pending :: proc(_: ^wl_display) -> c.int ---
	proxy_marshal_flags :: proc(_: ^wl_proxy, _: c.uint32_t, _: ^wl_interface, _: c.uint32_t, _: c.uint32_t, #c_vararg _: ..any) -> ^wl_proxy ---
	proxy_get_version :: proc(_: ^wl_proxy) -> c.uint32_t ---
	display_roundtrip :: proc(_: ^wl_display) -> c.int ---
	proxy_add_listener :: proc(_: ^wl_proxy, _: ^Implementation, _: rawptr) -> c.int ---
	proxy_destroy :: proc(_: ^wl_proxy) ---
}

@(default_calling_convention = "c", link_prefix = "wl_")
foreign lib_egl {
	egl_window_create :: proc(_: ^wl_surface, _: c.int, _: c.int) -> ^egl_window ---
	egl_window_resize :: proc(_: ^egl_window, _: c.int, _: c.int, _: c.int, _: c.int) ---
	egl_window_destroy :: proc(_: ^egl_window) ---
}


egl_window :: struct {
}
// struct wl_map {
// 	struct wl_array client_entries;
// 	struct wl_array server_entries;
// 	uint32_t side;
// 	uint32_t free_list;
// };

wl_map :: struct {
	client_entries: wl_array,
	server_entries: wl_array,
	side:           c.uint32_t,
	free_list:      c.uint32_t,
}

//struct wl_array {
//	/** Array size */
//	size_t size;
//	/** Allocated space */
//	size_t alloc;
//	/** Array data */
//	void *data;
//};

wl_fixed_t :: c.int32_t
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
	display:    ^wl_display,
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
	id:             c.uint32_t,
}


wl_argument :: union {
	c.int32_t, /**< `int`    */
	c.uint32_t, /**< `uint`   */
	cstring, /**< `string` */
	wl_object, /**< `object` */
	^wl_array, /**< `array`  */
}

wl_dispatcher_func_t :: #type proc "c" (
	_: rawptr,
	_: rawptr,
	_: c.uint32_t,
	_: ^wl_message,
	_: ^wl_argument,
)

// struct wl_proxy {
// 	struct wl_object object;
// 	struct wl_display *display;
// 	struct wl_event_queue *queue;
// 	uint32_t flags;
// 	int refcount;
// 	void *user_data;
// 	wl_dispatcher_func_t dispatcher;
// 	uint32_t version;
// 	const char * const *tag;
// 	struct wl_list queue_link; /**< in struct wl_event_queue::proxy_list */
// };

// typedef int (*wl_dispatcher_func_t)(const void *user_data, void *target,
// 				    uint32_t opcode, const struct wl_message *msg,
// 				    union wl_argument *args);

wl_proxy :: struct {
	object:     wl_object,
	display:    ^wl_display,
	queue:      ^wl_event_queue, // pointer to wl_event_queue
	flags:      c.uint32_t,
	refcount:   c.int,
	user_data:  rawptr, // void* pointer
	dispatcher: wl_dispatcher_func_t, // wl_dispatcher_func_t dispatcher;
	version:    c.uint32_t,
	tag:        cstring,
	queue_link: wl_list,
}

wl_ring_buffer :: struct {
	data:          cstring,
	head:          c.size_t,
	tail:          c.size_t,
	size_bits:     c.uint32_t,
	max_size_bits: c.uint32_t,
}

wl_connection :: struct {
	_in:        wl_ring_buffer,
	out:        wl_ring_buffer,
	fds_in:     wl_ring_buffer,
	fds_out:    wl_ring_buffer,
	fd:         c.int,
	want_flush: c.int,
}

wl_display :: struct {
	proxy:          wl_proxy,
	connection:     ^wl_connection,
	last_error:     c.int,
	protocol_error: _wl_protocol_error,
	fd:             c.int,
	objects:        wl_map,
	display_queue:  wl_event_queue,
	default_queue:  wl_event_queue,
}

// Opaque struct, do not implement anything
//wl_display :: struct {}

_wl_protocol_error :: struct {
	code:      c.uint32_t,
	interface: ^wl_interface,
	id:        c.uint32_t,
}

WL_MARSHAL_FLAG_DESTROY :: 1 // Originally is (1 << 0) for some god forsaken reason
