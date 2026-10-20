package karl2d_wayland

ZWP_Pointer_Constraints_V1 :: struct {
	using proxy: Proxy,
}

ZWP_Locked_Pointer_V1 :: struct {
	using proxy: Proxy,
}

ZWP_Pointer_Constraints_V1_Lifetime :: enum u32 {
	Oneshot    = 1,
	Persistent = 2,
}

ZWP_POINTER_CONSTRAINTS_V1_LIFETIME_PERSISTENT :: ZWP_Pointer_Constraints_V1_Lifetime.Persistent

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
	2,
	raw_data([]Message {
		{"destroy", "", raw_data([]^Interface{})},
		{"lock_pointer", "noo?ou", raw_data([]^Interface {
			&zwp_locked_pointer_v1_interface,
			&surface_interface,
			&pointer_interface,
			&region_interface,
			nil,
		})},
	}),
	0,
	nil,
}

ZWP_POINTER_CONSTRAINTS_V1_LOCK_POINTER :: 1

zwp_locked_pointer_v1_interface := Interface {
	"zwp_locked_pointer_v1",
	1,
	3,
	raw_data([]Message {
		{"destroy", "", raw_data([]^Interface{})},
		{"set_cursor_position_hint", "ff", raw_data([]^Interface {nil, nil})},
		{"set_region", "?o", raw_data([]^Interface {&region_interface})},
	}),
	2,
	raw_data([]Message {
		{"locked", "", raw_data([]^Interface{})},
		{"unlocked", "", raw_data([]^Interface{})},
	}),
}

ZWP_LOCKED_POINTER_V1_DESTROY :: 0

zwp_pointer_constraints_v1_lock_pointer :: proc(
	self: ^ZWP_Pointer_Constraints_V1,
	surface: ^Surface,
	pointer: ^Pointer,
	region: ^Region,
	lifetime: ZWP_Pointer_Constraints_V1_Lifetime,
) -> ^ZWP_Locked_Pointer_V1 {
	return (^ZWP_Locked_Pointer_V1)(proxy_marshal_flags(
		self,
		ZWP_POINTER_CONSTRAINTS_V1_LOCK_POINTER,
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
		ZWP_LOCKED_POINTER_V1_DESTROY,
		nil,
		proxy_get_version(self),
		MARSHAL_FLAG_DESTROY,
	)
}