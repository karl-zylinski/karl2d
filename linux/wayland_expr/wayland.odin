package karl2d_wayland_bindings

import "core:c"

foreign import lib_wl "system:wayland-client"

// BINDINGS

@(default_calling_convention = "c", link_prefix = "wl_")
foreign lib_wl {
	display_connect :: proc(name: cstring) -> ^Display ---

	// Prepares a request to be sent to the compositor. 
	proxy_marshal_flags :: proc(
		proxy: ^Proxy,
		opcode: c.uint32_t,
		interface: ^Interface,
		version: c.uint32_t,
		flags: c.uint32_t,
		#c_vararg _: ..any,
	) -> ^Proxy ---

	proxy_get_version :: proc(proxy: ^Proxy) -> c.uint32_t ---
	proxy_add_listener :: proc(proxy: ^Proxy, implementation: rawptr, data: rawptr) -> c.int ---
	display_roundtrip :: proc(display: ^Display) -> c.int ---
}

// TYPES

Surface :: struct {}

Display :: struct {
	proxy:          Proxy,
	connection:     ^Connection,
	last_error:     c.int,
	protocol_error: Protocol_Error,
	fd:             c.int,
	objects:        Map,
	display_queue:  Event_Queue,
	default_queue:  Event_Queue,
}

// COMPOSITOR

Compositor :: struct {}
Compositor_Listener :: struct {}


compositor_create_surface :: proc "c" (compositor: ^Compositor) -> ^Surface {
	id := proxy_marshal_flags(
		cast(^Proxy)compositor,
		0,
		&surface_interface,
		proxy_get_version(cast(^Proxy)compositor),
		0,
		nil,
	)
	
	return cast(^Surface)id
}

add_listener :: proc(
	proxy: ^$Proxy_Type,
	listener: ^$Listener_Type,
	data: rawptr,
) -> c.int {
	return proxy_add_listener((^Proxy)(proxy), rawptr(listener), data)
}

Protocol_Error :: struct {
	code:      c.uint32_t,
	interface: ^Interface,
	id:        c.uint32_t,
}

Map :: struct {
	client_entries: Array,
	server_entries: Array,
	side:           c.uint32_t,
	free_list:      c.uint32_t,
}

Connection :: struct {
	_in:        Ring_Buffer,
	out:        Ring_Buffer,
	fds_in:     Ring_Buffer,
	fds_out:    Ring_Buffer,
	fd:         c.int,
	want_flush: c.int,
}


Ring_Buffer :: struct {
	data:          [^]u8,
	head:          c.size_t,
	tail:          c.size_t,
	size_bits:     c.uint32_t,
	max_size_bits: c.uint32_t,
}


Proxy :: struct {
	object:     Object,
	display:    ^Display,
	queue:      ^Event_Queue,
	flags:      c.uint32_t,
	refcount:   c.int,
	user_data:  rawptr,
	dispatcher: Dispatcher_Func,
	version:    c.uint32_t,
	tag:        cstring,
	queue_link: List,
}

Dispatcher_Func :: #type proc "c" (
	impl: rawptr,
	target: rawptr,
	opcode: c.uint32_t,
	msg: ^Message,
	args: [^]Argument,
)

Argument :: union {
	c.int32_t,
	c.uint32_t,
	cstring,
	Object,
	^Array,
}

Array :: struct {
	size:  c.size_t,
	alloc: c.size_t,
	data:  rawptr,
}

Event_Queue :: struct {
	event_list: List,
	proxy_list: List,
	display:    ^Display,
	name:       cstring,
}

List :: struct {
	prev: ^List,
	next: ^List,
}

Object :: struct {
	interface:      ^Interface,
	implementation: rawptr,
	id:             c.uint32_t,
}

Interface :: struct {
	name:         cstring,
	version:      c.int,
	method_count: c.int,
	methods:      ^Message,
	event_count:  c.int,
	events:       ^Message,
}

Message :: struct {
	name:      cstring,
	signature: cstring,
	types:     [^]^Interface,
}

Registry :: struct {}

Registry_Listener :: struct {
	global: proc "c" (
		data: rawptr,
		registry: ^Registry,
		name: c.uint32_t,
		interface: cstring,
		version: c.uint32_t,
	),

	global_remove: proc "c" (
		data: rawptr,
		registry: ^Registry,
		name: c.uint32_t,
	),
}

