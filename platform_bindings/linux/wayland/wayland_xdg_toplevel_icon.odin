package wayland

XDG_Toplevel_Icon_Manager_V1 :: struct {
	using proxy: Proxy,
}

xdg_toplevel_icon_manager_v1_destroy :: proc "c" (
	xdg_toplevel_icon_manager_v1: ^XDG_Toplevel_Icon_Manager_V1,
) {
	proxy_marshal_flags(
		xdg_toplevel_icon_manager_v1,
		0,
		nil,
		proxy_get_version(xdg_toplevel_icon_manager_v1),
		MARSHAL_FLAG_DESTROY,
	)
}

xdg_toplevel_icon_manager_v1_create_icon :: proc "c" (
	xdg_toplevel_icon_manager_v1: ^XDG_Toplevel_Icon_Manager_V1,
) -> ^XDG_Toplevel_Icon_V1 {
	return (^XDG_Toplevel_Icon_V1)(proxy_marshal_flags(
		xdg_toplevel_icon_manager_v1,
		1,
		&xdg_toplevel_icon_v1_interface,
		proxy_get_version(xdg_toplevel_icon_manager_v1),
		0,
		nil,
	))
}

// `icon` may be nil, which puts the toplevel back on the icon the compositor picked for it.
xdg_toplevel_icon_manager_v1_set_icon :: proc "c" (
	xdg_toplevel_icon_manager_v1: ^XDG_Toplevel_Icon_Manager_V1,
	toplevel: ^XDG_Toplevel,
	icon: ^XDG_Toplevel_Icon_V1,
) {
	proxy_marshal_flags(
		xdg_toplevel_icon_manager_v1,
		2,
		nil,
		proxy_get_version(xdg_toplevel_icon_manager_v1),
		0,
		toplevel,
		icon,
	)
}

xdg_toplevel_icon_manager_v1_interface := Interface {
	"xdg_toplevel_icon_manager_v1",
	1,
	3,
	raw_data([]Message {
		{"destroy", "", raw_data([]^Interface{})},
		{"create_icon", "n", raw_data([]^Interface{&xdg_toplevel_icon_v1_interface})},
		{
			"set_icon",
			"o?o",
			raw_data([]^Interface{&xdg_toplevel_interface, &xdg_toplevel_icon_v1_interface}),
		},
	}),
	2,
	raw_data([]Message {
		{"icon_size", "i", raw_data([]^Interface{nil})},
		{"done", "", raw_data([]^Interface{})},
	}),
}

XDG_Toplevel_Icon_V1 :: struct {
	using proxy: Proxy,
}

xdg_toplevel_icon_v1_destroy :: proc "c" (xdg_toplevel_icon_v1: ^XDG_Toplevel_Icon_V1) {
	proxy_marshal_flags(
		xdg_toplevel_icon_v1,
		0,
		nil,
		proxy_get_version(xdg_toplevel_icon_v1),
		MARSHAL_FLAG_DESTROY,
	)
}

xdg_toplevel_icon_v1_set_name :: proc "c" (
	xdg_toplevel_icon_v1: ^XDG_Toplevel_Icon_V1,
	icon_name: cstring,
) {
	proxy_marshal_flags(
		xdg_toplevel_icon_v1,
		1,
		nil,
		proxy_get_version(xdg_toplevel_icon_v1),
		0,
		icon_name,
	)
}

// `buffer` must be square and backed by shm, or the compositor raises an `invalid_buffer` error,
// which kills the connection. It must also stay alive for as long as the icon does.
xdg_toplevel_icon_v1_add_buffer :: proc "c" (
	xdg_toplevel_icon_v1: ^XDG_Toplevel_Icon_V1,
	buffer: ^Buffer,
	scale: i32,
) {
	proxy_marshal_flags(
		xdg_toplevel_icon_v1,
		2,
		nil,
		proxy_get_version(xdg_toplevel_icon_v1),
		0,
		buffer,
		scale,
	)
}

xdg_toplevel_icon_v1_interface := Interface {
	"xdg_toplevel_icon_v1",
	1,
	3,
	raw_data([]Message {
		{"destroy", "", raw_data([]^Interface{})},
		{"set_name", "s", raw_data([]^Interface{nil})},
		{"add_buffer", "oi", raw_data([]^Interface{&buffer_interface, nil})},
	}),
	0,
	nil,
}

XDG_TOPLEVEL_ICON_V1_ERROR_INVALID_BUFFER :: 1
XDG_TOPLEVEL_ICON_V1_ERROR_IMMUTABLE :: 2
XDG_TOPLEVEL_ICON_V1_ERROR_NO_BUFFER :: 3
