package wayland

import "core:c"

add_listener :: proc(
	proxy: ^Proxy,
	listener: ^$Listener_Type,
	data: rawptr,
) -> c.int {
	return proxy_add_listener(proxy, rawptr(listener), data)
}

display_get_registry :: proc "c" (display: ^Display) -> ^Registry {
	return (^Registry)(proxy_marshal_flags(
		display,
		1, // WL_DISPLAY_GET_REGISTRY
		&registry_interface,
		proxy_get_version(display),
		0,
		nil,
	))
}


Registry :: struct {
	using proxy: Proxy,
}

Registry_Listener :: struct {
	global: proc "c" (
		data: rawptr,
		wl_registry: ^Registry,
		name: u32,
		interface: cstring,
		version: u32,
	),
	global_remove: proc "c" (data: rawptr, wl_registry: ^Registry, name: u32),
}

registry_bind :: proc(
	$T: typeid,
	registry: ^Registry,
	name: u32,
	interface: ^Interface,
	version: u32,
) -> ^T {
	return (^T)(proxy_marshal_flags(
		registry,
		0,
		interface,
		version,
		0,
		name,
		interface.name,
		version,
		nil,
	))
}

destroy :: proc "c" (proxy: ^Proxy) {
	proxy_destroy(proxy)
}

registry_interface := Interface {
	"wl_registry",
	1,
	1,
	raw_data([]Message {
		{ "bind", "usun", raw_data([]^Interface{nil, nil, nil, nil})},
	}),
	2,
	raw_data([]Message {
		{"global", "usu", raw_data([]^Interface{nil, nil, nil})},
		{"global_remove", "u", raw_data([]^Interface{nil})},
	}),
}


Callback :: struct {
	using proxy: Proxy,
}

Callback_Listener :: struct {
	done: proc "c" (data: rawptr, wl_callback: ^Callback, callback_data: u32),
}

callback_interface := Interface {
	"wl_callback",
	1,
	0,
	nil,
	1,
	raw_data([]Message{{"done", "u", raw_data([]^Interface{nil})}}),
}


Compositor :: struct {
	using proxy: Proxy,
}

Compositor_Listener :: struct {}

compositor_create_surface :: proc "c" (compositor: ^Compositor) -> ^Surface {
	return (^Surface)(proxy_marshal_flags(
		compositor,
		0,
		&surface_interface,
		proxy_get_version(compositor),
		0,
		nil,
	))
}

compositor_interface := Interface {
	"wl_compositor",
	6, 
	2,
	raw_data([]Message {
		{"create_surface", "n", raw_data([]^Interface{&surface_interface})},
		{"create_region", "n", raw_data([]^Interface{&wl_region_interface})},
	}),
	0, 
	nil,
}


Buffer :: struct {}

Buffer_Listener :: struct {
	release: proc "c" (data: rawptr, wl_buffer: ^Buffer),
}

buffer_destroy :: proc "c" (buffer: ^Buffer) {
	proxy_marshal_flags(
		cast(^Proxy)buffer,
		0,
		nil,
		proxy_get_version(cast(^Proxy)buffer),
		MARSHAL_FLAG_DESTROY,
	)
}

buffer_interface := Interface {
	"wl_buffer",
	1,
	1, 
	raw_data([]Message{{"destroy", "", raw_data([]^Interface{})}}),
	1, 
	raw_data([]Message{{"release", "", raw_data([]^Interface{})}}),
}


Surface :: struct {
	using proxy: Proxy,
}

Surface_Listener :: struct {
	enter:                      proc "c" (
		data: rawptr,
		wl_surface: ^Surface,
		output: ^wl_output,
	),
	leave:                      proc "c" (
		data: rawptr,
		wl_surface: ^Surface,
		output: ^wl_output,
	),
	preferred_buffer_scale:     proc "c" (
		data: rawptr,
		wl_surface: ^Surface,
		factor: c.int32_t,
	),
	preferred_buffer_transform: proc "c" (
		data: rawptr,
		wl_surface: ^Surface,
		transform: u32,
	),
}

surface_destroy :: proc "c" (_wl_surface: ^Surface) {
	proxy_marshal_flags(
		cast(^Proxy)_wl_surface,
		0,
		nil,
		proxy_get_version(cast(^Proxy)_wl_surface),
		MARSHAL_FLAG_DESTROY,
	)
}

