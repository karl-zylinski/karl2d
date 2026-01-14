package wayland

import "core:c"

XDG_WM_Base :: struct {
	using proxy: Proxy,
}

XDG_WM_Base_Listener :: struct {
	ping: proc "c" (data: rawptr, xdg_wm_base: ^XDG_WM_Base, serial: c.uint32_t),
}

xdg_wm_base_destroy :: proc "c" (xdg_wm_base: ^XDG_WM_Base) {
	proxy_marshal_flags(
		xdg_wm_base,
		0,
		nil,
		proxy_get_version(xdg_wm_base),
		MARSHAL_FLAG_DESTROY,
	)
}

xdg_wm_base_get_xdg_surface :: proc "c" (
	xdg_wm_base: ^XDG_WM_Base,
	surface: ^Surface,
) -> ^XDG_Surface {
	return (^XDG_Surface)(proxy_marshal_flags(
		xdg_wm_base,
		2,
		&xdg_surface_interface,
		proxy_get_version(xdg_wm_base),
		0,
		nil,
		surface,
	))
}

xdg_wm_base_pong :: proc "c" (xdg_wm_base: ^XDG_WM_Base, serial: c.uint32_t) {
	proxy_marshal_flags(
		xdg_wm_base,
		3,
		nil,
		proxy_get_version(xdg_wm_base),
		0,
		serial,
	)
}

xdg_wm_base_interface := Interface {
	"xdg_wm_base",
	6,
	4,
	raw_data([]Message {
		{"destroy", "", raw_data([]^Interface{})},
		{"create_positioner", "n", raw_data([]^Interface{nil})},
		{
			"get_xdg_surface",
			"no",
			raw_data([]^Interface{&xdg_surface_interface, &surface_interface}),
		},
		{"pong", "u", raw_data([]^Interface{nil})},
	}),
	1,
	raw_data([]Message{{"ping", "u", raw_data([]^Interface{nil})}}),
}

XDG_WM_BASE_ERROR_INVALID_SURFACE_STATE :: 4
XDG_WM_BASE_ERROR_DEFUNCT_SURFACES :: 1
XDG_WM_BASE_ERROR_INVALID_POSITIONER :: 5
XDG_WM_BASE_ERROR_NOT_THE_TOPMOST_POPUP :: 2
XDG_WM_BASE_ERROR_UNRESPONSIVE :: 6
XDG_WM_BASE_ERROR_ROLE :: 0
XDG_WM_BASE_ERROR_INVALID_POPUP_PARENT :: 3

XDG_Surface :: struct {
	using proxy: Proxy,
}
XDG_Surface_Listener :: struct {
	configure: proc "c" (data: rawptr, xdg_surface: ^XDG_Surface, serial: c.uint32_t),
}

xdg_surface_destroy :: proc "c" (xdg_surface: ^XDG_Surface) {
	proxy_marshal_flags(
		xdg_surface,
		0,
		nil,
		proxy_get_version(xdg_surface),
		MARSHAL_FLAG_DESTROY,
	)
}

xdg_surface_get_toplevel :: proc "c" (xdg_surface: ^XDG_Surface) -> ^XDG_Toplevel {
	return cast(^XDG_Toplevel)(proxy_marshal_flags(
		xdg_surface,
		1,
		&xdg_toplevel_interface,
		proxy_get_version(xdg_surface),
		0,
		nil,
	))
}

xdg_surface_set_window_geometry :: proc "c" (
	xdg_surface: ^XDG_Surface,
	x: c.int32_t,
	y: c.int32_t,
	width: c.int32_t,
	height: c.int32_t,
) {
	proxy_marshal_flags(
		xdg_surface,
		3,
		nil,
		proxy_get_version(xdg_surface),
		0,
		x,
		y,
		width,
		height,
	)
}

xdg_surface_ack_configure :: proc "c" (xdg_surface: ^XDG_Surface, serial: c.uint32_t) {
	proxy_marshal_flags(
		xdg_surface,
		4,
		nil,
		proxy_get_version(xdg_surface),
		0,
		serial,
	)
}

xdg_surface_interface := Interface {
	"xdg_surface",
	6,
	5,
	raw_data([]Message {
		{"destroy", "", raw_data([]^Interface{})},
		{"get_toplevel", "n", raw_data([]^Interface{&xdg_toplevel_interface})},
		{
			"get_popup",
			"n?oo",
			/*
			crashes compiler, circular loop:
			raw_data(
				[]^Interface {
					&xdg_popup_interface,
					&xdg_surface_interface,
					nil,
				},
			)

			so I set nil instead since I don't need it
			*/
			nil,
		},
		{"set_window_geometry", "iiii", raw_data([]^Interface{nil, nil, nil, nil})},
		{"ack_configure", "u", raw_data([]^Interface{nil})},
	}),
	1,
	raw_data([]Message{{"configure", "u", raw_data([]^Interface{nil})}}),
}

