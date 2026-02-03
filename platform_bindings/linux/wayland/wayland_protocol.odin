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
		registry: ^Registry,
		name: u32,
		interface: cstring,
		version: u32,
	),
	global_remove: proc "c" (data: rawptr, registry: ^Registry, name: u32),
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
	done: proc "c" (data: rawptr, callback: ^Callback, callback_data: u32),
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
		{"create_region", "n", raw_data([]^Interface{nil})},
	}),
	0, 
	nil,
}


Buffer :: struct {
	using proxy: Proxy,
}

Buffer_Listener :: struct {
	release: proc "c" (data: rawptr, buffer: ^Buffer),
}

buffer_destroy :: proc "c" (buffer: ^Buffer) {
	proxy_marshal_flags(
		buffer,
		0,
		nil,
		proxy_get_version(buffer),
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
		surface: ^Surface,
		output: ^Output,
	),
	leave:                      proc "c" (
		data: rawptr,
		surface: ^Surface,
		output: ^Output,
	),
	preferred_buffer_scale:     proc "c" (
		data: rawptr,
		surface: ^Surface,
		factor: c.int32_t,
	),
	preferred_buffer_transform: proc "c" (
		data: rawptr,
		surface: ^Surface,
		transform: u32,
	),
}

surface_destroy :: proc "c" (surface: ^Surface) {
	proxy_marshal_flags(
		surface,
		0,
		nil,
		proxy_get_version(surface),
		MARSHAL_FLAG_DESTROY,
	)
}

surface_frame :: proc "c" (surface: ^Surface) -> ^Callback {
	callback: ^Proxy
	callback = proxy_marshal_flags(
		surface,
		3,
		&callback_interface,
		proxy_get_version(surface),
		0,
		nil,
	)

	return cast(^Callback)callback
}