// WAYLAND GLUE PROCS

registry_add_listener :: proc(
	registry: ^Registry,
	listener: ^Registry_Listener,
	data: rawptr,
) -> c.int {
	return proxy_add_listener((^Proxy)(registry), rawptr(listener), data)
}



// BUFFER INTERFACE

buffer_interface_requests := [?]Message {{"destroy", "", raw_data([]^Interface{})}}

buffer_interface_events := [?]Message {{"release", "", raw_data([]^Interface{})}}

buffer_interface: Interface
@(init)
init_wl_buffer_interface :: proc "contextless" () {
	buffer_interface = {"wl_buffer", 1, 1, raw_data(&buffer_interface_requests), 1, raw_data(&buffer_interface_events)}
}


// CALLBACK INTERFACE


wl_callback_requests: []Message = []Message{}

wl_callback_events: []Message = []Message{{"done", "u", raw_data([]^Interface{nil})}}

wl_callback_interface: Interface = {}
@(init)
init_wl_callback_interface :: proc "contextless" () {
	wl_callback_interface = {"wl_callback", 1, 0, nil, 1, &wl_callback_events[0]}
}


// REGION INTERFACE


wl_region_requests: []Message = []Message {
	{"destroy", "", raw_data([]^Interface{})},
	{"add", "iiii", raw_data([]^Interface{nil, nil, nil, nil})},
	{"subtract", "iiii", raw_data([]^Interface{nil, nil, nil, nil})},
}

wl_region_events: []Message = []Message{}

wl_region_interface: Interface = {}
@(init)
init_wl_region_interface :: proc "contextless" () {
	wl_region_interface = {"wl_region", 1, 3, &wl_region_requests[0], 0, nil}
}


// OUTPUT INTERFACE


wl_output_requests: []Message = []Message{{"release", "", raw_data([]^Interface{})}}

wl_output_events: []Message = []Message {
	{"geometry", "iiiiissi", raw_data([]^Interface{nil, nil, nil, nil, nil, nil, nil, nil})},
	{"mode", "uiii", raw_data([]^Interface{nil, nil, nil, nil})},
	{"done", "", raw_data([]^Interface{})},
	{"scale", "i", raw_data([]^Interface{nil})},
	{"name", "s", raw_data([]^Interface{nil})},
	{"description", "s", raw_data([]^Interface{nil})},
}

wl_output_interface: Interface = {}
@(init)
init_wl_output_interface :: proc "contextless" () {
	wl_output_interface = {"wl_output", 4, 1, &wl_output_requests[0], 6, &wl_output_events[0]}
}


// COMPOSITOR INTERFACE



wl_compositor_requests: []Message = []Message {
	{"create_surface", "n", raw_data([]^Interface{&surface_interface})},
	{"create_region", "n", raw_data([]^Interface{&wl_region_interface})},
}

wl_compositor_events: []Message = []Message{}

compositor_interface: Interface = {}
@(init)
init_wl_compositor_interface :: proc "contextless" () {
	compositor_interface = {"wl_compositor", 6, 2, &wl_compositor_requests[0], 0, nil}
}

// POINTER INTERFACE


wl_pointer_requests: []Message = []Message {
	{"set_cursor", "u?oii", raw_data([]^Interface{nil, &surface_interface, nil, nil})},
	{"release", "", raw_data([]^Interface{})},
}

wl_pointer_events: []Message = []Message {
	{"enter", "uoff", raw_data([]^Interface{nil, &surface_interface, nil, nil})},
	{"leave", "uo", raw_data([]^Interface{nil, &surface_interface})},
	{"motion", "uff", raw_data([]^Interface{nil, nil, nil})},
	{"button", "uuuu", raw_data([]^Interface{nil, nil, nil, nil})},
	{"axis", "uuf", raw_data([]^Interface{nil, nil, nil})},
	{"frame", "", raw_data([]^Interface{})},
	{"axis_source", "u", raw_data([]^Interface{nil})},
	{"axis_stop", "uu", raw_data([]^Interface{nil, nil})},
	{"axis_discrete", "ui", raw_data([]^Interface{nil, nil})},
	{"axis_value120", "ui", raw_data([]^Interface{nil, nil})},
	{"axis_relative_direction", "uu", raw_data([]^Interface{nil, nil})},
}

