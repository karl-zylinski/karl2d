package wayland

WP_Fractional_Scale_Manager_V1 :: struct {
	using proxy: Proxy,
}


wp_fractional_scale_manager_v1_interface := Interface {
	"wp_fractional_scale_manager_v1",
	1,
	2,
	raw_data([]Message {
		{"destroy", "", raw_data([]^Interface {nil})},
		{"get_fractional_scale", "no", raw_data([]^Interface {nil})},
	}),
	0,
	nil,
}

wp_fractional_scale_manager_get_fractional_scale :: proc(
	wp_fractional_scale_manager_v1: ^WP_Fractional_Scale_Manager_V1,
	surface: ^Surface,
) -> (
	^WP_Fractional_Scale_V1,
) {

	return (^WP_Fractional_Scale_V1)(
		proxy_marshal_flags(
			wp_fractional_scale_manager_v1,
			WP_FRACTIONAL_SCALE_MANAGER_V1_GET_FRACTIONAL_SCALE,
			&wp_fractional_scale_v1_interface,
			proxy_get_version(wp_fractional_scale_manager_v1),
			0,
			nil,
			surface,
		),
	)
}


WP_FRACTIONAL_SCALE_MANAGER_V1_DESTROY                    :: 0
WP_FRACTIONAL_SCALE_MANAGER_V1_GET_FRACTIONAL_SCALE       :: 1
WP_FRACTIONAL_SCALE_MANAGER_V1_DESTROY_SINCE              :: 1
WP_FRACTIONAL_SCALE_MANAGER_V1_GET_FRACTIONAL_SCALE_SINCE :: 1

WP_Fractional_Scale_V1 :: struct {
	using proxy: Proxy,
}

WP_Fractional_Scale_V1_Listener :: struct {
	preferred_scale: proc "c" (
		data: rawptr,
		self: ^WP_Fractional_Scale_V1,
		scale: u32,
	),
}

wp_fractional_scale_v1_interface := Interface {
	"wp_fractional_scale_v1",
	1,
	1,
	raw_data([]Message{{"destroy", "", nil}}),
	1, 
	raw_data([]Message{{"preferred_scale", "u", nil}}),
}