XDG_SURFACE_ERROR_ALREADY_CONSTRUCTED :: 2
XDG_SURFACE_ERROR_INVALID_SIZE :: 5
XDG_SURFACE_ERROR_UNCONFIGURED_BUFFER :: 3
XDG_SURFACE_ERROR_NOT_CONSTRUCTED :: 1
XDG_SURFACE_ERROR_DEFUNCT_ROLE_OBJECT :: 6
XDG_SURFACE_ERROR_INVALID_SERIAL :: 4

XDG_Toplevel :: struct {
	using proxy: Proxy,
}

XDG_Toplevel_Listener :: struct {
	configure: proc "c" (
		data: rawptr,
		xdg_toplevel: ^XDG_Toplevel,
		width: c.int32_t,
		height: c.int32_t,
		states: ^Array,
	),
	close: proc "c" (data: rawptr, xdg_toplevel: ^XDG_Toplevel),
	configure_bounds: proc "c" (
		data: rawptr,
		xdg_toplevel: ^XDG_Toplevel,
		width: c.int32_t,
		height: c.int32_t,
	),
	wm_capabilities: proc "c" (
		data: rawptr,
		xdg_toplevel: ^XDG_Toplevel,
		capabilities: ^Array,
	),
}

xdg_toplevel_destroy :: proc "c" (xdg_toplevel: ^XDG_Toplevel) {
	proxy_marshal_flags(
		xdg_toplevel,
		0,
		nil,
		proxy_get_version(xdg_toplevel),
		MARSHAL_FLAG_DESTROY,
	)
}

xdg_toplevel_set_parent :: proc "c" (xdg_toplevel: ^XDG_Toplevel, parent: ^XDG_Toplevel) {
	proxy_marshal_flags(
		xdg_toplevel,
		1,
		nil,
		proxy_get_version(xdg_toplevel),
		0,
		parent,
	)
}

xdg_toplevel_set_title :: proc "c" (xdg_toplevel: ^XDG_Toplevel, title: cstring) {
	proxy_marshal_flags(
		xdg_toplevel,
		2,
		nil,
		proxy_get_version(xdg_toplevel),
		0,
		title,
	)
}

xdg_toplevel_set_app_id :: proc "c" (xdg_toplevel: ^XDG_Toplevel, app_id: cstring) {
	proxy_marshal_flags(
		xdg_toplevel,
		3,
		nil,
		proxy_get_version(xdg_toplevel),
		0,
		app_id,
	)
}

xdg_toplevel_show_window_menu :: proc "c" (
	xdg_toplevel: ^XDG_Toplevel,
	seat: ^Seat,
	serial: c.uint32_t,
	x: c.int32_t,
	y: c.int32_t,
) {
	proxy_marshal_flags(
		xdg_toplevel,
		4,
		nil,
		proxy_get_version(xdg_toplevel),
		0,
		seat,
		serial,
		x,
		y,
	)
}

xdg_toplevel_move :: proc "c" (xdg_toplevel: ^XDG_Toplevel, seat: ^Seat, serial: c.uint32_t) {
	proxy_marshal_flags(
		xdg_toplevel,
		5,
		nil,
		proxy_get_version(xdg_toplevel),
		0,
		seat,
		serial,
	)
}

xdg_toplevel_resize :: proc "c" (
	xdg_toplevel: ^XDG_Toplevel,
	seat: ^Seat,
	serial: c.uint32_t,
	edges: c.uint32_t,
) {
	proxy_marshal_flags(
		xdg_toplevel,
		6,
		nil,
		proxy_get_version(xdg_toplevel),
		0,
		seat,
		serial,
		edges,
	)
}

xdg_toplevel_set_max_size :: proc "c" (
	xdg_toplevel: ^XDG_Toplevel,
	width: c.int32_t,
	height: c.int32_t,
) {
	proxy_marshal_flags(
		xdg_toplevel,
		7,
		nil,
		proxy_get_version(xdg_toplevel),
		0,
		width,
		height,
	)
}

xdg_toplevel_set_min_size :: proc "c" (
	xdg_toplevel: ^XDG_Toplevel,
	width: c.int32_t,
	height: c.int32_t,
) {
	proxy_marshal_flags(
		xdg_toplevel,
		8,
		nil,
		proxy_get_version(xdg_toplevel),
		0,
		width,
		height,
	)
}

xdg_toplevel_set_maximized :: proc "c" (xdg_toplevel: ^XDG_Toplevel) {
	proxy_marshal_flags(
		xdg_toplevel,
		9,
		nil,
		proxy_get_version(xdg_toplevel),
		0,
	)
}