MARSHAL_FLAG_DESTROY :: 1

Fixed :: c.int32_t

wl_pointer_listener :: struct {
	enter:                   proc "c" (
		data: rawptr,
		pointer: ^Pointer,
		serial: c.uint32_t,
		surface: ^Surface,
		surface_x: Fixed,
		surface_y: Fixed,
	),
	leave:                   proc "c" (
		data: rawptr,
		pointer: ^Pointer,
		serial: c.uint32_t,
		surface: ^Surface,
	),
	motion:                  proc "c" (
		data: rawptr,
		pointer: ^Pointer,
		time: c.uint32_t,
		surface_x: Fixed,
		surface_y: Fixed,
	),
	button:                  proc "c" (
		data: rawptr,
		pointer: ^Pointer,
		serial: c.uint32_t,
		time: c.uint32_t,
		button: c.uint32_t,
		state: c.uint32_t,
	),
	axis:                    proc "c" (
		data: rawptr,
		pointer: ^Pointer,
		time: c.uint32_t,
		axis: c.uint32_t,
		value: Fixed,
	),
	frame:                   proc "c" (data: rawptr, pointer: ^Pointer),
	axis_source:             proc "c" (
		data: rawptr,
		pointer: ^Pointer,
		axis_source: c.uint32_t,
	),
	axis_stop:               proc "c" (
		data: rawptr,
		pointer: ^Pointer,
		time: c.uint32_t,
		axis: c.uint32_t,
	),
	axis_discrete:           proc "c" (
		data: rawptr,
		pointer: ^Pointer,
		axis: c.uint32_t,
		discrete: c.int32_t,
	),
	axis_value120:           proc "c" (
		data: rawptr,
		pointer: ^Pointer,
		axis: c.uint32_t,
		value120: c.int32_t,
	),
	axis_relative_direction: proc "c" (
		data: rawptr,
		pointer: ^Pointer,
		axis: c.uint32_t,
		direction: c.uint32_t,
	),
}

Pointer :: struct {}

Pointer_Listener :: struct {
	enter: proc "c" (
		data: rawptr,
		pointer: ^Pointer,
		serial: c.uint32_t,
		surface: ^Surface,
		surface_x: Fixed,
		surface_y: Fixed,
	),
	leave: proc "c" (
		data: rawptr,
		pointer: ^Pointer,
		serial: c.uint32_t,
		surface: ^Surface,
	),
	motion: proc "c" (
		data: rawptr,
		pointer: ^Pointer,
		time: c.uint32_t,
		surface_x: Fixed,
		surface_y: Fixed,
	),
	button: proc "c" (
		data: rawptr,
		pointer: ^Pointer,
		serial: c.uint32_t,
		time: c.uint32_t,
		button: c.uint32_t,
		state: c.uint32_t,
	),
	axis: proc "c" (
		data: rawptr,
		pointer: ^Pointer,
		time: c.uint32_t,
		axis: c.uint32_t,
		value: Fixed,
	),
	frame: proc "c" (data: rawptr, pointer: ^Pointer),
	axis_source: proc "c" (
		data: rawptr,
		pointer: ^Pointer,
		axis_source: c.uint32_t,
	),
	axis_stop: proc "c" (
		data: rawptr,
		pointer: ^Pointer,
		time: c.uint32_t,
		axis: c.uint32_t,
	),
	axis_discrete: proc "c" (
		data: rawptr,
		pointer: ^Pointer,
		axis: c.uint32_t,
		discrete: c.int32_t,
	),
	axis_value120: proc "c" (
		data: rawptr,
		pointer: ^Pointer,
		axis: c.uint32_t,
		value120: c.int32_t,
	),
	axis_relative_direction: proc "c" (
		data: rawptr,
		pointer: ^Pointer,
		axis: c.uint32_t,
		direction: c.uint32_t,
	),
}

wl_pointer_interface: Interface = {}
@(init)
init_wl_pointer_interface :: proc "contextless" () {
	wl_pointer_interface = {"wl_pointer", 9, 2, &wl_pointer_requests[0], 11, &wl_pointer_events[0]}
}

pointer_release :: proc "c" (pointer: ^Pointer) {
	proxy_marshal_flags(
		(^Proxy)(pointer),
		1,
		nil,
		proxy_get_version((^Proxy)(pointer)),
		MARSHAL_FLAG_DESTROY,
	)
}

