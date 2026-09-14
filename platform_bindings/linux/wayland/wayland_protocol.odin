package wayland

import "core:c"

add_listener :: proc(
	proxy: ^Proxy,
	listener: ^$Listener_Type,
	data: rawptr,
) -> c.int {
	return proxy_add_listener(proxy, rawptr(listener), data)
}

DISPLAY_GET_REGISTRY :: 1

display_get_registry :: proc "c" (display: ^Display) -> ^Registry {
	return (^Registry)(proxy_marshal_flags(
		display,
		DISPLAY_GET_REGISTRY,
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

REGISTRY_BIND :: 0

// Bound at the version these bindings implement at most. Binding at whatever the
// compositor advertises tells it we understand events we don't, and an event past the
// end of our event table makes libwayland abort the process.
registry_bind :: proc(
	$T: typeid,
	registry: ^Registry,
	name: u32,
	interface: ^Interface,
	version: u32,
) -> ^T {
	bind_version := min(version, u32(interface.version))

	return (^T)(proxy_marshal_flags(
		registry,
		REGISTRY_BIND,
		interface,
		bind_version,
		0,
		name,
		interface.name,
		bind_version,
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
		COMPOSITOR_CREATE_SURFACE,
		&surface_interface,
		proxy_get_version(compositor),
		0,
		nil,
	))
}

compositor_create_region :: proc "c" (compositor: ^Compositor) -> ^Region {
	return (^Region)(proxy_marshal_flags(
		compositor,
		COMPOSITOR_CREATE_REGION,
		&region_interface,
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
		{"create_region", "n", raw_data([]^Interface{&region_interface})},
	}),
	0,
	nil,
}

COMPOSITOR_CREATE_SURFACE :: 0
COMPOSITOR_CREATE_REGION :: 1


Region :: struct {
	using proxy: Proxy,
}

region_destroy :: proc "c" (region: ^Region) {
	proxy_marshal_flags(
		region,
		REGION_DESTROY,
		nil,
		proxy_get_version(region),
		MARSHAL_FLAG_DESTROY,
	)
}

region_add :: proc "c" (
	region: ^Region,
	x: c.int32_t,
	y: c.int32_t,
	width: c.int32_t,
	height: c.int32_t,
) {
	proxy_marshal_flags(region, REGION_ADD, nil, proxy_get_version(region), 0, x, y, width, height)
}

region_interface := Interface {
	"wl_region",
	1,
	3,
	raw_data([]Message {
		{"destroy", "", raw_data([]^Interface{})},
		{"add", "iiii", raw_data([]^Interface{nil, nil, nil, nil})},
		{"subtract", "iiii", raw_data([]^Interface{nil, nil, nil, nil})},
	}),
	0,
	nil,
}

REGION_DESTROY :: 0
REGION_ADD :: 1
REGION_SUBTRACT :: 2


Buffer :: struct {
	using proxy: Proxy,
}

Buffer_Listener :: struct {
	release: proc "c" (data: rawptr, buffer: ^Buffer),
}

buffer_destroy :: proc "c" (buffer: ^Buffer) {
	proxy_marshal_flags(
		buffer,
		BUFFER_DESTROY,
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

BUFFER_DESTROY :: 0


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
		SURFACE_DESTROY,
		nil,
		proxy_get_version(surface),
		MARSHAL_FLAG_DESTROY,
	)
}

surface_attach :: proc "c" (surface: ^Surface, buffer: ^Buffer, x: c.int32_t, y: c.int32_t) {
	proxy_marshal_flags(
		surface,
		SURFACE_ATTACH,
		nil,
		proxy_get_version(surface),
		0,
		buffer,
		x,
		y,
	)
}

// Marks a rectangle of the attached buffer as changed, in buffer pixels. A compositor is free to
// leave everything else as it was, so a new buffer only shows up once its area has been damaged.
surface_damage_buffer :: proc "c" (
	surface: ^Surface,
	x: c.int32_t,
	y: c.int32_t,
	width: c.int32_t,
	height: c.int32_t,
) {
	proxy_marshal_flags(
		surface,
		SURFACE_DAMAGE_BUFFER,
		nil,
		proxy_get_version(surface),
		0,
		x,
		y,
		width,
		height,
	)
}

// Which part of a surface takes pointer events. A surface with no region set takes them
// everywhere it reaches, transparent pixels included.
surface_set_input_region :: proc "c" (surface: ^Surface, region: ^Region) {
	proxy_marshal_flags(
		surface,
		SURFACE_SET_INPUT_REGION,
		nil,
		proxy_get_version(surface),
		0,
		region,
	)
}

surface_frame :: proc "c" (surface: ^Surface) -> ^Callback {
	callback: ^Proxy
	callback = proxy_marshal_flags(
		surface,
		SURFACE_FRAME,
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
		SURFACE_COMMIT,
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
		{"set_opaque_region", "?o", raw_data([]^Interface{&region_interface})},
		{"set_input_region", "?o", raw_data([]^Interface{&region_interface})},
		{"commit", "", raw_data([]^Interface{})},
		{"set_buffer_transform", "2i", raw_data([]^Interface{nil})},
		{"set_buffer_scale", "3i", raw_data([]^Interface{nil})},
		{"damage_buffer", "4iiii", raw_data([]^Interface{nil, nil, nil, nil})},
		{"offset", "5ii", raw_data([]^Interface{nil, nil})},
	}),
	4,
	raw_data([]Message {
		{"enter", "o", raw_data([]^Interface{&output_interface})},
		{"leave", "o", raw_data([]^Interface{&output_interface})},
		{"preferred_buffer_scale", "6i", raw_data([]^Interface{nil})},
		{"preferred_buffer_transform", "6u", raw_data([]^Interface{nil})},
	}),
}

SURFACE_DESTROY :: 0
SURFACE_ATTACH :: 1
SURFACE_DAMAGE :: 2
SURFACE_FRAME :: 3
SURFACE_SET_OPAQUE_REGION :: 4
SURFACE_SET_INPUT_REGION :: 5
SURFACE_COMMIT :: 6
SURFACE_SET_BUFFER_TRANSFORM :: 7
SURFACE_SET_BUFFER_SCALE :: 8
SURFACE_DAMAGE_BUFFER :: 9
SURFACE_OFFSET :: 10

SURFACE_ERROR_INVALID_SCALE :: 0
SURFACE_ERROR_INVALID_TRANSFORM :: 1
SURFACE_ERROR_INVALID_SIZE :: 2
SURFACE_ERROR_INVALID_OFFSET :: 3
SURFACE_ERROR_DEFUNCT_ROLE_OBJECT :: 4

Subcompositor :: struct {
	using proxy: Proxy,
}

subcompositor_get_subsurface :: proc "c" (
	subcompositor: ^Subcompositor,
	surface: ^Surface,
	parent: ^Surface,
) -> ^Subsurface {
	return (^Subsurface)(proxy_marshal_flags(
		subcompositor,
		SUBCOMPOSITOR_GET_SUBSURFACE,
		&subsurface_interface,
		proxy_get_version(subcompositor),
		0,
		nil,
		surface,
		parent,
	))
}

subcompositor_interface := Interface {
	"wl_subcompositor",
	1,
	2,
	raw_data([]Message {
		{"destroy", "", raw_data([]^Interface{})},
		{
			"get_subsurface", "noo",
			raw_data([]^Interface{&subsurface_interface, &surface_interface, &surface_interface}),
		},
	}),
	0,
	nil,
}

SUBCOMPOSITOR_DESTROY :: 0
SUBCOMPOSITOR_GET_SUBSURFACE :: 1

SUBCOMPOSITOR_ERROR_BAD_SURFACE :: 0
SUBCOMPOSITOR_ERROR_BAD_PARENT :: 1


Subsurface :: struct {
	using proxy: Proxy,
}

subsurface_destroy :: proc "c" (subsurface: ^Subsurface) {
	proxy_marshal_flags(
		subsurface,
		SUBSURFACE_DESTROY,
		nil,
		proxy_get_version(subsurface),
		MARSHAL_FLAG_DESTROY,
	)
}

subsurface_set_position :: proc "c" (subsurface: ^Subsurface, x: c.int32_t, y: c.int32_t) {
	proxy_marshal_flags(
		subsurface,
		SUBSURFACE_SET_POSITION,
		nil,
		proxy_get_version(subsurface),
		0,
		x,
		y,
	)
}

subsurface_interface := Interface {
	"wl_subsurface",
	1,
	6,
	raw_data([]Message {
		{"destroy", "", raw_data([]^Interface{})},
		{"set_position", "ii", raw_data([]^Interface{nil, nil})},
		{"place_above", "o", raw_data([]^Interface{&surface_interface})},
		{"place_below", "o", raw_data([]^Interface{&surface_interface})},
		{"set_sync", "", raw_data([]^Interface{})},
		{"set_desync", "", raw_data([]^Interface{})},
	}),
	0,
	nil,
}

SUBSURFACE_DESTROY :: 0
SUBSURFACE_SET_POSITION :: 1
SUBSURFACE_PLACE_ABOVE :: 2
SUBSURFACE_PLACE_BELOW :: 3
SUBSURFACE_SET_SYNC :: 4
SUBSURFACE_SET_DESYNC :: 5

SUBSURFACE_ERROR_BAD_SURFACE :: 0

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
		SEAT_GET_POINTER,
		&pointer_interface,
		proxy_get_version(seat),
		0,
		nil,
	))
}

