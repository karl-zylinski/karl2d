package wayland

ZWP_Relative_Pointer_Manager_V1 :: struct {
	using proxy: Proxy,
}

ZWP_Relative_Pointer_V1 :: struct {
	using proxy: Proxy,
}

ZWP_Relative_Pointer_V1_Listener :: struct {
	relative_motion: proc "c" (
		data: rawptr,
		relative_pointer: ^ZWP_Relative_Pointer_V1,
		utime_hi: u32,
		utime_lo: u32,
		dx: Fixed,
		dy: Fixed,
		dx_unaccel: Fixed,
		dy_unaccel: Fixed,
	),
}

zwp_relative_pointer_manager_v1_interface := Interface {
	"zwp_relative_pointer_manager_v1",
	1,
	2,
	raw_data([]Message {
		{"destroy", "", raw_data([]^Interface{})},
		{"get_relative_pointer", "no", raw_data([]^Interface {
			&zwp_relative_pointer_v1_interface,
			&pointer_interface,
		})},
	}),
	0,
	nil,
}

zwp_relative_pointer_v1_interface := Interface {
	"zwp_relative_pointer_v1",
	1,
	1,
	raw_data([]Message {
		{"destroy", "", raw_data([]^Interface{})},
	}),
	1,
	raw_data([]Message {
		{"relative_motion", "uuffff", raw_data([]^Interface {
			nil,
			nil,
			nil,
			nil,
			nil,
			nil,
		})},
	}),
}

zwp_relative_pointer_manager_v1_destroy :: proc(self: ^ZWP_Relative_Pointer_Manager_V1) {
	proxy_marshal_flags(
		self,
		0,
		nil,
		proxy_get_version(self),
		MARSHAL_FLAG_DESTROY,
	)
}

zwp_relative_pointer_manager_v1_get_relative_pointer :: proc(
	self: ^ZWP_Relative_Pointer_Manager_V1,
	pointer: ^Pointer,
) -> ^ZWP_Relative_Pointer_V1 {
	return (^ZWP_Relative_Pointer_V1)(proxy_marshal_flags(
		self,
		1,
		&zwp_relative_pointer_v1_interface,
		proxy_get_version(self),
		0,
		nil,
		pointer,
	))
}
