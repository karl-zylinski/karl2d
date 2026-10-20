package karl2d_wayland

import "core:c"

ZXDG_Output_Manager_V1 :: struct {
	using proxy: Proxy,
}

zxdg_output_manager_v1_interface := Interface {
	"zxdg_output_manager_v1",
	3,
	2,
	raw_data([]Message {
		{"destroy", "", raw_data([]^Interface{})},
		{
			"get_xdg_output",
			"no",
			raw_data([]^Interface{&zxdg_output_v1_interface, &output_interface}),
		},
	}),
	0,
	nil,
}

ZXDG_OUTPUT_MANAGER_V1_DESTROY :: 0
ZXDG_OUTPUT_MANAGER_V1_GET_XDG_OUTPUT :: 1

zxdg_output_manager_v1_destroy :: proc "c" (zxdg_output_manager_v1: ^ZXDG_Output_Manager_V1) {
	proxy_marshal_flags(
		zxdg_output_manager_v1,
		ZXDG_OUTPUT_MANAGER_V1_DESTROY,
		nil,
		proxy_get_version(zxdg_output_manager_v1),
		MARSHAL_FLAG_DESTROY,
	)
}

zxdg_output_manager_v1_get_xdg_output :: proc "c" (
	zxdg_output_manager_v1: ^ZXDG_Output_Manager_V1,
	output: ^Output,
) -> ^ZXDG_Output_V1 {
	return (^ZXDG_Output_V1)(
		proxy_marshal_flags(
			zxdg_output_manager_v1,
			ZXDG_OUTPUT_MANAGER_V1_GET_XDG_OUTPUT,
			&zxdg_output_v1_interface,
			proxy_get_version(zxdg_output_manager_v1),
			0,
			nil,
			output,
		),
	)
}

ZXDG_Output_V1 :: struct {
	using proxy: Proxy,
}

ZXDG_Output_V1_Listener :: struct {
	logical_position: proc "c" (data: rawptr, self: ^ZXDG_Output_V1, x: c.int32_t, y: c.int32_t),
	logical_size: proc "c" (
		data: rawptr,
		self: ^ZXDG_Output_V1,
		width: c.int32_t,
		height: c.int32_t,
	),
	done: proc "c" (data: rawptr, self: ^ZXDG_Output_V1),
	name: proc "c" (data: rawptr, self: ^ZXDG_Output_V1, name: cstring),
	description: proc "c" (data: rawptr, self: ^ZXDG_Output_V1, description: cstring),
}

ZXDG_OUTPUT_V1_DESTROY :: 0

zxdg_output_v1_destroy :: proc "c" (zxdg_output_v1: ^ZXDG_Output_V1) {
	proxy_marshal_flags(
		zxdg_output_v1,
		ZXDG_OUTPUT_V1_DESTROY,
		nil,
		proxy_get_version(zxdg_output_v1),
		MARSHAL_FLAG_DESTROY,
	)
}

zxdg_output_v1_interface := Interface {
	"zxdg_output_v1",
	3,
	1,
	raw_data([]Message{{"destroy", "", raw_data([]^Interface{})}}),
	5,
	raw_data([]Message {
		{"logical_position", "ii", raw_data([]^Interface{nil, nil})},
		{"logical_size", "ii", raw_data([]^Interface{nil, nil})},
		{"done", "", raw_data([]^Interface{})},
		{"name", "2s", raw_data([]^Interface{nil})},
		{"description", "2s", raw_data([]^Interface{nil})},
	}),
}