// KEYBOARD INTERFACE


wl_keyboard_requests: []Message = []Message{{"release", "", raw_data([]^Interface{})}}

wl_keyboard_events: []Message = []Message {
	{"keymap", "uhu", raw_data([]^Interface{nil, nil, nil})},
	{"enter", "uoa", raw_data([]^Interface{nil, &surface_interface, nil})},
	{"leave", "uo", raw_data([]^Interface{nil, &surface_interface})},
	{"key", "uuuu", raw_data([]^Interface{nil, nil, nil, nil})},
	{"modifiers", "uuuuu", raw_data([]^Interface{nil, nil, nil, nil, nil})},
	{"repeat_info", "ii", raw_data([]^Interface{nil, nil})},
}

wl_keyboard_interface: Interface = {}
@(init)
init_wl_keyboard_interface :: proc "contextless" () {
	wl_keyboard_interface = {
		"wl_keyboard",
		9,
		1,
		&wl_keyboard_requests[0],
		6,
		&wl_keyboard_events[0],
	}
}

// TOUCH INTERFACE


wl_touch_requests: []Message = []Message{{"release", "", raw_data([]^Interface{})}}

wl_touch_events: []Message = []Message {
	{"down", "uuoiff", raw_data([]^Interface{nil, nil, &surface_interface, nil, nil, nil})},
	{"up", "uui", raw_data([]^Interface{nil, nil, nil})},
	{"motion", "uiff", raw_data([]^Interface{nil, nil, nil, nil})},
	{"frame", "", raw_data([]^Interface{})},
	{"cancel", "", raw_data([]^Interface{})},
	{"shape", "iff", raw_data([]^Interface{nil, nil, nil})},
	{"orientation", "if", raw_data([]^Interface{nil, nil})},
}

wl_touch_interface: Interface = {}
@(init)
init_wl_touch_interface :: proc "contextless" () {
	wl_touch_interface = {"wl_touch", 9, 1, &wl_touch_requests[0], 7, &wl_touch_events[0]}
}



// SEAT INTERFACE

Seat :: struct {}

Seat_Capability :: enum u32 {
	Pointer, // Mouse
	Keyboard,
	Touch,
}

Seat_Capabilities :: bit_set[Seat_Capability; u32]

Seat_Listener :: struct {
	capabilities: proc "c" (data: rawptr, seat: ^Seat, capabilities: Seat_Capabilities),
	name:         proc "c" (data: rawptr, seat: ^Seat, name: cstring),
}

wl_seat_requests: []Message = []Message {
	{"get_pointer", "n", raw_data([]^Interface{&wl_pointer_interface})},
	{"get_keyboard", "n", raw_data([]^Interface{&wl_keyboard_interface})},
	{"get_touch", "n", raw_data([]^Interface{&wl_touch_interface})},
	{"release", "", raw_data([]^Interface{})},
}

wl_seat_events: []Message = []Message {
	{"capabilities", "u", raw_data([]^Interface{nil})},
	{"name", "s", raw_data([]^Interface{nil})},
}

seat_interface: Interface = {}
@(init)
init_seat_interface :: proc "contextless" () {
	seat_interface = {"wl_seat", 9, 4, &wl_seat_requests[0], 2, &wl_seat_events[0]}
}

seat_get_pointer :: proc "c" (seat: ^Seat) -> ^Pointer {
	proxy := proxy_marshal_flags(
		cast(^Proxy)seat,
		0,
		&wl_pointer_interface,
		proxy_get_version(cast(^Proxy)seat),
		0,
		nil,
	)

	return (^Pointer)(proxy)
}

// XDG POPUP INTERFACE

xdg_popup_requests: []Message = []Message {
	{"destroy", "", raw_data([]^Interface{})},
	{"grab", "ou", raw_data([]^Interface{&seat_interface, nil})},
	{"reposition", "ou", raw_data([]^Interface{&xdg_positioner_interface, nil})},
}

xdg_popup_events: []Message = []Message {
	{"configure", "iiii", raw_data([]^Interface{nil, nil, nil, nil})},
	{"popup_done", "", raw_data([]^Interface{})},
	{"repositioned", "u", raw_data([]^Interface{nil})},
}