surface_frame :: proc "c" (_wl_surface: ^Surface) -> ^Callback {
	callback: ^Proxy
	callback = proxy_marshal_flags(
		cast(^Proxy)_wl_surface,
		3,
		&callback_interface,
		proxy_get_version(cast(^Proxy)_wl_surface),
		0,
		nil,
	)

	return cast(^Callback)callback
}

surface_commit :: proc "c" (_wl_surface: ^Surface) {
	proxy_marshal_flags(
		cast(^Proxy)_wl_surface,
		6,
		nil,
		proxy_get_version(cast(^Proxy)_wl_surface),
		0,
	)
}

surface_interface := Interface {
	"wl_surface",
	6,
	11,
	raw_data([]Message {
		{"destroy", "", raw_data([]^Interface{})},
		{"attach", "?oii", raw_data([]^Interface{&buffer_interface, nil, nil})},
		{"damage", "iiii", raw_data([]^Interface{nil, nil, nil, nil})},
		{"frame", "n", raw_data([]^Interface{&callback_interface})},
		{"set_opaque_region", "?o", raw_data([]^Interface{&wl_region_interface})},
		{"set_input_region", "?o", raw_data([]^Interface{&wl_region_interface})},
		{"commit", "", raw_data([]^Interface{})},
		{"set_buffer_transform", "i", raw_data([]^Interface{nil})},
		{"set_buffer_scale", "i", raw_data([]^Interface{nil})},
		{"damage_buffer", "iiii", raw_data([]^Interface{nil, nil, nil, nil})},
		{"offset", "ii", raw_data([]^Interface{nil, nil})},
	}),
	4,
	raw_data([]Message {
		{"enter", "o", raw_data([]^Interface{&wl_output_interface})},
		{"leave", "o", raw_data([]^Interface{&wl_output_interface})},
		{"preferred_buffer_scale", "i", raw_data([]^Interface{nil})},
		{"preferred_buffer_transform", "u", raw_data([]^Interface{nil})},
	}),
}

Seat :: struct {
	using proxy: Proxy,
}

Seat_Listener :: struct {
	capabilities: proc "c" (data: rawptr, seat: ^Seat, capabilities: Seat_Capabilities),
	name:         proc "c" (data: rawptr, seat: ^Seat, name: cstring),
}

seat_get_pointer :: proc "c" (seat: ^Seat) -> ^Pointer {
	return (^Pointer)(proxy_marshal_flags(
		seat,
		0,
		&pointer_interface,
		proxy_get_version(seat),
		0,
		nil,
	))
}

seat_get_keyboard :: proc "c" (seat: ^Seat) -> ^Keyboard {
	return (^Keyboard)(proxy_marshal_flags(
		seat,
		1,
		&keyboard_interface,
		proxy_get_version(seat),
		0,
		nil,
	))
}

seat_get_touch :: proc "c" (seat: ^Seat) -> ^Touch {
	return (^Touch)(proxy_marshal_flags(
		seat,
		2,
		&touch_interface,
		proxy_get_version(seat),
		0,
		nil,
	))
}

seat_release :: proc "c" (seat: ^Seat) {
	proxy_marshal_flags(
		cast(^Proxy)seat,
		3,
		nil,
		proxy_get_version(cast(^Proxy)seat),
		MARSHAL_FLAG_DESTROY,
	)
}

seat_interface := Interface {
	"wl_seat",
	9,
	4,
	raw_data([]Message {
		{"get_pointer", "n", raw_data([]^Interface{&pointer_interface})},
		{"get_keyboard", "n", raw_data([]^Interface{&keyboard_interface})},
		{"get_touch", "n", raw_data([]^Interface{&touch_interface})},
		{"release", "", raw_data([]^Interface{})},
	}),
	2,
	raw_data([]Message {
		{"capabilities", "u", raw_data([]^Interface{nil})},
		{"name", "s", raw_data([]^Interface{nil})},
	}),
}

Seat_Capability :: enum u32 {
	Pointer,
	Keyboard,
	Touch,
}

Seat_Capabilities :: bit_set[Seat_Capability; u32]


Pointer :: struct {
	using proxy: Proxy,
}

