package karl2d_wayland

KDE_Output_Order_V1 :: struct {
	using proxy: Proxy,
}

KDE_Output_Order_V1_Listener :: struct {
	output: proc "c" (data: rawptr, self: ^KDE_Output_Order_V1, output_name: cstring),
	done: proc "c" (data: rawptr, self: ^KDE_Output_Order_V1),
}

KDE_OUTPUT_ORDER_V1_DESTROY :: 0

kde_output_order_v1_destroy :: proc "c" (kde_output_order_v1: ^KDE_Output_Order_V1) {
	proxy_marshal_flags(
		kde_output_order_v1,
		KDE_OUTPUT_ORDER_V1_DESTROY,
		nil,
		proxy_get_version(kde_output_order_v1),
		MARSHAL_FLAG_DESTROY,
	)
}

kde_output_order_v1_interface := Interface {
	"kde_output_order_v1",
	1,
	1,
	raw_data([]Message{{"destroy", "", raw_data([]^Interface{})}}),
	2,
	raw_data([]Message {
		{"output", "s", raw_data([]^Interface{nil})},
		{"done", "", raw_data([]^Interface{})},
	}),
}