surface_commit :: proc "c" (surface: ^Surface) {
	proxy_marshal_flags(
		surface,
		6,
		nil,
		proxy_get_version(surface),
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
		{"set_opaque_region", "?o", raw_data([]^Interface{nil})},
		{"set_input_region", "?o", raw_data([]^Interface{nil})},
		{"commit", "", raw_data([]^Interface{})},
		{"set_buffer_transform", "i", raw_data([]^Interface{nil})},
		{"set_buffer_scale", "i", raw_data([]^Interface{nil})},
		{"damage_buffer", "iiii", raw_data([]^Interface{nil, nil, nil, nil})},
		{"offset", "ii", raw_data([]^Interface{nil, nil})},
	}),
	4,
	raw_data([]Message {
		{"enter", "o", raw_data([]^Interface{&output_interface})},
		{"leave", "o", raw_data([]^Interface{&output_interface})},
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
		seat,
		3,
		nil,
		proxy_get_version(seat),
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
		pointer: ^Pointer,
		serial: u32,
		surface: ^Surface,
		surface_x: Fixed,
		surface_y: Fixed,
	),
	leave: proc "c" (
		data: rawptr,
		pointer: ^Pointer,
		serial: u32,
		surface: ^Surface,
	),
	motion: proc "c" (
		data: rawptr,
		pointer: ^Pointer,
		time: u32,
		surface_x: Fixed,
		surface_y: Fixed,
	),
	button: proc "c" (
		data: rawptr,
		pointer: ^Pointer,
		serial: u32,
		time: u32,
		button: u32,
		state: u32,
	),
	axis: proc "c" (
		data: rawptr,
		pointer: ^Pointer,
		time: u32,
		axis: u32,
		value: Fixed,
	),
	frame: proc "c" (data: rawptr, pointer: ^Pointer),
	axis_source: proc "c" (
		data: rawptr,
		pointer: ^Pointer,
		axis_source: u32,
	),
	axis_stop: proc "c" (
		data: rawptr,
		pointer: ^Pointer,
		time: u32,
		axis: u32,
	),
	axis_discrete: proc "c" (
		data: rawptr,
		pointer: ^Pointer,
		axis: u32,
		discrete: c.int32_t,
	),
	axis_value120: proc "c" (
		data: rawptr,
		pointer: ^Pointer,
		axis: u32,
		value120: c.int32_t,
	),
	axis_relative_direction: proc "c" (
		data: rawptr,
		pointer: ^Pointer,
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

pointer_release :: proc "c" (pointer: ^Pointer) {
	proxy_marshal_flags(
		pointer,
		1,
		nil,
		proxy_get_version(pointer),
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

POINTER_BTN_LEFT :: 0x110
POINTER_BTN_RIGHT :: 0x111
POINTER_BTN_MIDDLE :: 0x112
POINTER_BTN_SIDE :: 0x113
POINTER_BTN_EXTRA :: 0x114
POINTER_BTN_FORWARD :: 0x115
POINTER_BTN_BACK :: 0x116
POINTER_BTN_TASK :: 0x117

Keyboard :: struct {
	using proxy: Proxy,
}

Keyboard_Listener :: struct {
	keymap: proc "c" (
		data: rawptr,
		keyboard: ^Keyboard,
		format: u32,
		fd: c.int32_t,
		size: u32,
	),
	enter: proc "c" (
		data: rawptr,
		keyboard: ^Keyboard,
		serial: u32,
		surface: ^Surface,
		keys: ^Array,
	),
	leave: proc "c" (
		data: rawptr,
		keyboard: ^Keyboard,
		serial: u32,
		surface: ^Surface,
	),
	key: proc "c" (
		data: rawptr,
		keyboard: ^Keyboard,
		serial: u32,
		time: u32,
		key: u32,
		state: u32,
	),
	modifiers: proc "c" (
		data: rawptr,
		keyboard: ^Keyboard,
		serial: u32,
		mods_depressed: u32,
		mods_latched: u32,
		mods_locked: u32,
		group: u32,
	),
	repeat_info: proc "c" (
		data: rawptr,
		keyboard: ^Keyboard,
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

Output :: struct {
	using proxy: Proxy,
}

Output_Listener :: struct {
	geometry:    proc "c" (
		data: rawptr,
		output: ^Output,
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
		output: ^Output,
		flags: u32,
		width: c.int32_t,
		height: c.int32_t,
		refresh: c.int32_t,
	),
	done:        proc "c" (data: rawptr, output: ^Output),
	scale:       proc "c" (data: rawptr, output: ^Output, factor: c.int32_t),
	name:        proc "c" (data: rawptr, output: ^Output, name: cstring),
	description: proc "c" (data: rawptr, output: ^Output, description: cstring),
}

output_release :: proc "c" (output: ^Output) {
	proxy_marshal_flags(
		output,
		0,
		nil,
		proxy_get_version(output),
		MARSHAL_FLAG_DESTROY,
	)
}

output_interface := Interface {
	"wl_output",
	4,
	1,
	raw_data([]Message{{"release", "", raw_data([]^Interface{})}}),
	6,
	raw_data([]Message {
		{"geometry", "iiiiissi", raw_data([]^Interface{nil, nil, nil, nil, nil, nil, nil, nil})},
		{"mode", "uiii", raw_data([]^Interface{nil, nil, nil, nil})},
		{"done", "", raw_data([]^Interface{})},
		{"scale", "i", raw_data([]^Interface{nil})},
		{"name", "s", raw_data([]^Interface{nil})},
		{"description", "s", raw_data([]^Interface{nil})},
	}),
}

OUTPUT_SUBPIXEL_NONE :: 1
OUTPUT_SUBPIXEL_HORIZONTAL_RGB :: 2
OUTPUT_SUBPIXEL_HORIZONTAL_BGR :: 3
OUTPUT_SUBPIXEL_VERTICAL_RGB :: 4
OUTPUT_SUBPIXEL_VERTICAL_BGR :: 5
OUTPUT_SUBPIXEL_UNKNOWN :: 0
OUTPUT_TRANSFORM_FLIPPED_270 :: 7
OUTPUT_TRANSFORM_180 :: 2
OUTPUT_TRANSFORM_FLIPPED_180 :: 6
OUTPUT_TRANSFORM_FLIPPED_90 :: 5
OUTPUT_TRANSFORM_270 :: 3
OUTPUT_TRANSFORM_NORMAL :: 0
OUTPUT_TRANSFORM_FLIPPED :: 4
OUTPUT_TRANSFORM_90 :: 1
OUTPUT_MODE_CURRENT :: 0x1
OUTPUT_MODE_PREFERRED :: 0x2