Pointer_Listener :: struct {
	enter: proc "c" (
		data: rawptr,
		wl_pointer: ^Pointer,
		serial: u32,
		surface: ^Surface,
		surface_x: Fixed,
		surface_y: Fixed,
	),
	leave: proc "c" (
		data: rawptr,
		wl_pointer: ^Pointer,
		serial: u32,
		surface: ^Surface,
	),
	motion: proc "c" (
		data: rawptr,
		wl_pointer: ^Pointer,
		time: u32,
		surface_x: Fixed,
		surface_y: Fixed,
	),
	button: proc "c" (
		data: rawptr,
		wl_pointer: ^Pointer,
		serial: u32,
		time: u32,
		button: u32,
		state: u32,
	),
	axis: proc "c" (
		data: rawptr,
		wl_pointer: ^Pointer,
		time: u32,
		axis: u32,
		value: Fixed,
	),
	frame: proc "c" (data: rawptr, wl_pointer: ^Pointer),
	axis_source: proc "c" (
		data: rawptr,
		wl_pointer: ^Pointer,
		axis_source: u32,
	),
	axis_stop: proc "c" (
		data: rawptr,
		wl_pointer: ^Pointer,
		time: u32,
		axis: u32,
	),
	axis_discrete: proc "c" (
		data: rawptr,
		wl_pointer: ^Pointer,
		axis: u32,
		discrete: c.int32_t,
	),
	axis_value120: proc "c" (
		data: rawptr,
		wl_pointer: ^Pointer,
		axis: u32,
		value120: c.int32_t,
	),
	axis_relative_direction: proc "c" (
		data: rawptr,
		wl_pointer: ^Pointer,
		axis: u32,
		direction: u32,
	),
}

pointer_set_cursor :: proc "c" (
	pointer: ^Pointer,
	serial: u32,
	surface: ^Surface,
	hotspot_x: c.int32_t,
	hotspot_y: c.int32_t,
) {
	proxy_marshal_flags(
		pointer,
		0,
		nil,
		proxy_get_version(pointer),
		0,
		serial,
		surface,
		hotspot_x,
		hotspot_y,
	)
}

pointer_release :: proc "c" (_wl_pointer: ^Pointer) {
	proxy_marshal_flags(
		cast(^Proxy)_wl_pointer,
		1,
		nil,
		proxy_get_version(cast(^Proxy)_wl_pointer),
		MARSHAL_FLAG_DESTROY,
	)
}

pointer_interface := Interface {
	"wl_pointer",
	9,
	2,
	raw_data([]Message {
		{"set_cursor", "u?oii", raw_data([]^Interface{nil, &surface_interface, nil, nil})},
		{"release", "", raw_data([]^Interface{})},
	}),
	11,
	raw_data([]Message {
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
	}),
}

POINTER_ERROR_ROLE :: 0
POINTER_BUTTON_STATE_PRESSED :: 1
POINTER_BUTTON_STATE_RELEASED :: 0
POINTER_AXIS_VERTICAL_SCROLL :: 0
POINTER_AXIS_HORIZONTAL_SCROLL :: 1
POINTER_AXIS_SOURCE_CONTINUOUS :: 2
POINTER_AXIS_SOURCE_WHEEL_TILT :: 3
POINTER_AXIS_SOURCE_WHEEL :: 0
POINTER_AXIS_SOURCE_FINGER :: 1
POINTER_AXIS_RELATIVE_DIRECTION_IDENTICAL :: 0
POINTER_AXIS_RELATIVE_DIRECTION_INVERTED :: 1


Keyboard :: struct {
	using proxy: Proxy,
}

Keyboard_Listener :: struct {
	keymap: proc "c" (
		data: rawptr,
		wl_keyboard: ^Keyboard,
		format: u32,
		fd: c.int32_t,
		size: u32,
	),
	enter: proc "c" (
		data: rawptr,
		wl_keyboard: ^Keyboard,
		serial: u32,
		surface: ^Surface,
		keys: ^Array,
	),
	leave: proc "c" (
		data: rawptr,
		wl_keyboard: ^Keyboard,
		serial: u32,
		surface: ^Surface,
	),
	key: proc "c" (
		data: rawptr,
		wl_keyboard: ^Keyboard,
		serial: u32,
		time: u32,
		key: u32,
		state: u32,
	),
	modifiers: proc "c" (
		data: rawptr,
		wl_keyboard: ^Keyboard,
		serial: u32,
		mods_depressed: u32,
		mods_latched: u32,
		mods_locked: u32,
		group: u32,
	),
	repeat_info: proc "c" (
		data: rawptr,
		wl_keyboard: ^Keyboard,
		rate: c.int32_t,
		delay: c.int32_t,
	),
}