xdg_popup_interface: Interface = {}
@(init)
init_xdg_popup_interface :: proc "contextless" () {
	xdg_popup_interface = {"xdg_popup", 6, 3, &xdg_popup_requests[0], 3, &xdg_popup_events[0]}
}

// XDG TOP LEVEL INTERFACE


xdg_toplevel_requests: []Message = []Message {
	{"destroy", "", raw_data([]^Interface{})},
	{"set_parent", "?o", raw_data([]^Interface{&xdg_toplevel_interface})},
	{"set_title", "s", raw_data([]^Interface{nil})},
	{"set_app_id", "s", raw_data([]^Interface{nil})},
	{"show_window_menu", "ouii", raw_data([]^Interface{&seat_interface, nil, nil, nil})},
	{"move", "ou", raw_data([]^Interface{&seat_interface, nil})},
	{"resize", "ouu", raw_data([]^Interface{&seat_interface, nil, nil})},
	{"set_max_size", "ii", raw_data([]^Interface{nil, nil})},
	{"set_min_size", "ii", raw_data([]^Interface{nil, nil})},
	{"set_maximized", "", raw_data([]^Interface{})},
	{"unset_maximized", "", raw_data([]^Interface{})},
	{"set_fullscreen", "?o", raw_data([]^Interface{&wl_output_interface})},
	{"unset_fullscreen", "", raw_data([]^Interface{})},
	{"set_minimized", "", raw_data([]^Interface{})},
}

xdg_toplevel_events: []Message = []Message {
	{"configure", "iia", raw_data([]^Interface{nil, nil, nil})},
	{"close", "", raw_data([]^Interface{})},
	{"configure_bounds", "ii", raw_data([]^Interface{nil, nil})},
	{"wm_capabilities", "a", raw_data([]^Interface{nil})},
}

xdg_toplevel_interface: Interface = {}
@(init)
init_xdg_toplevel_interface :: proc "contextless" () {
	xdg_toplevel_interface = {
		"xdg_toplevel",
		6,
		14,
		&xdg_toplevel_requests[0],
		4,
		&xdg_toplevel_events[0],
	}
}

// XDG WM BASE INTERFACE


XDG_WM_Base :: struct {}
XDG_WM_Base_Listener :: struct {
	ping: proc "c" (data: rawptr, xdg_wm_base: ^XDG_WM_Base, serial: c.uint32_t),
}


xdg_wm_base_pong :: proc "c" (xdg_wm_base: ^XDG_WM_Base, serial: c.uint32_t) {
	proxy_marshal_flags(
		cast(^Proxy)xdg_wm_base,
		3,
		nil,
		proxy_get_version(cast(^Proxy)xdg_wm_base),
		0,
		serial,
	)
}


xdg_surface_requests: []Message = []Message {
	{"destroy", "", raw_data([]^Interface{})},
	{"get_toplevel", "n", raw_data([]^Interface{&xdg_toplevel_interface})},
	{
		"get_popup",
		"n?oo",
		raw_data(
			[]^Interface {
				&xdg_popup_interface,
				&xdg_surface_interface,
				&xdg_positioner_interface,
			},
		),
	},
	{"set_window_geometry", "iiii", raw_data([]^Interface{nil, nil, nil, nil})},
	{"ack_configure", "u", raw_data([]^Interface{nil})},
}

xdg_surface_events: []Message = []Message{{"configure", "u", raw_data([]^Interface{nil})}}

xdg_surface_interface: Interface = {}
@(init)
init_xdg_surface_interface :: proc "contextless" () {
	xdg_surface_interface = {
		"xdg_surface",
		6,
		5,
		&xdg_surface_requests[0],
		1,
		&xdg_surface_events[0],
	}
}


xdg_wm_base_requests: []Message = []Message {
	{"destroy", "", raw_data([]^Interface{})},
	{"create_positioner", "n", raw_data([]^Interface{&xdg_positioner_interface})},
	{
		"get_xdg_surface",
		"no",
		raw_data([]^Interface{&xdg_surface_interface, &surface_interface}),
	},
	{"pong", "u", raw_data([]^Interface{nil})},
}

xdg_wm_base_events: []Message = []Message{{"ping", "u", raw_data([]^Interface{nil})}}