seat_get_keyboard :: proc "c" (seat: ^Seat) -> ^Keyboard {
	return (^Keyboard)(proxy_marshal_flags(
		seat,
		SEAT_GET_KEYBOARD,
		&keyboard_interface,
		proxy_get_version(seat),
		0,
		nil,
	))
}

seat_get_touch :: proc "c" (seat: ^Seat) -> ^Touch {
	return (^Touch)(proxy_marshal_flags(
		seat,
		SEAT_GET_TOUCH,
		&touch_interface,
		proxy_get_version(seat),
		0,
		nil,
	))
}

seat_release :: proc "c" (seat: ^Seat) {
	proxy_marshal_flags(
		seat,
		SEAT_RELEASE,
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
		{"release", "5", raw_data([]^Interface{})},
	}),
	2,
	raw_data([]Message {
		{"capabilities", "u", raw_data([]^Interface{nil})},
		{"name", "2s", raw_data([]^Interface{nil})},
	}),
}

SEAT_GET_POINTER :: 0
SEAT_GET_KEYBOARD :: 1
SEAT_GET_TOUCH :: 2
SEAT_RELEASE :: 3

SEAT_ERROR_MISSING_CAPABILITY :: 0

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
		POINTER_SET_CURSOR,
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
		POINTER_RELEASE,
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
		{"release", "3", raw_data([]^Interface{})},
	}),
	11,
	raw_data([]Message {
		{"enter", "uoff", raw_data([]^Interface{nil, &surface_interface, nil, nil})},
		{"leave", "uo", raw_data([]^Interface{nil, &surface_interface})},
		{"motion", "uff", raw_data([]^Interface{nil, nil, nil})},
		{"button", "uuuu", raw_data([]^Interface{nil, nil, nil, nil})},
		{"axis", "uuf", raw_data([]^Interface{nil, nil, nil})},
		{"frame", "5", raw_data([]^Interface{})},
		{"axis_source", "5u", raw_data([]^Interface{nil})},
		{"axis_stop", "5uu", raw_data([]^Interface{nil, nil})},
		{"axis_discrete", "5ui", raw_data([]^Interface{nil, nil})},
		{"axis_value120", "8ui", raw_data([]^Interface{nil, nil})},
		{"axis_relative_direction", "9uu", raw_data([]^Interface{nil, nil})},
	}),
}