keyboard_release :: proc "c" (keyboard: ^Keyboard) {
	proxy_marshal_flags(
		keyboard,
		0,
		nil,
		proxy_get_version(keyboard),
		MARSHAL_FLAG_DESTROY,
	)
}

keyboard_interface := Interface {
	"wl_keyboard",
	9,
	1,
	raw_data([]Message{{"release", "", raw_data([]^Interface{})}}),
	6,
	raw_data([]Message {
		{"keymap", "uhu", raw_data([]^Interface{nil, nil, nil})},
		{"enter", "uoa", raw_data([]^Interface{nil, &surface_interface, nil})},
		{"leave", "uo", raw_data([]^Interface{nil, &surface_interface})},
		{"key", "uuuu", raw_data([]^Interface{nil, nil, nil, nil})},
		{"modifiers", "uuuuu", raw_data([]^Interface{nil, nil, nil, nil, nil})},
		{"repeat_info", "ii", raw_data([]^Interface{nil, nil})},
	}),
}

KEYBOARD_KEYMAP_FORMAT_NO_KEYMAP :: 0
KEYBOARD_KEYMAP_FORMAT_XKB_V1 :: 1
KEYBOARD_KEY_STATE_RELEASED :: 0
KEYBOARD_KEY_STATE_PRESSED :: 1


Touch :: struct {
	using proxy: Proxy,
}

Touch_Listener :: struct {
	down: proc "c" (
		data: rawptr,
		touch: ^Touch,
		serial: u32,
		time: u32,
		surface: ^Surface,
		id: c.int32_t,
		x: Fixed,
		y: Fixed,
	),
	up: proc "c" (
		data: rawptr,
		touch: ^Touch,
		serial: u32,
		time: u32,
		id: c.int32_t,
	),
	motion: proc "c" (
		data: rawptr,
		touch: ^Touch,
		time: u32,
		id: c.int32_t,
		x: Fixed,
		y: Fixed,
	),
	frame: proc "c" (data: rawptr, touch: ^Touch),
	cancel: proc "c" (data: rawptr, touch: ^Touch),
	shape: proc "c" (
		data: rawptr,
		touch: ^Touch,
		id: c.int32_t,
		major: Fixed,
		minor: Fixed,
	),
	orientation: proc "c" (
		data: rawptr,
		touch: ^Touch,
		id: c.int32_t,
		orientation: Fixed,
	),
}

touch_release :: proc "c" (touch: ^Touch) {
	proxy_marshal_flags(
		touch,
		0,
		nil,
		proxy_get_version(touch),
		MARSHAL_FLAG_DESTROY,
	)
}

touch_interface := Interface {
	"wl_touch",
	9,
	1,
	raw_data([]Message{{"release", "", raw_data([]^Interface{})}}),
	7,
	raw_data([]Message {
		{"down", "uuoiff", raw_data([]^Interface{nil, nil, &surface_interface, nil, nil, nil})},
		{"up", "uui", raw_data([]^Interface{nil, nil, nil})},
		{"motion", "uiff", raw_data([]^Interface{nil, nil, nil, nil})},
		{"frame", "", raw_data([]^Interface{})},
		{"cancel", "", raw_data([]^Interface{})},
		{"shape", "iff", raw_data([]^Interface{nil, nil, nil})},
		{"orientation", "if", raw_data([]^Interface{nil, nil})},
	}),
}

wl_output :: struct {}
wl_output_listener :: struct {
	geometry:    proc "c" (
		data: rawptr,
		wl_output: ^wl_output,
		x: c.int32_t,
		y: c.int32_t,
		physical_width: c.int32_t,
		physical_height: c.int32_t,
		subpixel: c.int32_t,
		make: cstring,
		model: cstring,
		transform: c.int32_t,
	),
	mode:        proc "c" (
		data: rawptr,
		wl_output: ^wl_output,
		flags: u32,
		width: c.int32_t,
		height: c.int32_t,
		refresh: c.int32_t,
	),
	done:        proc "c" (data: rawptr, wl_output: ^wl_output),
	scale:       proc "c" (data: rawptr, wl_output: ^wl_output, factor: c.int32_t),
	name:        proc "c" (data: rawptr, wl_output: ^wl_output, name: cstring),
	description: proc "c" (data: rawptr, wl_output: ^wl_output, description: cstring),
}