xdg_toplevel_unset_maximized :: proc "c" (xdg_toplevel: ^XDG_Toplevel) {
	proxy_marshal_flags(
		xdg_toplevel,
		10,
		nil,
		proxy_get_version(xdg_toplevel),
		0,
	)
}

xdg_toplevel_set_fullscreen :: proc "c" (xdg_toplevel: ^XDG_Toplevel, output: ^Output) {
	proxy_marshal_flags(
		xdg_toplevel,
		11,
		nil,
		proxy_get_version(xdg_toplevel),
		0,
		output,
	)
}

xdg_toplevel_unset_fullscreen :: proc "c" (xdg_toplevel: ^XDG_Toplevel) {
	proxy_marshal_flags(
		xdg_toplevel,
		12,
		nil,
		proxy_get_version(xdg_toplevel),
		0,
	)
}

xdg_toplevel_set_minimized :: proc "c" (xdg_toplevel: ^XDG_Toplevel) {
	proxy_marshal_flags(
		xdg_toplevel,
		13,
		nil,
		proxy_get_version(xdg_toplevel),
		0,
	)
}

xdg_toplevel_interface := Interface {
	"xdg_toplevel",
	6,
	14,
	raw_data([]Message {
		{"destroy", "", raw_data([]^Interface{})},
		// nil should xdg_toplevel_interface, but that crashes compiler due to loop
		{"set_parent", "?o", raw_data([]^Interface{nil})},
		{"set_title", "s", raw_data([]^Interface{nil})},
		{"set_app_id", "s", raw_data([]^Interface{nil})},
		{"show_window_menu", "ouii", raw_data([]^Interface{&seat_interface, nil, nil, nil})},
		{"move", "ou", raw_data([]^Interface{&seat_interface, nil})},
		{"resize", "ouu", raw_data([]^Interface{&seat_interface, nil, nil})},
		{"set_max_size", "ii", raw_data([]^Interface{nil, nil})},
		{"set_min_size", "ii", raw_data([]^Interface{nil, nil})},
		{"set_maximized", "", raw_data([]^Interface{})},
		{"unset_maximized", "", raw_data([]^Interface{})},
		{"set_fullscreen", "?o", raw_data([]^Interface{&output_interface})},
		{"unset_fullscreen", "", raw_data([]^Interface{})},
		{"set_minimized", "", raw_data([]^Interface{})},
	}),
	4,
	raw_data([]Message {
		{"configure", "iia", raw_data([]^Interface{nil, nil, nil})},
		{"close", "", raw_data([]^Interface{})},
		{"configure_bounds", "ii", raw_data([]^Interface{nil, nil})},
		{"wm_capabilities", "a", raw_data([]^Interface{nil})},
	}),
}

XDG_TOPLEVEL_ERROR_INVALID_PARENT :: 1
XDG_TOPLEVEL_ERROR_INVALID_SIZE :: 2
XDG_TOPLEVEL_ERROR_INVALID_RESIZE_EDGE :: 0
XDG_TOPLEVEL_RESIZE_EDGE_LEFT :: 4
XDG_TOPLEVEL_RESIZE_EDGE_TOP :: 1
XDG_TOPLEVEL_RESIZE_EDGE_TOP_RIGHT :: 9
XDG_TOPLEVEL_RESIZE_EDGE_BOTTOM :: 2
XDG_TOPLEVEL_RESIZE_EDGE_BOTTOM_RIGHT :: 10
XDG_TOPLEVEL_RESIZE_EDGE_BOTTOM_LEFT :: 6
XDG_TOPLEVEL_RESIZE_EDGE_NONE :: 0
XDG_TOPLEVEL_RESIZE_EDGE_TOP_LEFT :: 5
XDG_TOPLEVEL_RESIZE_EDGE_RIGHT :: 8
XDG_TOPLEVEL_STATE_MAXIMIZED :: 1
XDG_TOPLEVEL_STATE_RESIZING :: 3
XDG_TOPLEVEL_STATE_SUSPENDED :: 9
XDG_TOPLEVEL_STATE_TILED_TOP :: 7
XDG_TOPLEVEL_STATE_FULLSCREEN :: 2
XDG_TOPLEVEL_STATE_TILED_LEFT :: 5
XDG_TOPLEVEL_STATE_TILED_RIGHT :: 6
XDG_TOPLEVEL_STATE_TILED_BOTTOM :: 8
XDG_TOPLEVEL_STATE_ACTIVATED :: 4
XDG_TOPLEVEL_WM_CAPABILITIES_MINIMIZE :: 4
XDG_TOPLEVEL_WM_CAPABILITIES_FULLSCREEN :: 3
XDG_TOPLEVEL_WM_CAPABILITIES_MAXIMIZE :: 2
XDG_TOPLEVEL_WM_CAPABILITIES_WINDOW_MENU :: 1