POINTER_SET_CURSOR :: 0
POINTER_RELEASE :: 1

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

BTN_LEFT :: 0x110
BTN_RIGHT :: 0x111
BTN_MIDDLE :: 0x112
BTN_SIDE :: 0x113
BTN_EXTRA :: 0x114
BTN_FORWARD :: 0x115
BTN_BACK :: 0x116
BTN_TASK :: 0x117

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
		KEYBOARD_RELEASE,
		nil,
		proxy_get_version(keyboard),
		MARSHAL_FLAG_DESTROY,
	)
}

keyboard_interface := Interface {
	"wl_keyboard",
	9,
	1,
	raw_data([]Message{{"release", "3", raw_data([]^Interface{})}}),
	6,
	raw_data([]Message {
		{"keymap", "uhu", raw_data([]^Interface{nil, nil, nil})},
		{"enter", "uoa", raw_data([]^Interface{nil, &surface_interface, nil})},
		{"leave", "uo", raw_data([]^Interface{nil, &surface_interface})},
		{"key", "uuuu", raw_data([]^Interface{nil, nil, nil, nil})},
		{"modifiers", "uuuuu", raw_data([]^Interface{nil, nil, nil, nil, nil})},
		{"repeat_info", "4ii", raw_data([]^Interface{nil, nil})},
	}),
}