wl_output_add_listener :: proc(
	wl_output: ^wl_output,
	listener: ^wl_output_listener,
	data: rawptr,
) -> c.int {

	return proxy_add_listener(cast(^Proxy)wl_output, cast(rawptr)listener, data)
}

wl_output_release :: proc "c" (_wl_output: ^wl_output) {
	proxy_marshal_flags(
		cast(^Proxy)_wl_output,
		0,
		nil,
		proxy_get_version(cast(^Proxy)_wl_output),
		MARSHAL_FLAG_DESTROY,
	)

}


wl_output_destroy :: proc "c" (wl_output: ^wl_output) {
	proxy_destroy(cast(^Proxy)wl_output)
}

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

WL_OUTPUT_SUBPIXEL_NONE :: 1
WL_OUTPUT_SUBPIXEL_HORIZONTAL_RGB :: 2
WL_OUTPUT_SUBPIXEL_HORIZONTAL_BGR :: 3
WL_OUTPUT_SUBPIXEL_VERTICAL_RGB :: 4
WL_OUTPUT_SUBPIXEL_VERTICAL_BGR :: 5
WL_OUTPUT_SUBPIXEL_UNKNOWN :: 0
WL_OUTPUT_TRANSFORM_FLIPPED_270 :: 7
WL_OUTPUT_TRANSFORM_180 :: 2
WL_OUTPUT_TRANSFORM_FLIPPED_180 :: 6
WL_OUTPUT_TRANSFORM_FLIPPED_90 :: 5
WL_OUTPUT_TRANSFORM_270 :: 3
WL_OUTPUT_TRANSFORM_NORMAL :: 0
WL_OUTPUT_TRANSFORM_FLIPPED :: 4
WL_OUTPUT_TRANSFORM_90 :: 1
WL_OUTPUT_MODE_CURRENT :: 0x1
WL_OUTPUT_MODE_PREFERRED :: 0x2

wl_region :: struct {}
wl_region_listener :: struct {}

wl_region_add_listener :: proc(
	wl_region: ^wl_region,
	listener: ^wl_region_listener,
	data: rawptr,
) -> c.int {

	return proxy_add_listener(cast(^Proxy)wl_region, cast(rawptr)listener, data)
}

wl_region_destroy :: proc "c" (_wl_region: ^wl_region) {
	proxy_marshal_flags(
		cast(^Proxy)_wl_region,
		0,
		nil,
		proxy_get_version(cast(^Proxy)_wl_region),
		MARSHAL_FLAG_DESTROY,
	)

}

wl_region_add :: proc "c" (
	_wl_region: ^wl_region,
	x: c.int32_t,
	y: c.int32_t,
	width: c.int32_t,
	height: c.int32_t,
) {
	proxy_marshal_flags(
		cast(^Proxy)_wl_region,
		1,
		nil,
		proxy_get_version(cast(^Proxy)_wl_region),
		0,
		x,
		y,
		width,
		height,
	)

}

wl_region_subtract :: proc "c" (
	_wl_region: ^wl_region,
	x: c.int32_t,
	y: c.int32_t,
	width: c.int32_t,
	height: c.int32_t,
) {
	proxy_marshal_flags(
		cast(^Proxy)_wl_region,
		2,
		nil,
		proxy_get_version(cast(^Proxy)_wl_region),
		0,
		x,
		y,
		width,
		height,
	)

}

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


wl_subcompositor :: struct {}
wl_subcompositor_listener :: struct {}

wl_subcompositor_add_listener :: proc(
	wl_subcompositor: ^wl_subcompositor,
	listener: ^wl_subcompositor_listener,
	data: rawptr,
) -> c.int {

	return proxy_add_listener(cast(^Proxy)wl_subcompositor, cast(rawptr)listener, data)
}

wl_subcompositor_destroy :: proc "c" (_wl_subcompositor: ^wl_subcompositor) {
	proxy_marshal_flags(
		cast(^Proxy)_wl_subcompositor,
		0,
		nil,
		proxy_get_version(cast(^Proxy)_wl_subcompositor),
		MARSHAL_FLAG_DESTROY,
	)

}

