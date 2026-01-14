package wayland

import "core:c"

ZXDG_Decoration_Manager_V1 :: struct {
	using proxy: Proxy,
}

zxdg_decoration_manager_v1_get_toplevel_decoration :: proc "c" (
	zxdg_decoration_manager_v1: ^ZXDG_Decoration_Manager_V1,
	toplevel: ^XDG_Toplevel,
) -> ^ZXDG_Decoration_Manager_V1 {
	return cast(^ZXDG_Decoration_Manager_V1)(
		proxy_marshal_flags(
		zxdg_decoration_manager_v1,
		1,
		&zxdg_toplevel_decoration_v1_interface,
		proxy_get_version(zxdg_decoration_manager_v1),
		0,
		nil,
		toplevel,
	))
}

zxdg_decoration_manager_v1_interface := Interface {
	"zxdg_decoration_manager_v1",
	1,
	2,
	raw_data([]Message {
		{"destroy", "", raw_data([]^Interface{})},
		{
			"get_toplevel_decoration",
			"no",
			raw_data([]^Interface{&zxdg_toplevel_decoration_v1_interface, &xdg_toplevel_interface}),
		},
	}),
	0,
	nil,
}

ZXDG_Toplevel_Decoration_V1 :: struct {
	using proxy: Proxy,
}

zxdg_toplevel_decoration_v1_destroy :: proc "c" (
	zxdg_toplevel_decoration_v1: ^ZXDG_Decoration_Manager_V1,
) {
	proxy_marshal_flags(
		zxdg_toplevel_decoration_v1,
		0,
		nil,
		proxy_get_version(zxdg_toplevel_decoration_v1),
		MARSHAL_FLAG_DESTROY,
	)
}

zxdg_toplevel_decoration_v1_set_mode :: proc "c" (
	zxdg_toplevel_decoration_v1: ^ZXDG_Decoration_Manager_V1,
	mode: c.uint32_t,
) {
	proxy_marshal_flags(
		zxdg_toplevel_decoration_v1,
		1,
		nil,
		proxy_get_version(zxdg_toplevel_decoration_v1),
		0,
		mode,
	)
}

zxdg_toplevel_decoration_v1_unset_mode :: proc "c" (
	zxdg_toplevel_decoration_v1: ^ZXDG_Decoration_Manager_V1,
) {
	proxy_marshal_flags(
		zxdg_toplevel_decoration_v1,
		2,
		nil,
		proxy_get_version(zxdg_toplevel_decoration_v1),
		0,
	)
}

zxdg_toplevel_decoration_v1_interface := Interface {
	"zxdg_toplevel_decoration_v1",
	1,
	3,
	raw_data([]Message {
		{"destroy", "", raw_data([]^Interface{})},
		{"set_mode", "u", raw_data([]^Interface{nil})},
		{"unset_mode", "", raw_data([]^Interface{})},
	}),
	1,
	raw_data([]Message {
		{"configure", "u", raw_data([]^Interface{nil})},
	}),
}

ZXDG_TOPLEVEL_DECORATION_V1_ERROR_ALREADY_CONSTRUCTED :: 1
ZXDG_TOPLEVEL_DECORATION_V1_ERROR_UNCONFIGURED_BUFFER :: 0
ZXDG_TOPLEVEL_DECORATION_V1_ERROR_ORPHANED :: 2
ZXDG_TOPLEVEL_DECORATION_V1_ERROR_INVALID_MODE :: 3
ZXDG_TOPLEVEL_DECORATION_V1_MODE_CLIENT_SIDE :: 1
ZXDG_TOPLEVEL_DECORATION_V1_MODE_SERVER_SIDE :: 2