KEYBOARD_RELEASE :: 0

KEYBOARD_KEYMAP_FORMAT_NO_KEYMAP :: 0
KEYBOARD_KEYMAP_FORMAT_XKB_V1 :: 1
KEYBOARD_KEY_STATE_RELEASED :: 0
KEYBOARD_KEY_STATE_PRESSED :: 1
KEYBOARD_KEY_STATE_REPEATED :: 2


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
		TOUCH_RELEASE,
		nil,
		proxy_get_version(touch),
		MARSHAL_FLAG_DESTROY,
	)
}

touch_interface := Interface {
	"wl_touch",
	9,
	1,
	raw_data([]Message{{"release", "3", raw_data([]^Interface{})}}),
	7,
	raw_data([]Message {
		{"down", "uuoiff", raw_data([]^Interface{nil, nil, &surface_interface, nil, nil, nil})},
		{"up", "uui", raw_data([]^Interface{nil, nil, nil})},
		{"motion", "uiff", raw_data([]^Interface{nil, nil, nil, nil})},
		{"frame", "", raw_data([]^Interface{})},
		{"cancel", "", raw_data([]^Interface{})},
		{"shape", "6iff", raw_data([]^Interface{nil, nil, nil})},
		{"orientation", "6if", raw_data([]^Interface{nil, nil})},
	}),
}

TOUCH_RELEASE :: 0

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
		OUTPUT_RELEASE,
		nil,
		proxy_get_version(output),
		MARSHAL_FLAG_DESTROY,
	)
}

output_interface := Interface {
	"wl_output",
	4,
	1,
	raw_data([]Message{{"release", "3", raw_data([]^Interface{})}}),
	6,
	raw_data([]Message {
		{"geometry", "iiiiissi", raw_data([]^Interface{nil, nil, nil, nil, nil, nil, nil, nil})},
		{"mode", "uiii", raw_data([]^Interface{nil, nil, nil, nil})},
		{"done", "2", raw_data([]^Interface{})},
		{"scale", "2i", raw_data([]^Interface{nil})},
		{"name", "4s", raw_data([]^Interface{nil})},
		{"description", "4s", raw_data([]^Interface{nil})},
	}),
}

OUTPUT_RELEASE :: 0

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

SHM_Pool :: struct {
	using proxy: Proxy,
}

SHM_ERROR_INVALID_FORMAT :: 0
SHM_ERROR_INVALID_STRIDE :: 1
SHM_ERROR_INVALID_FD :: 2

SHM_FORMAT_ARGB8888 :: u32(0)
SHM_FORMAT_XRGB8888 :: u32(1)

shm_create_pool :: proc "c" (shm: ^SHM, fd: c.int32_t, size: c.int32_t) -> ^SHM_Pool {
	return (^SHM_Pool)(proxy_marshal_flags(
		shm,
		SHM_CREATE_POOL,
		&shm_pool_interface,
		proxy_get_version(shm),
		0,
		nil,
		fd,
		size,
	))
}

shm_pool_interface := Interface {
	"wl_shm_pool",
	2,
	3,
	raw_data([]Message{
		{
			"create_buffer", "niiiiu",
			raw_data([]^Interface{&buffer_interface, nil, nil, nil, nil, nil}),
		},
		{"destroy", "", raw_data([]^Interface{})},
		{"resize", "i", raw_data([]^Interface{nil})},
	}),
	0,
	nil,
}

SHM_POOL_CREATE_BUFFER :: 0
SHM_POOL_DESTROY :: 1
SHM_POOL_RESIZE :: 2

shm_pool_create_buffer :: proc "c" (
	pool: ^SHM_Pool,
	offset: c.int32_t,
	width: c.int32_t,
	height: c.int32_t,
	stride: c.int32_t,
	format: u32,
) -> ^Buffer {
	return (^Buffer)(proxy_marshal_flags(
		pool,
		SHM_POOL_CREATE_BUFFER,
		&buffer_interface,
		proxy_get_version(pool),
		0,
		nil,
		offset,
		width,
		height,
		stride,
		format,
	))
}