wl_subcompositor_get_subsurface :: proc "c" (
	_wl_subcompositor: ^wl_subcompositor,
	surface: ^Surface,
	parent: ^Surface,
) -> ^wl_subsurface {
	id: ^Proxy
	id = proxy_marshal_flags(
		cast(^Proxy)_wl_subcompositor,
		1,
		&wl_subsurface_interface,
		proxy_get_version(cast(^Proxy)_wl_subcompositor),
		0,
		nil,
		surface,
		parent,
	)


	return cast(^wl_subsurface)id
}

wl_subcompositor_requests: []Message = []Message {
	{"destroy", "", raw_data([]^Interface{})},
	{
		"get_subsurface",
		"noo",
		raw_data(
			[]^Interface {
				&wl_subsurface_interface,
				&surface_interface,
				&surface_interface,
			},
		),
	},
}

wl_subcompositor_events: []Message = []Message{}

wl_subcompositor_interface: Interface = {}
@(init)
init_wl_subcompositor_interface :: proc "contextless" () {
	wl_subcompositor_interface = {"wl_subcompositor", 1, 2, &wl_subcompositor_requests[0], 0, nil}
}

WL_SUBCOMPOSITOR_ERROR_BAD_SURFACE :: 0
WL_SUBCOMPOSITOR_ERROR_BAD_PARENT :: 1

wl_subsurface :: struct {}
wl_subsurface_listener :: struct {}

wl_subsurface_add_listener :: proc(
	wl_subsurface: ^wl_subsurface,
	listener: ^wl_subsurface_listener,
	data: rawptr,
) -> c.int {

	return proxy_add_listener(cast(^Proxy)wl_subsurface, cast(rawptr)listener, data)
}

wl_subsurface_destroy :: proc "c" (_wl_subsurface: ^wl_subsurface) {
	proxy_marshal_flags(
		cast(^Proxy)_wl_subsurface,
		0,
		nil,
		proxy_get_version(cast(^Proxy)_wl_subsurface),
		MARSHAL_FLAG_DESTROY,
	)

}

wl_subsurface_set_position :: proc "c" (
	_wl_subsurface: ^wl_subsurface,
	x: c.int32_t,
	y: c.int32_t,
) {
	proxy_marshal_flags(
		cast(^Proxy)_wl_subsurface,
		1,
		nil,
		proxy_get_version(cast(^Proxy)_wl_subsurface),
		0,
		x,
		y,
	)

}

wl_subsurface_place_above :: proc "c" (_wl_subsurface: ^wl_subsurface, sibling: ^Surface) {
	proxy_marshal_flags(
		cast(^Proxy)_wl_subsurface,
		2,
		nil,
		proxy_get_version(cast(^Proxy)_wl_subsurface),
		0,
		sibling,
	)

}

wl_subsurface_place_below :: proc "c" (_wl_subsurface: ^wl_subsurface, sibling: ^Surface) {
	proxy_marshal_flags(
		cast(^Proxy)_wl_subsurface,
		3,
		nil,
		proxy_get_version(cast(^Proxy)_wl_subsurface),
		0,
		sibling,
	)

}

wl_subsurface_set_sync :: proc "c" (_wl_subsurface: ^wl_subsurface) {
	proxy_marshal_flags(
		cast(^Proxy)_wl_subsurface,
		4,
		nil,
		proxy_get_version(cast(^Proxy)_wl_subsurface),
		0,
	)

}

wl_subsurface_set_desync :: proc "c" (_wl_subsurface: ^wl_subsurface) {
	proxy_marshal_flags(
		cast(^Proxy)_wl_subsurface,
		5,
		nil,
		proxy_get_version(cast(^Proxy)_wl_subsurface),
		0,
	)

}

wl_subsurface_requests: []Message = []Message {
	{"destroy", "", raw_data([]^Interface{})},
	{"set_position", "ii", raw_data([]^Interface{nil, nil})},
	{"place_above", "o", raw_data([]^Interface{&surface_interface})},
	{"place_below", "o", raw_data([]^Interface{&surface_interface})},
	{"set_sync", "", raw_data([]^Interface{})},
	{"set_desync", "", raw_data([]^Interface{})},
}

wl_subsurface_events: []Message = []Message{}

wl_subsurface_interface: Interface = {}
@(init)
init_wl_subsurface_interface :: proc "contextless" () {
	wl_subsurface_interface = {"wl_subsurface", 1, 6, &wl_subsurface_requests[0], 0, nil}
}

WL_SUBSURFACE_ERROR_BAD_SURFACE :: 0