xdg_wm_base_interface: Interface = {}
@(init)
init_xdg_wm_base_interface :: proc "contextless" () {
	xdg_wm_base_interface = {
		"xdg_wm_base",
		6,
		4,
		&xdg_wm_base_requests[0],
		1,
		&xdg_wm_base_events[0],
	}
}

// XDG POSITIONER INTERFACE


xdg_positioner_requests: []Message = []Message {
	{"destroy", "", raw_data([]^Interface{})},
	{"set_size", "ii", raw_data([]^Interface{nil, nil})},
	{"set_anchor_rect", "iiii", raw_data([]^Interface{nil, nil, nil, nil})},
	{"set_anchor", "u", raw_data([]^Interface{nil})},
	{"set_gravity", "u", raw_data([]^Interface{nil})},
	{"set_constraint_adjustment", "u", raw_data([]^Interface{nil})},
	{"set_offset", "ii", raw_data([]^Interface{nil, nil})},
	{"set_reactive", "", raw_data([]^Interface{})},
	{"set_parent_size", "ii", raw_data([]^Interface{nil, nil})},
	{"set_parent_configure", "u", raw_data([]^Interface{nil})},
}

xdg_positioner_events: []Message = []Message{}

xdg_positioner_interface: Interface = {}
@(init)
init_xdg_positioner_interface :: proc "contextless" () {
	xdg_positioner_interface = {"xdg_positioner", 6, 10, &xdg_positioner_requests[0], 0, nil}
}


// SURFACE INTERFACE

surface_interface_requests := [?]Message {
	{"destroy", "", raw_data([]^Interface{})},
	{"attach", "?oii", raw_data([]^Interface{&buffer_interface, nil, nil})},
	{"damage", "iiii", raw_data([]^Interface{nil, nil, nil, nil})},
	{"frame", "n", raw_data([]^Interface{&wl_callback_interface})},
	{"set_opaque_region", "?o", raw_data([]^Interface{&wl_region_interface})},
	{"set_input_region", "?o", raw_data([]^Interface{&wl_region_interface})},
	{"commit", "", raw_data([]^Interface{})},
	{"set_buffer_transform", "i", raw_data([]^Interface{nil})},
	{"set_buffer_scale", "i", raw_data([]^Interface{nil})},
	{"damage_buffer", "iiii", raw_data([]^Interface{nil, nil, nil, nil})},
	{"offset", "ii", raw_data([]^Interface{nil, nil})},
}

surface_interface_events := [?]Message {
	{"enter", "o", raw_data([]^Interface{&wl_output_interface})},
	{"leave", "o", raw_data([]^Interface{&wl_output_interface})},
	{"preferred_buffer_scale", "i", raw_data([]^Interface{nil})},
	{"preferred_buffer_transform", "u", raw_data([]^Interface{nil})},
}

surface_interface: Interface = {}
@(init)
init_surface_interface :: proc "contextless" () {
	surface_interface = {"wl_surface", 6, 11, raw_data(&surface_interface_requests), 4, raw_data(&surface_interface_events)}
}

display_registry_interface_requests := [?]Message {
	{"bind", "usun", raw_data([]^Interface{nil, nil, nil, nil})},
}

display_registry_interface_events := [?]Message {
	{"global", "usu", raw_data([]^Interface{nil, nil, nil})},
	{"global_remove", "u", raw_data([]^Interface{nil})},
}

display_get_registry :: proc "c" (display: ^Display) -> ^Registry {
	@static registry_interface: Interface

	if registry_interface.name == "" {
		registry_interface = {
			"wl_registry",
			1,
			1,
			raw_data(&display_registry_interface_requests),
			2,
			raw_data(&display_registry_interface_events),
		}
	}

	registry_proxy := proxy_marshal_flags(
		(^Proxy)(display),
		1,
		&registry_interface,
		proxy_get_version((^Proxy)(display)),
		0,
		nil,
	)

	return (^Registry)(registry_proxy)
}


registry_bind :: proc "c" (
	registry: ^Registry,
	name: c.uint32_t,
	interface: ^Interface,
	version: c.uint32_t,
) -> rawptr {
	id := proxy_marshal_flags(
		cast(^Proxy)registry,
		0,
		interface,
		version,
		0,
		name,
		interface.name,
		version,
		nil,
	)

	return rawptr(id)
}