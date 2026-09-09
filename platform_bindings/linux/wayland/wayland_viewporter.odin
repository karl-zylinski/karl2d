package wayland

WP_Viewporter :: struct {
	using proxy: Proxy,
}

wp_viewporter_interface := Interface {
	"wp_viewporter",
	1,
	2,
	raw_data([]Message {
		{ "destroy", "", raw_data([]^Interface { }) },
		{
			"get_viewport",
			"no",
			raw_data([]^Interface { &wp_viewport_interface, &surface_interface }),
		},
	}),
	0,
	nil,
}

WP_VIEWPORTER_DESTROY :: 0
WP_VIEWPORTER_GET_VIEWPORT :: 1

WP_VIEWPORTER_ERROR_VIEWPORT_EXISTS :: 0

wp_viewporter_get_viewport :: proc(
	wp_viewporter: ^WP_Viewporter,
	surface: ^Surface,
) -> ^WP_Viewport {
	return (^WP_Viewport)(proxy_marshal_flags(
		wp_viewporter,
		WP_VIEWPORTER_GET_VIEWPORT,
		&wp_viewport_interface,
		proxy_get_version(wp_viewporter),
		0,
		nil,
		surface,
	))
}

WP_Viewport :: struct {
	using proxy: Proxy,
}

wp_viewport_interface := Interface {
	"wp_viewport",
	1,
	3,
	raw_data([]Message {
		{ "destroy", "", raw_data([]^Interface { }) },
		{ "set_source", "ffff", raw_data([]^Interface { nil, nil, nil, nil })},
		{ "set_destination", "ii", raw_data([]^Interface { nil, nil }) },
	}),
	0,
	nil,
}

WP_VIEWPORT_DESTROY :: 0
WP_VIEWPORT_SET_SOURCE :: 1
WP_VIEWPORT_SET_DESTINATION :: 2

WP_VIEWPORT_ERROR_BAD_VALUE :: 0
WP_VIEWPORT_ERROR_BAD_SIZE :: 1
WP_VIEWPORT_ERROR_OUT_OF_BUFFER :: 2
WP_VIEWPORT_ERROR_NO_SURFACE :: 3

wp_viewport_destroy :: proc (wp_viewport: ^WP_Viewport) {
	proxy_marshal_flags(
		wp_viewport,
		WP_VIEWPORT_DESTROY,
		nil,
		proxy_get_version(wp_viewport),
		MARSHAL_FLAG_DESTROY,
	)
}

wp_viewport_set_source :: proc (
	wp_viewport: ^WP_Viewport,
	x, y, width, height: Fixed,
) {
	proxy_marshal_flags(
		wp_viewport,
		WP_VIEWPORT_SET_SOURCE,
		nil,
		proxy_get_version(wp_viewport),
		0,
		x,
		y,
		width,
		height,
	)
}

wp_viewport_set_destination :: proc (
	wp_viewport: ^WP_Viewport,
	width: i32,
	height: i32,
) {
	proxy_marshal_flags(
		wp_viewport,
		WP_VIEWPORT_SET_DESTINATION,
		nil,
		proxy_get_version(wp_viewport),
		0,
		width,
		height,
	)
}
