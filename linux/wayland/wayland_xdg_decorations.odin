package wayland

import "core:c"

zxdg_decoration_manager_v1 :: struct {}
zxdg_decoration_manager_v1_listener :: struct {}

zxdg_decoration_manager_v1_add_listener :: proc(
	zxdg_decoration_manager_v1: ^zxdg_decoration_manager_v1,
	listener: ^zxdg_decoration_manager_v1_listener,
	data: rawptr,
) -> c.int {

	return proxy_add_listener(
		cast(^Proxy)zxdg_decoration_manager_v1,
		cast(^Implementation)listener,
		data,
	)
}

zxdg_decoration_manager_v1_destroy :: proc "c" (
	_zxdg_decoration_manager_v1: ^zxdg_decoration_manager_v1,
) {
	proxy_marshal_flags(
		cast(^Proxy)_zxdg_decoration_manager_v1,
		0,
		nil,
		proxy_get_version(cast(^Proxy)_zxdg_decoration_manager_v1),
		WL_MARSHAL_FLAG_DESTROY,
	)

}

zxdg_decoration_manager_v1_get_toplevel_decoration :: proc "c" (
	_zxdg_decoration_manager_v1: ^zxdg_decoration_manager_v1,
	toplevel: ^xdg_toplevel,
) -> ^zxdg_toplevel_decoration_v1 {
	id: ^Proxy
	id = proxy_marshal_flags(
		cast(^Proxy)_zxdg_decoration_manager_v1,
		1,
		&zxdg_toplevel_decoration_v1_interface,
		proxy_get_version(cast(^Proxy)_zxdg_decoration_manager_v1),
		0,
		nil,
		toplevel,
	)


	return cast(^zxdg_toplevel_decoration_v1)id
}

zxdg_decoration_manager_v1_requests: []wl_message = []wl_message {
	{"destroy", "", raw_data([]^wl_interface{})},
	{
		"get_toplevel_decoration",
		"no",
		raw_data([]^wl_interface{&zxdg_toplevel_decoration_v1_interface, &xdg_toplevel_interface}),
	},
}

zxdg_decoration_manager_v1_events: []wl_message = []wl_message{}

zxdg_decoration_manager_v1_interface: wl_interface = {}
@(init)
init_zxdg_decoration_manager_v1_interface :: proc "contextless" () {
	zxdg_decoration_manager_v1_interface = {
		"zxdg_decoration_manager_v1",
		1,
		2,
		&zxdg_decoration_manager_v1_requests[0],
		0,
		nil,
	}
}


zxdg_toplevel_decoration_v1 :: struct {}
zxdg_toplevel_decoration_v1_listener :: struct {
	configure: proc "c" (
		data: rawptr,
		zxdg_toplevel_decoration_v1: ^zxdg_toplevel_decoration_v1,
		mode: c.uint32_t,
	),
}

zxdg_toplevel_decoration_v1_add_listener :: proc(
	zxdg_toplevel_decoration_v1: ^zxdg_toplevel_decoration_v1,
	listener: ^zxdg_toplevel_decoration_v1_listener,
	data: rawptr,
) -> c.int {

	return proxy_add_listener(
		cast(^Proxy)zxdg_toplevel_decoration_v1,
		cast(^Implementation)listener,
		data,
	)
}

zxdg_toplevel_decoration_v1_destroy :: proc "c" (
	_zxdg_toplevel_decoration_v1: ^zxdg_toplevel_decoration_v1,
) {
	proxy_marshal_flags(
		cast(^Proxy)_zxdg_toplevel_decoration_v1,
		0,
		nil,
		proxy_get_version(cast(^Proxy)_zxdg_toplevel_decoration_v1),
		WL_MARSHAL_FLAG_DESTROY,
	)

}

zxdg_toplevel_decoration_v1_set_mode :: proc "c" (
	_zxdg_toplevel_decoration_v1: ^zxdg_toplevel_decoration_v1,
	mode: c.uint32_t,
) {
	proxy_marshal_flags(
		cast(^Proxy)_zxdg_toplevel_decoration_v1,
		1,
		nil,
		proxy_get_version(cast(^Proxy)_zxdg_toplevel_decoration_v1),
		0,
		mode,
	)

}

zxdg_toplevel_decoration_v1_unset_mode :: proc "c" (
	_zxdg_toplevel_decoration_v1: ^zxdg_toplevel_decoration_v1,
) {
	proxy_marshal_flags(
		cast(^Proxy)_zxdg_toplevel_decoration_v1,
		2,
		nil,
		proxy_get_version(cast(^Proxy)_zxdg_toplevel_decoration_v1),
		0,
	)

}

zxdg_toplevel_decoration_v1_requests: []wl_message = []wl_message {
	{"destroy", "", raw_data([]^wl_interface{})},
	{"set_mode", "u", raw_data([]^wl_interface{nil})},
	{"unset_mode", "", raw_data([]^wl_interface{})},
}

zxdg_toplevel_decoration_v1_events: []wl_message = []wl_message {
	{"configure", "u", raw_data([]^wl_interface{nil})},
}

zxdg_toplevel_decoration_v1_interface: wl_interface = {}
@(init)
init_zxdg_toplevel_decoration_v1_interface :: proc "contextless" () {
	zxdg_toplevel_decoration_v1_interface = {
		"zxdg_toplevel_decoration_v1",
		1,
		3,
		&zxdg_toplevel_decoration_v1_requests[0],
		1,
		&zxdg_toplevel_decoration_v1_events[0],
	}
}

ZXDG_TOPLEVEL_DECORATION_V1_ERROR_ALREADY_CONSTRUCTED :: 1
ZXDG_TOPLEVEL_DECORATION_V1_ERROR_UNCONFIGURED_BUFFER :: 0
ZXDG_TOPLEVEL_DECORATION_V1_ERROR_ORPHANED :: 2
ZXDG_TOPLEVEL_DECORATION_V1_ERROR_INVALID_MODE :: 3
ZXDG_TOPLEVEL_DECORATION_V1_MODE_CLIENT_SIDE :: 1
ZXDG_TOPLEVEL_DECORATION_V1_MODE_SERVER_SIDE :: 2