shm_pool_destroy :: proc "c" (pool: ^SHM_Pool) {
	proxy_marshal_flags(pool, SHM_POOL_DESTROY, nil, proxy_get_version(pool), MARSHAL_FLAG_DESTROY)
}

WP_Cursor_Shape_Manager_V1 :: struct {
	using proxy: Proxy,
}

wp_cursor_shape_manager_v1_interface := Interface {
	"wp_cursor_shape_manager_v1",
	1,
	2,
	raw_data([]Message{
		{"destroy", "", raw_data([]^Interface{})},
		{
			"get_pointer", "no",
			raw_data([]^Interface{&cursor_shape_device_interface, &pointer_interface}),
		},
	}),
	0,
	nil,
}

WP_CURSOR_SHAPE_MANAGER_V1_DESTROY :: 0
WP_CURSOR_SHAPE_MANAGER_V1_GET_POINTER :: 1

cursor_shape_manager_get_pointer :: proc "c" (
	manager: ^WP_Cursor_Shape_Manager_V1,
	pointer: ^Pointer,
) -> ^WP_Cursor_Shape_Device_V1 {
	return (^WP_Cursor_Shape_Device_V1)(proxy_marshal_flags(
		manager,
		WP_CURSOR_SHAPE_MANAGER_V1_GET_POINTER,
		&cursor_shape_device_interface,
		proxy_get_version(manager),
		0,
		nil,
		pointer,
	))
}

cursor_shape_manager_destroy :: proc "c" (manager: ^WP_Cursor_Shape_Manager_V1) {
	proxy_marshal_flags(
		manager,
		WP_CURSOR_SHAPE_MANAGER_V1_DESTROY,
		nil,
		proxy_get_version(manager),
		MARSHAL_FLAG_DESTROY,
	)
}

WP_Cursor_Shape_Device_V1 :: struct {
	using proxy: Proxy,
}

WP_Cursor_Shape :: enum u32 {
	Default        = 1,
	Context_Menu   = 2,
	Help           = 3,
	Pointer        = 4,
	Progress       = 5,
	Wait           = 6,
	Cell           = 7,
	Crosshair      = 8,
	Text           = 9,
	Vertical_Text  = 10,
	Alias          = 11,
	Copy           = 12,
	Move           = 13,
	No_Drop        = 14,
	Not_Allowed    = 15,
	Grab           = 16,
	Grabbing       = 17,
	E_Resize       = 18,
	N_Resize       = 19,
	Ne_Resize      = 20,
	Nw_Resize      = 21,
	S_Resize       = 22,
	Se_Resize      = 23,
	Sw_Resize      = 24,
	W_Resize       = 25,
	Ew_Resize      = 26,
	Ns_Resize      = 27,
	Nesw_Resize    = 28,
	Nwse_Resize    = 29,
	Col_Resize     = 30,
	Row_Resize     = 31,
	All_Scroll     = 32,
	Zoom_In        = 33,
	Zoom_Out       = 34,
}

cursor_shape_device_interface := Interface {
	"wp_cursor_shape_device_v1",
	1,
	2,
	raw_data([]Message{
		{"destroy", "", raw_data([]^Interface{})},
		{"set_shape", "uu", raw_data([]^Interface{nil, nil})},
	}),
	0,
	nil,
}

WP_CURSOR_SHAPE_DEVICE_V1_DESTROY :: 0
WP_CURSOR_SHAPE_DEVICE_V1_SET_SHAPE :: 1

WP_CURSOR_SHAPE_DEVICE_V1_ERROR_INVALID_SHAPE :: 1

cursor_shape_device_set_shape :: proc "c" (
	device: ^WP_Cursor_Shape_Device_V1,
	serial: u32,
	shape: WP_Cursor_Shape,
) {
	proxy_marshal_flags(
		device,
		WP_CURSOR_SHAPE_DEVICE_V1_SET_SHAPE,
		nil,
		proxy_get_version(device),
		0,
		serial,
		u32(shape),
	)
}

cursor_shape_device_destroy :: proc "c" (device: ^WP_Cursor_Shape_Device_V1) {
	proxy_marshal_flags(
		device,
		WP_CURSOR_SHAPE_DEVICE_V1_DESTROY,
		nil,
		proxy_get_version(device),
		MARSHAL_FLAG_DESTROY,
	)
}
