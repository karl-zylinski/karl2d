package wayland

ZWP_Pointer_Constraints_V1 :: struct {
	using proxy: Proxy,
}

ZWP_Locked_Pointer_V1 :: struct {
	using proxy: Proxy,
}

ZWP_Pointer_Constraints_V1_Lifetime :: enum u32 {
	ONESHOT,
	PERSISTENT,
}

ZWP_POINTER_CONSTRAINTS_V1_LIFETIME_ONESHOT    :: ZWP_Pointer_Constraints_V1_Lifetime.ONESHOT
ZWP_POINTER_CONSTRAINTS_V1_LIFETIME_PERSISTENT :: ZWP_Pointer_Constraints_V1_Lifetime.PERSISTENT

ZWP_Locked_Pointer_V1_Listener :: struct {
	locked: proc "c" (
		data: rawptr,
		locked_pointer: ^ZWP_Locked_Pointer_V1,
	),
	unlocked: proc "c" (
		data: rawptr,
		locked_pointer: ^ZWP_Locked_Pointer_V1,
	),
}

zwp_pointer_constraints_v1_interface := Interface {
	"zwp_pointer_constraints_v1",
	1,
	3,
	raw_data([]Message {
		{"destroy", "", raw_data([]^Interface{})},
		{"lock_pointer", "noo?ou", raw_data([]^Interface {
			&zwp_locked_pointer_v1_interface,
			&surface_interface,
			&pointer_interface,
			nil,
			nil,
			nil,
		})},
		{"confine_pointer", "noo?ou", raw_data([]^Interface {
			nil,
			&surface_interface,
			&pointer_interface,
			nil,
			nil,
			nil,
		})},
	}),
	0,
	nil,
}

zwp_locked_pointer_v1_interface := Interface {
	"zwp_locked_pointer_v1",
	1,
	3,
	raw_data([]Message {
		{"destroy", "", raw_data([]^Interface{})},
		{"set_cursor_position_hint", "ff", raw_data([]^Interface {nil, nil})},
		{"set_region", "?o", raw_data([]^Interface {nil})},
	}),
	2,
	raw_data([]Message {
		{"locked", "", raw_data([]^Interface{})},
		{"unlocked", "", raw_data([]^Interface{})},
	}),
}

zwp_pointer_constraints_v1_destroy :: proc(self: ^ZWP_Pointer_Constraints_V1) {
	proxy_marshal_flags(
		self,
		0,
		nil,
		proxy_get_version(self),
		MARSHAL_FLAG_DESTROY,
	)
}

zwp_pointer_constraints_v1_lock_pointer :: proc(
	self: ^ZWP_Pointer_Constraints_V1,
	surface: ^Surface,
	pointer: ^Pointer,
	region: ^Proxy,
	lifetime: ZWP_Pointer_Constraints_V1_Lifetime,
) -> ^ZWP_Locked_Pointer_V1 {
	return (^ZWP_Locked_Pointer_V1)(proxy_marshal_flags(
		self,
		1,
		&zwp_locked_pointer_v1_interface,
		proxy_get_version(self),
		0,
		nil,
		surface,
		pointer,
		region,
		u32(lifetime),
	))
}

zwp_locked_pointer_v1_destroy :: proc(self: ^ZWP_Locked_Pointer_V1) {
	proxy_marshal_flags(
		self,
		0,
		nil,
		proxy_get_version(self),
		MARSHAL_FLAG_DESTROY,
	)
}

zwp_locked_pointer_v1_set_cursor_position_hint :: proc(
	self: ^ZWP_Locked_Pointer_V1,
	surface_x: Fixed,
	surface_y: Fixed,
) {
	proxy_marshal_flags(
		self,
		1,
		nil,
		proxy_get_version(self),
		0,
		surface_x,
		surface_y,
	)
}

zwp_locked_pointer_v1_set_region :: proc(self: ^ZWP_Locked_Pointer_V1, region: ^Proxy) {
	proxy_marshal_flags(
		self,
		2,
		nil,
		proxy_get_version(self),
		0,
		region,
	)
}