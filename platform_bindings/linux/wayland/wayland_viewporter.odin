package wayland

WP_Viewporter :: struct {
	using proxy: Proxy,
}

wp_viewporter_interface := Interface {
	"wp_viewporter",
	1,
	2,
	raw_data([]Message {
		{ "destroy", "", raw_data([]^Interface { nil }) },
		{ "get_viewport", "no", raw_data([]^Interface { &wp_viewport_interface, &surface_interface })},	
	}),
	0,
	nil,
}

wp_viewporter_get_viewport :: proc(
	wp_viewporter: ^WP_Viewporter,
	surface: ^Surface,
) -> ^WP_Viewport {
	return (^WP_Viewport)(proxy_marshal_flags(
		wp_viewporter,
		1,
		&wp_viewporter_interface,
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

wp_viewport_set_source :: proc (
	wp_viewport: ^WP_Viewport,
	x, y, width, height: Fixed,
) {
	proxy_marshal_flags(
		wp_viewport,
		1,
		&wp_viewport_interface,
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
		2,
		&wp_viewport_interface,
		proxy_get_version(wp_viewport),
		0,
		width,
		height,
	)
}
