package wayland

import "core:c"

add_listener :: proc(
	proxy: ^$Proxy_Type,
	listener: ^$Listener_Type,
	data: rawptr,
) -> c.int {
	return proxy_add_listener(cast(^Proxy)proxy, rawptr(listener), data)
}

display_get_registry :: proc "c" (display: ^Display) -> ^Registry {
	return (^Registry)(proxy_marshal_flags(
		display,
		1, // WL_DISPLAY_GET_REGISTRY
		&registry_interface,
		proxy_get_version(display),
		0,
		nil,
	))
}

Registry :: struct {
	using proxy: Proxy,
}

Registry_Listener :: struct {
	global: proc "c" (
		data: rawptr,
		wl_registry: ^Registry,
		name: u32,
		interface: cstring,
		version: u32,
	),
	global_remove: proc "c" (data: rawptr, wl_registry: ^Registry, name: u32),
}

registry_bind :: proc(
	$T: typeid,
	registry: ^Registry,
	name: u32,
	interface: ^Interface,
	version: u32,
) -> ^T {
	return (^T)(proxy_marshal_flags(
		registry,
		0,
		interface,
		version,
		0,
		name,
		interface.name,
		version,
		nil,
	))
}

destroy :: proc(proxy: ^Proxy) {
	proxy_destroy(proxy)
}

registry_interface := Interface {
	"wl_registry",
	1,
	1,
	raw_data([]Message {
		{ "bind", "usun", raw_data([]^Interface{nil, nil, nil, nil})},
	}),
	2,
	raw_data([]Message {
		{"global", "usu", raw_data([]^Interface{nil, nil, nil})},
		{"global_remove", "u", raw_data([]^Interface{nil})},
	}),
}

Callback :: struct {
	using proxy: Proxy,
}

Callback_Listener :: struct {
	done: proc "c" (data: rawptr, wl_callback: ^Callback, callback_data: u32),
}

callback_destroy :: proc "c" (wl_callback: ^Callback) {
	proxy_destroy(cast(^Proxy)wl_callback)
}

wl_callback_requests: []Message = []Message{}

wl_callback_events: []Message = []Message{{"done", "u", raw_data([]^Interface{nil})}}

wl_callback_interface: Interface = {}
@(init)
init_wl_callback_interface :: proc "contextless" () {
	wl_callback_interface = {"wl_callback", 1, 0, nil, 1, &wl_callback_events[0]}
}


Compositor :: struct {
	using proxy: Proxy,
}
Compositor_Listener :: struct {}

wl_compositor_add_listener :: proc(
	wl_compositor: ^Compositor,
	listener: ^Compositor_Listener,
	data: rawptr,
) -> c.int {

	return proxy_add_listener(cast(^Proxy)wl_compositor, cast(rawptr)listener, data)
}

compositor_create_surface :: proc "c" (_wl_compositor: ^Compositor) -> ^Surface {
	id: ^Proxy
	id = proxy_marshal_flags(
		_wl_compositor,
		0,
		&wl_surface_interface,
		proxy_get_version(_wl_compositor),
		0,
		nil,
	)


	return cast(^Surface)id
}

wl_compositor_create_region :: proc "c" (_wl_compositor: ^Compositor) -> ^wl_region {
	id: ^Proxy
	id = proxy_marshal_flags(
		cast(^Proxy)_wl_compositor,
		1,
		&wl_region_interface,
		proxy_get_version(cast(^Proxy)_wl_compositor),
		0,
		nil,
	)


	return cast(^wl_region)id
}

wl_compositor_destroy :: proc "c" (wl_compositor: ^Compositor) {
	proxy_destroy(cast(^Proxy)wl_compositor)
}

compositor_interface := Interface {
	"wl_compositor",
	6, 
	2,
	raw_data([]Message {
		{"create_surface", "n", raw_data([]^Interface{&wl_surface_interface})},
		{"create_region", "n", raw_data([]^Interface{&wl_region_interface})},
	}),
	0, 
	nil,
}


wl_shm_pool :: struct {}
wl_shm_pool_listener :: struct {}

wl_shm_pool_add_listener :: proc(
	wl_shm_pool: ^wl_shm_pool,
	listener: ^wl_shm_pool_listener,
	data: rawptr,
) -> c.int {

	return proxy_add_listener(cast(^Proxy)wl_shm_pool, cast(rawptr)listener, data)
}

wl_shm_pool_create_buffer :: proc "c" (
	_wl_shm_pool: ^wl_shm_pool,
	offset: c.int32_t,
	width: c.int32_t,
	height: c.int32_t,
	stride: c.int32_t,
	format: u32,
) -> ^wl_buffer {
	id: ^Proxy
	id = proxy_marshal_flags(
		cast(^Proxy)_wl_shm_pool,
		0,
		&wl_buffer_interface,
		proxy_get_version(cast(^Proxy)_wl_shm_pool),
		0,
		nil,
		offset,
		width,
		height,
		stride,
		format,
	)


	return cast(^wl_buffer)id
}

wl_shm_pool_destroy :: proc "c" (_wl_shm_pool: ^wl_shm_pool) {
	proxy_marshal_flags(
		cast(^Proxy)_wl_shm_pool,
		1,
		nil,
		proxy_get_version(cast(^Proxy)_wl_shm_pool),
		MARSHAL_FLAG_DESTROY,
	)

}

wl_shm_pool_resize :: proc "c" (_wl_shm_pool: ^wl_shm_pool, size: c.int32_t) {
	proxy_marshal_flags(
		cast(^Proxy)_wl_shm_pool,
		2,
		nil,
		proxy_get_version(cast(^Proxy)_wl_shm_pool),
		0,
		size,
	)

}

wl_shm_pool_requests: []Message = []Message {
	{
		"create_buffer",
		"niiiiu",
		raw_data([]^Interface{&wl_buffer_interface, nil, nil, nil, nil, nil}),
	},
	{"destroy", "", raw_data([]^Interface{})},
	{"resize", "i", raw_data([]^Interface{nil})},
}

wl_shm_pool_events: []Message = []Message{}

wl_shm_pool_interface: Interface = {}
@(init)
init_wl_shm_pool_interface :: proc "contextless" () {
	wl_shm_pool_interface = {"wl_shm_pool", 1, 3, &wl_shm_pool_requests[0], 0, nil}
}


wl_shm :: struct {}
wl_shm_listener :: struct {
	format: proc "c" (data: rawptr, wl_shm: ^wl_shm, format: u32),
}

wl_shm_add_listener :: proc(wl_shm: ^wl_shm, listener: ^wl_shm_listener, data: rawptr) -> c.int {

	return proxy_add_listener(cast(^Proxy)wl_shm, cast(rawptr)listener, data)
}

wl_shm_create_pool :: proc "c" (_wl_shm: ^wl_shm, fd: c.int32_t, size: c.int32_t) -> ^wl_shm_pool {
	id: ^Proxy
	id = proxy_marshal_flags(
		cast(^Proxy)_wl_shm,
		0,
		&wl_shm_pool_interface,
		proxy_get_version(cast(^Proxy)_wl_shm),
		0,
		nil,
		fd,
		size,
	)


	return cast(^wl_shm_pool)id
}


wl_shm_destroy :: proc "c" (wl_shm: ^wl_shm) {
	proxy_destroy(cast(^Proxy)wl_shm)
}

wl_shm_requests: []Message = []Message {
	{"create_pool", "nhi", raw_data([]^Interface{&wl_shm_pool_interface, nil, nil})},
}

wl_shm_events: []Message = []Message{{"format", "u", raw_data([]^Interface{nil})}}

wl_shm_interface: Interface = {}
@(init)
init_wl_shm_interface :: proc "contextless" () {
	wl_shm_interface = {"wl_shm", 1, 1, &wl_shm_requests[0], 1, &wl_shm_events[0]}
}

WL_SHM_ERROR_INVALID_FD :: 2
WL_SHM_ERROR_INVALID_FORMAT :: 0
WL_SHM_ERROR_INVALID_STRIDE :: 1
WL_SHM_FORMAT_NV21 :: 0x3132564e
WL_SHM_FORMAT_RGBA8888 :: 0x34324152
WL_SHM_FORMAT_BGRA8888 :: 0x34324142
WL_SHM_FORMAT_XRGB8888_A8 :: 0x38415258
WL_SHM_FORMAT_GR88 :: 0x38385247
WL_SHM_FORMAT_XBGR2101010 :: 0x30334258
WL_SHM_FORMAT_VUY888 :: 0x34325556
WL_SHM_FORMAT_XBGR16161616F :: 0x48344258
WL_SHM_FORMAT_UYVY :: 0x59565955
WL_SHM_FORMAT_RGBX4444 :: 0x32315852
WL_SHM_FORMAT_BGRX4444 :: 0x32315842
WL_SHM_FORMAT_YVU420 :: 0x32315659
WL_SHM_FORMAT_XBGR8888 :: 0x34324258
WL_SHM_FORMAT_YVYU :: 0x55595659
WL_SHM_FORMAT_YUV422 :: 0x36315559
WL_SHM_FORMAT_ARGB16161616F :: 0x48345241
WL_SHM_FORMAT_BGR233 :: 0x38524742
WL_SHM_FORMAT_NV16 :: 0x3631564e
WL_SHM_FORMAT_YUV444 :: 0x34325559
WL_SHM_FORMAT_Y210 :: 0x30313259
WL_SHM_FORMAT_RGBX1010102 :: 0x30335852
WL_SHM_FORMAT_BGRX1010102 :: 0x30335842
WL_SHM_FORMAT_Y416 :: 0x36313459
WL_SHM_FORMAT_VYUY :: 0x59555956
WL_SHM_FORMAT_XVYU12_16161616 :: 0x36335658
WL_SHM_FORMAT_ABGR1555 :: 0x35314241
WL_SHM_FORMAT_R8 :: 0x20203852
WL_SHM_FORMAT_Y0L0 :: 0x304c3059
WL_SHM_FORMAT_YUV420_10BIT :: 0x30315559
WL_SHM_FORMAT_X0L0 :: 0x304c3058
WL_SHM_FORMAT_YUV411 :: 0x31315559
WL_SHM_FORMAT_RGB332 :: 0x38424752
WL_SHM_FORMAT_YVU411 :: 0x31315659
WL_SHM_FORMAT_XBGR4444 :: 0x32314258
WL_SHM_FORMAT_NV12 :: 0x3231564e
WL_SHM_FORMAT_NV42 :: 0x3234564e
WL_SHM_FORMAT_P010 :: 0x30313050
WL_SHM_FORMAT_RG88 :: 0x38384752
WL_SHM_FORMAT_ABGR16161616 :: 0x38344241
WL_SHM_FORMAT_Y410 :: 0x30313459
WL_SHM_FORMAT_RG1616 :: 0x32334752
WL_SHM_FORMAT_YUV420_8BIT :: 0x38305559
WL_SHM_FORMAT_ARGB4444 :: 0x32315241
WL_SHM_FORMAT_XRGB16161616F :: 0x48345258
WL_SHM_FORMAT_XVYU16161616 :: 0x38345658
WL_SHM_FORMAT_XYUV8888 :: 0x56555958
WL_SHM_FORMAT_NV15 :: 0x3531564e
WL_SHM_FORMAT_XRGB8888 :: 1
WL_SHM_FORMAT_ABGR16161616F :: 0x48344241
WL_SHM_FORMAT_NV24 :: 0x3432564e
WL_SHM_FORMAT_XRGB16161616 :: 0x38345258
WL_SHM_FORMAT_ARGB16161616 :: 0x38345241
WL_SHM_FORMAT_RGBX8888 :: 0x34325852
WL_SHM_FORMAT_BGRX8888 :: 0x34325842
WL_SHM_FORMAT_XBGR1555 :: 0x35314258
WL_SHM_FORMAT_VUY101010 :: 0x30335556
WL_SHM_FORMAT_P016 :: 0x36313050
WL_SHM_FORMAT_Y212 :: 0x32313259
WL_SHM_FORMAT_RGB565_A8 :: 0x38413552
WL_SHM_FORMAT_BGR565_A8 :: 0x38413542
WL_SHM_FORMAT_ABGR8888 :: 0x34324241
WL_SHM_FORMAT_BGR888_A8 :: 0x38413842
WL_SHM_FORMAT_YUV410 :: 0x39565559
WL_SHM_FORMAT_RGB888_A8 :: 0x38413852
WL_SHM_FORMAT_YVU410 :: 0x39555659
WL_SHM_FORMAT_XBGR16161616 :: 0x38344258
WL_SHM_FORMAT_YVU444 :: 0x34325659
WL_SHM_FORMAT_NV61 :: 0x3136564e
WL_SHM_FORMAT_RGB565 :: 0x36314752
WL_SHM_FORMAT_BGR565 :: 0x36314742
WL_SHM_FORMAT_Y0L2 :: 0x324c3059
WL_SHM_FORMAT_ABGR2101010 :: 0x30334241
WL_SHM_FORMAT_YVU422 :: 0x36315659
WL_SHM_FORMAT_YUV420 :: 0x32315559
WL_SHM_FORMAT_XRGB4444 :: 0x32315258
WL_SHM_FORMAT_ARGB8888 :: 0
WL_SHM_FORMAT_R16 :: 0x20363152
WL_SHM_FORMAT_P012 :: 0x32313050
WL_SHM_FORMAT_Y216 :: 0x36313259
WL_SHM_FORMAT_ABGR4444 :: 0x32314241
WL_SHM_FORMAT_Q410 :: 0x30313451
WL_SHM_FORMAT_ARGB2101010 :: 0x30335241
WL_SHM_FORMAT_RGBA5551 :: 0x35314152
WL_SHM_FORMAT_BGRA5551 :: 0x35314142
WL_SHM_FORMAT_RGB888 :: 0x34324752
WL_SHM_FORMAT_BGR888 :: 0x34324742
WL_SHM_FORMAT_AXBXGXRX106106106106 :: 0x30314241
WL_SHM_FORMAT_AYUV :: 0x56555941
WL_SHM_FORMAT_XVYU2101010 :: 0x30335658
WL_SHM_FORMAT_YUYV :: 0x56595559
WL_SHM_FORMAT_GR1616 :: 0x32335247
WL_SHM_FORMAT_C8 :: 0x20203843
WL_SHM_FORMAT_XBGR8888_A8 :: 0x38414258
WL_SHM_FORMAT_X0L2 :: 0x324c3058
WL_SHM_FORMAT_RGBA1010102 :: 0x30334152
WL_SHM_FORMAT_BGRA1010102 :: 0x30334142
WL_SHM_FORMAT_XRGB2101010 :: 0x30335258
WL_SHM_FORMAT_XRGB1555 :: 0x35315258
WL_SHM_FORMAT_P210 :: 0x30313250
WL_SHM_FORMAT_ARGB1555 :: 0x35315241
WL_SHM_FORMAT_RGBX8888_A8 :: 0x38415852
WL_SHM_FORMAT_BGRX8888_A8 :: 0x38415842
WL_SHM_FORMAT_BGRA4444 :: 0x32314142
WL_SHM_FORMAT_RGBA4444 :: 0x32314152
WL_SHM_FORMAT_Q401 :: 0x31303451
WL_SHM_FORMAT_RGBX5551 :: 0x35315852
WL_SHM_FORMAT_BGRX5551 :: 0x35315842
WL_SHM_FORMAT_Y412 :: 0x32313459

wl_buffer :: struct {}
wl_buffer_listener :: struct {
	release: proc "c" (data: rawptr, wl_buffer: ^wl_buffer),
}

wl_buffer_add_listener :: proc(
	wl_buffer: ^wl_buffer,
	listener: ^wl_buffer_listener,
	data: rawptr,
) -> c.int {

	return proxy_add_listener(cast(^Proxy)wl_buffer, cast(rawptr)listener, data)
}

wl_buffer_destroy :: proc "c" (_wl_buffer: ^wl_buffer) {
	proxy_marshal_flags(
		cast(^Proxy)_wl_buffer,
		0,
		nil,
		proxy_get_version(cast(^Proxy)_wl_buffer),
		MARSHAL_FLAG_DESTROY,
	)

}

wl_buffer_requests: []Message = []Message{{"destroy", "", raw_data([]^Interface{})}}

wl_buffer_events: []Message = []Message{{"release", "", raw_data([]^Interface{})}}

wl_buffer_interface: Interface = {}
@(init)
init_wl_buffer_interface :: proc "contextless" () {
	wl_buffer_interface = {"wl_buffer", 1, 1, &wl_buffer_requests[0], 1, &wl_buffer_events[0]}
}


wl_data_offer :: struct {}
wl_data_offer_listener :: struct {
	offer:          proc "c" (data: rawptr, wl_data_offer: ^wl_data_offer, mime_type: cstring),
	source_actions: proc "c" (
		data: rawptr,
		wl_data_offer: ^wl_data_offer,
		source_actions: u32,
	),
	action:         proc "c" (data: rawptr, wl_data_offer: ^wl_data_offer, dnd_action: u32),
}

wl_data_offer_add_listener :: proc(
	wl_data_offer: ^wl_data_offer,
	listener: ^wl_data_offer_listener,
	data: rawptr,
) -> c.int {

	return proxy_add_listener(cast(^Proxy)wl_data_offer, cast(rawptr)listener, data)
}

wl_data_offer_accept :: proc "c" (
	_wl_data_offer: ^wl_data_offer,
	serial: u32,
	mime_type: cstring,
) {
	proxy_marshal_flags(
		cast(^Proxy)_wl_data_offer,
		0,
		nil,
		proxy_get_version(cast(^Proxy)_wl_data_offer),
		0,
		serial,
		mime_type,
	)

}

wl_data_offer_receive :: proc "c" (
	_wl_data_offer: ^wl_data_offer,
	mime_type: cstring,
	fd: c.int32_t,
) {
	proxy_marshal_flags(
		cast(^Proxy)_wl_data_offer,
		1,
		nil,
		proxy_get_version(cast(^Proxy)_wl_data_offer),
		0,
		mime_type,
		fd,
	)

}

wl_data_offer_destroy :: proc "c" (_wl_data_offer: ^wl_data_offer) {
	proxy_marshal_flags(
		cast(^Proxy)_wl_data_offer,
		2,
		nil,
		proxy_get_version(cast(^Proxy)_wl_data_offer),
		MARSHAL_FLAG_DESTROY,
	)

}

wl_data_offer_finish :: proc "c" (_wl_data_offer: ^wl_data_offer) {
	proxy_marshal_flags(
		cast(^Proxy)_wl_data_offer,
		3,
		nil,
		proxy_get_version(cast(^Proxy)_wl_data_offer),
		0,
	)

}

wl_data_offer_set_actions :: proc "c" (
	_wl_data_offer: ^wl_data_offer,
	dnd_actions: u32,
	preferred_action: u32,
) {
	proxy_marshal_flags(
		cast(^Proxy)_wl_data_offer,
		4,
		nil,
		proxy_get_version(cast(^Proxy)_wl_data_offer),
		0,
		dnd_actions,
		preferred_action,
	)

}

wl_data_offer_requests: []Message = []Message {
	{"accept", "u?s", raw_data([]^Interface{nil, nil})},
	{"receive", "sh", raw_data([]^Interface{nil, nil})},
	{"destroy", "", raw_data([]^Interface{})},
	{"finish", "", raw_data([]^Interface{})},
	{"set_actions", "uu", raw_data([]^Interface{nil, nil})},
}

wl_data_offer_events: []Message = []Message {
	{"offer", "s", raw_data([]^Interface{nil})},
	{"source_actions", "u", raw_data([]^Interface{nil})},
	{"action", "u", raw_data([]^Interface{nil})},
}

wl_data_offer_interface: Interface = {}
@(init)
init_wl_data_offer_interface :: proc "contextless" () {
	wl_data_offer_interface = {
		"wl_data_offer",
		3,
		5,
		&wl_data_offer_requests[0],
		3,
		&wl_data_offer_events[0],
	}
}

WL_DATA_OFFER_ERROR_INVALID_OFFER :: 3
WL_DATA_OFFER_ERROR_INVALID_FINISH :: 0
WL_DATA_OFFER_ERROR_INVALID_ACTION :: 2
WL_DATA_OFFER_ERROR_INVALID_ACTION_MASK :: 1

wl_data_source :: struct {}
wl_data_source_listener :: struct {
	target:             proc "c" (
		data: rawptr,
		wl_data_source: ^wl_data_source,
		mime_type: cstring,
	),
	send:               proc "c" (
		data: rawptr,
		wl_data_source: ^wl_data_source,
		mime_type: cstring,
		fd: c.int32_t,
	),
	cancelled:          proc "c" (data: rawptr, wl_data_source: ^wl_data_source),
	dnd_drop_performed: proc "c" (data: rawptr, wl_data_source: ^wl_data_source),
	dnd_finished:       proc "c" (data: rawptr, wl_data_source: ^wl_data_source),
	action:             proc "c" (
		data: rawptr,
		wl_data_source: ^wl_data_source,
		dnd_action: u32,
	),
}

wl_data_source_add_listener :: proc(
	wl_data_source: ^wl_data_source,
	listener: ^wl_data_source_listener,
	data: rawptr,
) -> c.int {

	return proxy_add_listener(cast(^Proxy)wl_data_source, cast(rawptr)listener, data)
}

wl_data_source_offer :: proc "c" (_wl_data_source: ^wl_data_source, mime_type: cstring) {
	proxy_marshal_flags(
		cast(^Proxy)_wl_data_source,
		0,
		nil,
		proxy_get_version(cast(^Proxy)_wl_data_source),
		0,
		mime_type,
	)

}

wl_data_source_destroy :: proc "c" (_wl_data_source: ^wl_data_source) {
	proxy_marshal_flags(
		cast(^Proxy)_wl_data_source,
		1,
		nil,
		proxy_get_version(cast(^Proxy)_wl_data_source),
		MARSHAL_FLAG_DESTROY,
	)

}

wl_data_source_set_actions :: proc "c" (
	_wl_data_source: ^wl_data_source,
	dnd_actions: u32,
) {
	proxy_marshal_flags(
		cast(^Proxy)_wl_data_source,
		2,
		nil,
		proxy_get_version(cast(^Proxy)_wl_data_source),
		0,
		dnd_actions,
	)

}

wl_data_source_requests: []Message = []Message {
	{"offer", "s", raw_data([]^Interface{nil})},
	{"destroy", "", raw_data([]^Interface{})},
	{"set_actions", "u", raw_data([]^Interface{nil})},
}

wl_data_source_events: []Message = []Message {
	{"target", "?s", raw_data([]^Interface{nil})},
	{"send", "sh", raw_data([]^Interface{nil, nil})},
	{"cancelled", "", raw_data([]^Interface{})},
	{"dnd_drop_performed", "", raw_data([]^Interface{})},
	{"dnd_finished", "", raw_data([]^Interface{})},
	{"action", "u", raw_data([]^Interface{nil})},
}

wl_data_source_interface: Interface = {}
@(init)
init_wl_data_source_interface :: proc "contextless" () {
	wl_data_source_interface = {
		"wl_data_source",
		3,
		3,
		&wl_data_source_requests[0],
		6,
		&wl_data_source_events[0],
	}
}

WL_DATA_SOURCE_ERROR_INVALID_ACTION_MASK :: 0
WL_DATA_SOURCE_ERROR_INVALID_SOURCE :: 1

wl_data_device :: struct {}
wl_data_device_listener :: struct {
	data_offer: proc "c" (data: rawptr, wl_data_device: ^wl_data_device, id: u32),
	enter:      proc "c" (
		data: rawptr,
		wl_data_device: ^wl_data_device,
		serial: u32,
		surface: ^Surface,
		x: Fixed,
		y: Fixed,
		id: ^wl_data_offer,
	),
	leave:      proc "c" (data: rawptr, wl_data_device: ^wl_data_device),
	motion:     proc "c" (
		data: rawptr,
		wl_data_device: ^wl_data_device,
		time: u32,
		x: Fixed,
		y: Fixed,
	),
	drop:       proc "c" (data: rawptr, wl_data_device: ^wl_data_device),
	selection:  proc "c" (data: rawptr, wl_data_device: ^wl_data_device, id: ^wl_data_offer),
}

wl_data_device_add_listener :: proc(
	wl_data_device: ^wl_data_device,
	listener: ^wl_data_device_listener,
	data: rawptr,
) -> c.int {

	return proxy_add_listener(cast(^Proxy)wl_data_device, cast(rawptr)listener, data)
}

wl_data_device_start_drag :: proc "c" (
	_wl_data_device: ^wl_data_device,
	source: ^wl_data_source,
	origin: ^Surface,
	icon: ^Surface,
	serial: u32,
) {
	proxy_marshal_flags(
		cast(^Proxy)_wl_data_device,
		0,
		nil,
		proxy_get_version(cast(^Proxy)_wl_data_device),
		0,
		source,
		origin,
		icon,
		serial,
	)

}

wl_data_device_set_selection :: proc "c" (
	_wl_data_device: ^wl_data_device,
	source: ^wl_data_source,
	serial: u32,
) {
	proxy_marshal_flags(
		cast(^Proxy)_wl_data_device,
		1,
		nil,
		proxy_get_version(cast(^Proxy)_wl_data_device),
		0,
		source,
		serial,
	)

}

wl_data_device_release :: proc "c" (_wl_data_device: ^wl_data_device) {
	proxy_marshal_flags(
		cast(^Proxy)_wl_data_device,
		2,
		nil,
		proxy_get_version(cast(^Proxy)_wl_data_device),
		MARSHAL_FLAG_DESTROY,
	)

}


wl_data_device_destroy :: proc "c" (wl_data_device: ^wl_data_device) {
	proxy_destroy(cast(^Proxy)wl_data_device)
}

wl_data_device_requests: []Message = []Message {
	{
		"start_drag",
		"?oo?ou",
		raw_data(
			[]^Interface {
				&wl_data_source_interface,
				&wl_surface_interface,
				&wl_surface_interface,
				nil,
			},
		),
	},
	{"set_selection", "?ou", raw_data([]^Interface{&wl_data_source_interface, nil})},
	{"release", "", raw_data([]^Interface{})},
}

wl_data_device_events: []Message = []Message {
	{"data_offer", "n", raw_data([]^Interface{&wl_data_offer_interface})},
	{
		"enter",
		"uoff?o",
		raw_data([]^Interface{nil, &wl_surface_interface, nil, nil, &wl_data_offer_interface}),
	},
	{"leave", "", raw_data([]^Interface{})},
	{"motion", "uff", raw_data([]^Interface{nil, nil, nil})},
	{"drop", "", raw_data([]^Interface{})},
	{"selection", "?o", raw_data([]^Interface{&wl_data_offer_interface})},
}

wl_data_device_interface: Interface = {}
@(init)
init_wl_data_device_interface :: proc "contextless" () {
	wl_data_device_interface = {
		"wl_data_device",
		3,
		3,
		&wl_data_device_requests[0],
		6,
		&wl_data_device_events[0],
	}
}

WL_DATA_DEVICE_ERROR_ROLE :: 0

wl_data_device_manager :: struct {}
wl_data_device_manager_listener :: struct {}

wl_data_device_manager_add_listener :: proc(
	wl_data_device_manager: ^wl_data_device_manager,
	listener: ^wl_data_device_manager_listener,
	data: rawptr,
) -> c.int {

	return proxy_add_listener(
		cast(^Proxy)wl_data_device_manager,
		cast(rawptr)listener,
		data,
	)
}

wl_data_device_manager_create_data_source :: proc "c" (
	_wl_data_device_manager: ^wl_data_device_manager,
) -> ^wl_data_source {
	id: ^Proxy
	id = proxy_marshal_flags(
		cast(^Proxy)_wl_data_device_manager,
		0,
		&wl_data_source_interface,
		proxy_get_version(cast(^Proxy)_wl_data_device_manager),
		0,
		nil,
	)


	return cast(^wl_data_source)id
}

wl_data_device_manager_get_data_device :: proc "c" (
	_wl_data_device_manager: ^wl_data_device_manager,
	seat: ^Seat,
) -> ^wl_data_device {
	id: ^Proxy
	id = proxy_marshal_flags(
		cast(^Proxy)_wl_data_device_manager,
		1,
		&wl_data_device_interface,
		proxy_get_version(cast(^Proxy)_wl_data_device_manager),
		0,
		nil,
		seat,
	)


	return cast(^wl_data_device)id
}


wl_data_device_manager_destroy :: proc "c" (wl_data_device_manager: ^wl_data_device_manager) {
	proxy_destroy(cast(^Proxy)wl_data_device_manager)
}

wl_data_device_manager_requests: []Message = []Message {
	{"create_data_source", "n", raw_data([]^Interface{&wl_data_source_interface})},
	{
		"get_data_device",
		"no",
		raw_data([]^Interface{&wl_data_device_interface, &seat_interface}),
	},
}

wl_data_device_manager_events: []Message = []Message{}

wl_data_device_manager_interface: Interface = {}
@(init)
init_wl_data_device_manager_interface :: proc "contextless" () {
	wl_data_device_manager_interface = {
		"wl_data_device_manager",
		3,
		2,
		&wl_data_device_manager_requests[0],
		0,
		nil,
	}
}

WL_DATA_DEVICE_MANAGER_DND_ACTION_ASK :: 4
WL_DATA_DEVICE_MANAGER_DND_ACTION_NONE :: 0
WL_DATA_DEVICE_MANAGER_DND_ACTION_COPY :: 1
WL_DATA_DEVICE_MANAGER_DND_ACTION_MOVE :: 2

wl_shell :: struct {}
wl_shell_listener :: struct {}

wl_shell_add_listener :: proc(
	wl_shell: ^wl_shell,
	listener: ^wl_shell_listener,
	data: rawptr,
) -> c.int {

	return proxy_add_listener(cast(^Proxy)wl_shell, cast(rawptr)listener, data)
}

wl_shell_get_shell_surface :: proc "c" (
	_wl_shell: ^wl_shell,
	surface: ^Surface,
) -> ^wl_shell_surface {
	id: ^Proxy
	id = proxy_marshal_flags(
		cast(^Proxy)_wl_shell,
		0,
		&wl_shell_surface_interface,
		proxy_get_version(cast(^Proxy)_wl_shell),
		0,
		nil,
		surface,
	)


	return cast(^wl_shell_surface)id
}


wl_shell_destroy :: proc "c" (wl_shell: ^wl_shell) {
	proxy_destroy(cast(^Proxy)wl_shell)
}

wl_shell_requests: []Message = []Message {
	{
		"get_shell_surface",
		"no",
		raw_data([]^Interface{&wl_shell_surface_interface, &wl_surface_interface}),
	},
}

wl_shell_events: []Message = []Message{}

wl_shell_interface: Interface = {}
@(init)
init_wl_shell_interface :: proc "contextless" () {
	wl_shell_interface = {"wl_shell", 1, 1, &wl_shell_requests[0], 0, nil}
}

WL_SHELL_ERROR_ROLE :: 0

wl_shell_surface :: struct {}
wl_shell_surface_listener :: struct {
	ping:       proc "c" (data: rawptr, wl_shell_surface: ^wl_shell_surface, serial: u32),
	configure:  proc "c" (
		data: rawptr,
		wl_shell_surface: ^wl_shell_surface,
		edges: u32,
		width: c.int32_t,
		height: c.int32_t,
	),
	popup_done: proc "c" (data: rawptr, wl_shell_surface: ^wl_shell_surface),
}

wl_shell_surface_add_listener :: proc(
	wl_shell_surface: ^wl_shell_surface,
	listener: ^wl_shell_surface_listener,
	data: rawptr,
) -> c.int {

	return proxy_add_listener(cast(^Proxy)wl_shell_surface, cast(rawptr)listener, data)
}

wl_shell_surface_pong :: proc "c" (_wl_shell_surface: ^wl_shell_surface, serial: u32) {
	proxy_marshal_flags(
		cast(^Proxy)_wl_shell_surface,
		0,
		nil,
		proxy_get_version(cast(^Proxy)_wl_shell_surface),
		0,
		serial,
	)

}

wl_shell_surface_move :: proc "c" (
	_wl_shell_surface: ^wl_shell_surface,
	seat: ^Seat,
	serial: u32,
) {
	proxy_marshal_flags(
		cast(^Proxy)_wl_shell_surface,
		1,
		nil,
		proxy_get_version(cast(^Proxy)_wl_shell_surface),
		0,
		seat,
		serial,
	)

}

wl_shell_surface_resize :: proc "c" (
	_wl_shell_surface: ^wl_shell_surface,
	seat: ^Seat,
	serial: u32,
	edges: u32,
) {
	proxy_marshal_flags(
		cast(^Proxy)_wl_shell_surface,
		2,
		nil,
		proxy_get_version(cast(^Proxy)_wl_shell_surface),
		0,
		seat,
		serial,
		edges,
	)

}

wl_shell_surface_set_toplevel :: proc "c" (_wl_shell_surface: ^wl_shell_surface) {
	proxy_marshal_flags(
		cast(^Proxy)_wl_shell_surface,
		3,
		nil,
		proxy_get_version(cast(^Proxy)_wl_shell_surface),
		0,
	)

}

wl_shell_surface_set_transient :: proc "c" (
	_wl_shell_surface: ^wl_shell_surface,
	parent: ^Surface,
	x: c.int32_t,
	y: c.int32_t,
	flags: u32,
) {
	proxy_marshal_flags(
		cast(^Proxy)_wl_shell_surface,
		4,
		nil,
		proxy_get_version(cast(^Proxy)_wl_shell_surface),
		0,
		parent,
		x,
		y,
		flags,
	)

}

wl_shell_surface_set_fullscreen :: proc "c" (
	_wl_shell_surface: ^wl_shell_surface,
	method: u32,
	framerate: u32,
	output: ^wl_output,
) {
	proxy_marshal_flags(
		cast(^Proxy)_wl_shell_surface,
		5,
		nil,
		proxy_get_version(cast(^Proxy)_wl_shell_surface),
		0,
		method,
		framerate,
		output,
	)

}

wl_shell_surface_set_popup :: proc "c" (
	_wl_shell_surface: ^wl_shell_surface,
	seat: ^Seat,
	serial: u32,
	parent: ^Surface,
	x: c.int32_t,
	y: c.int32_t,
	flags: u32,
) {
	proxy_marshal_flags(
		cast(^Proxy)_wl_shell_surface,
		6,
		nil,
		proxy_get_version(cast(^Proxy)_wl_shell_surface),
		0,
		seat,
		serial,
		parent,
		x,
		y,
		flags,
	)

}

wl_shell_surface_set_maximized :: proc "c" (
	_wl_shell_surface: ^wl_shell_surface,
	output: ^wl_output,
) {
	proxy_marshal_flags(
		cast(^Proxy)_wl_shell_surface,
		7,
		nil,
		proxy_get_version(cast(^Proxy)_wl_shell_surface),
		0,
		output,
	)

}

wl_shell_surface_set_title :: proc "c" (_wl_shell_surface: ^wl_shell_surface, title: cstring) {
	proxy_marshal_flags(
		cast(^Proxy)_wl_shell_surface,
		8,
		nil,
		proxy_get_version(cast(^Proxy)_wl_shell_surface),
		0,
		title,
	)

}

wl_shell_surface_set_class :: proc "c" (_wl_shell_surface: ^wl_shell_surface, class_: cstring) {
	proxy_marshal_flags(
		cast(^Proxy)_wl_shell_surface,
		9,
		nil,
		proxy_get_version(cast(^Proxy)_wl_shell_surface),
		0,
		class_,
	)

}


wl_shell_surface_destroy :: proc "c" (wl_shell_surface: ^wl_shell_surface) {
	proxy_destroy(cast(^Proxy)wl_shell_surface)
}

wl_shell_surface_requests: []Message = []Message {
	{"pong", "u", raw_data([]^Interface{nil})},
	{"move", "ou", raw_data([]^Interface{&seat_interface, nil})},
	{"resize", "ouu", raw_data([]^Interface{&seat_interface, nil, nil})},
	{"set_toplevel", "", raw_data([]^Interface{})},
	{"set_transient", "oiiu", raw_data([]^Interface{&wl_surface_interface, nil, nil, nil})},
	{"set_fullscreen", "uu?o", raw_data([]^Interface{nil, nil, &wl_output_interface})},
	{
		"set_popup",
		"ouoiiu",
		raw_data([]^Interface{&seat_interface, nil, &wl_surface_interface, nil, nil, nil}),
	},
	{"set_maximized", "?o", raw_data([]^Interface{&wl_output_interface})},
	{"set_title", "s", raw_data([]^Interface{nil})},
	{"set_class", "s", raw_data([]^Interface{nil})},
}

wl_shell_surface_events: []Message = []Message {
	{"ping", "u", raw_data([]^Interface{nil})},
	{"configure", "uii", raw_data([]^Interface{nil, nil, nil})},
	{"popup_done", "", raw_data([]^Interface{})},
}

wl_shell_surface_interface: Interface = {}
@(init)
init_wl_shell_surface_interface :: proc "contextless" () {
	wl_shell_surface_interface = {
		"wl_shell_surface",
		1,
		10,
		&wl_shell_surface_requests[0],
		3,
		&wl_shell_surface_events[0],
	}
}

WL_SHELL_SURFACE_RESIZE_TOP_LEFT :: 5
WL_SHELL_SURFACE_RESIZE_TOP_RIGHT :: 9
WL_SHELL_SURFACE_RESIZE_RIGHT :: 8
WL_SHELL_SURFACE_RESIZE_BOTTOM :: 2
WL_SHELL_SURFACE_RESIZE_BOTTOM_LEFT :: 6
WL_SHELL_SURFACE_RESIZE_BOTTOM_RIGHT :: 10
WL_SHELL_SURFACE_RESIZE_LEFT :: 4
WL_SHELL_SURFACE_RESIZE_NONE :: 0
WL_SHELL_SURFACE_RESIZE_TOP :: 1
WL_SHELL_SURFACE_TRANSIENT_INACTIVE :: 0x1
WL_SHELL_SURFACE_FULLSCREEN_METHOD_DRIVER :: 2
WL_SHELL_SURFACE_FULLSCREEN_METHOD_DEFAULT :: 0
WL_SHELL_SURFACE_FULLSCREEN_METHOD_FILL :: 3
WL_SHELL_SURFACE_FULLSCREEN_METHOD_SCALE :: 1

Surface :: struct {
	using proxy: Proxy,
}

Surface_Listener :: struct {
	enter:                      proc "c" (
		data: rawptr,
		wl_surface: ^Surface,
		output: ^wl_output,
	),
	leave:                      proc "c" (
		data: rawptr,
		wl_surface: ^Surface,
		output: ^wl_output,
	),
	preferred_buffer_scale:     proc "c" (
		data: rawptr,
		wl_surface: ^Surface,
		factor: c.int32_t,
	),
	preferred_buffer_transform: proc "c" (
		data: rawptr,
		wl_surface: ^Surface,
		transform: u32,
	),
}

wl_surface_add_listener :: proc(
	wl_surface: ^Surface,
	listener: ^Surface_Listener,
	data: rawptr,
) -> c.int {

	return proxy_add_listener(cast(^Proxy)wl_surface, cast(rawptr)listener, data)
}

wl_surface_destroy :: proc "c" (_wl_surface: ^Surface) {
	proxy_marshal_flags(
		cast(^Proxy)_wl_surface,
		0,
		nil,
		proxy_get_version(cast(^Proxy)_wl_surface),
		MARSHAL_FLAG_DESTROY,
	)

}

wl_surface_attach :: proc "c" (
	_wl_surface: ^Surface,
	buffer: ^wl_buffer,
	x: c.int32_t,
	y: c.int32_t,
) {
	proxy_marshal_flags(
		cast(^Proxy)_wl_surface,
		1,
		nil,
		proxy_get_version(cast(^Proxy)_wl_surface),
		0,
		buffer,
		x,
		y,
	)

}

surface_damage :: proc "c" (
	_wl_surface: ^Surface,
	x: c.int32_t,
	y: c.int32_t,
	width: c.int32_t,
	height: c.int32_t,
) {
	proxy_marshal_flags(
		cast(^Proxy)_wl_surface,
		2,
		nil,
		proxy_get_version(cast(^Proxy)_wl_surface),
		0,
		x,
		y,
		width,
		height,
	)

}

surface_frame :: proc "c" (_wl_surface: ^Surface) -> ^Callback {
	callback: ^Proxy
	callback = proxy_marshal_flags(
		cast(^Proxy)_wl_surface,
		3,
		&wl_callback_interface,
		proxy_get_version(cast(^Proxy)_wl_surface),
		0,
		nil,
	)

	return cast(^Callback)callback
}

wl_surface_set_opaque_region :: proc "c" (_wl_surface: ^Surface, region: ^wl_region) {
	proxy_marshal_flags(
		cast(^Proxy)_wl_surface,
		4,
		nil,
		proxy_get_version(cast(^Proxy)_wl_surface),
		0,
		region,
	)

}

wl_surface_set_input_region :: proc "c" (_wl_surface: ^Surface, region: ^wl_region) {
	proxy_marshal_flags(
		cast(^Proxy)_wl_surface,
		5,
		nil,
		proxy_get_version(cast(^Proxy)_wl_surface),
		0,
		region,
	)

}

surface_commit :: proc "c" (_wl_surface: ^Surface) {
	proxy_marshal_flags(
		cast(^Proxy)_wl_surface,
		6,
		nil,
		proxy_get_version(cast(^Proxy)_wl_surface),
		0,
	)

}

wl_surface_set_buffer_transform :: proc "c" (_wl_surface: ^Surface, transform: u32) {
	proxy_marshal_flags(
		cast(^Proxy)_wl_surface,
		7,
		nil,
		proxy_get_version(cast(^Proxy)_wl_surface),
		0,
		transform,
	)

}

wl_surface_set_buffer_scale :: proc "c" (_wl_surface: ^Surface, scale: c.int32_t) {
	proxy_marshal_flags(
		cast(^Proxy)_wl_surface,
		8,
		nil,
		proxy_get_version(cast(^Proxy)_wl_surface),
		0,
		scale,
	)

}

wl_surface_damage_buffer :: proc "c" (
	_wl_surface: ^Surface,
	x: c.int32_t,
	y: c.int32_t,
	width: c.int32_t,
	height: c.int32_t,
) {
	proxy_marshal_flags(
		cast(^Proxy)_wl_surface,
		9,
		nil,
		proxy_get_version(cast(^Proxy)_wl_surface),
		0,
		x,
		y,
		width,
		height,
	)

}

wl_surface_offset :: proc "c" (_wl_surface: ^Surface, x: c.int32_t, y: c.int32_t) {
	proxy_marshal_flags(
		cast(^Proxy)_wl_surface,
		10,
		nil,
		proxy_get_version(cast(^Proxy)_wl_surface),
		0,
		x,
		y,
	)

}

wl_surface_requests: []Message = []Message {
	{"destroy", "", raw_data([]^Interface{})},
	{"attach", "?oii", raw_data([]^Interface{&wl_buffer_interface, nil, nil})},
	{"damage", "iiii", raw_data([]^Interface{nil, nil, nil, nil})},
	{"frame", "n", raw_data([]^Interface{&wl_callback_interface})},
	{"set_opaque_region", "?o", raw_data([]^Interface{&wl_region_interface})},
	{"set_input_region", "?o", raw_data([]^Interface{&wl_region_interface})},
	{"commit", "", raw_data([]^Interface{})},
	{"set_buffer_transform", "i", raw_data([]^Interface{nil})},
	{"set_buffer_scale", "i", raw_data([]^Interface{nil})},
	{"damage_buffer", "iiii", raw_data([]^Interface{nil, nil, nil, nil})},
	{"offset", "ii", raw_data([]^Interface{nil, nil})},
}

wl_surface_events: []Message = []Message {
	{"enter", "o", raw_data([]^Interface{&wl_output_interface})},
	{"leave", "o", raw_data([]^Interface{&wl_output_interface})},
	{"preferred_buffer_scale", "i", raw_data([]^Interface{nil})},
	{"preferred_buffer_transform", "u", raw_data([]^Interface{nil})},
}

wl_surface_interface: Interface = {}
@(init)
init_wl_surface_interface :: proc "contextless" () {
	wl_surface_interface = {"wl_surface", 6, 11, &wl_surface_requests[0], 4, &wl_surface_events[0]}
}

WL_SURFACE_ERROR_INVALID_SCALE :: 0
WL_SURFACE_ERROR_DEFUNCT_ROLE_OBJECT :: 4
WL_SURFACE_ERROR_INVALID_OFFSET :: 3
WL_SURFACE_ERROR_INVALID_TRANSFORM :: 1
WL_SURFACE_ERROR_INVALID_SIZE :: 2

Seat :: struct {}
Seat_Listener :: struct {
	capabilities: proc "c" (data: rawptr, wl_seat: ^Seat, capabilities: Seat_Capabilities),
	name:         proc "c" (data: rawptr, wl_seat: ^Seat, name: cstring),
}

wl_seat_add_listener :: proc(
	wl_seat: ^Seat,
	listener: ^Seat_Listener,
	data: rawptr,
) -> c.int {

	return proxy_add_listener(cast(^Proxy)wl_seat, cast(rawptr)listener, data)
}

seat_get_pointer :: proc "c" (_wl_seat: ^Seat) -> ^Pointer {
	id: ^Proxy
	id = proxy_marshal_flags(
		cast(^Proxy)_wl_seat,
		0,
		&wl_pointer_interface,
		proxy_get_version(cast(^Proxy)_wl_seat),
		0,
		nil,
	)


	return cast(^Pointer)id
}

seat_get_keyboard :: proc "c" (_wl_seat: ^Seat) -> ^Keyboard {
	id: ^Proxy
	id = proxy_marshal_flags(
		cast(^Proxy)_wl_seat,
		1,
		&wl_keyboard_interface,
		proxy_get_version(cast(^Proxy)_wl_seat),
		0,
		nil,
	)


	return cast(^Keyboard)id
}

wl_seat_get_touch :: proc "c" (_wl_seat: ^Seat) -> ^wl_touch {
	id: ^Proxy
	id = proxy_marshal_flags(
		cast(^Proxy)_wl_seat,
		2,
		&wl_touch_interface,
		proxy_get_version(cast(^Proxy)_wl_seat),
		0,
		nil,
	)


	return cast(^wl_touch)id
}

wl_seat_release :: proc "c" (_wl_seat: ^Seat) {
	proxy_marshal_flags(
		cast(^Proxy)_wl_seat,
		3,
		nil,
		proxy_get_version(cast(^Proxy)_wl_seat),
		MARSHAL_FLAG_DESTROY,
	)

}


wl_seat_destroy :: proc "c" (wl_seat: ^Seat) {
	proxy_destroy(cast(^Proxy)wl_seat)
}

wl_seat_requests: []Message = []Message {
	{"get_pointer", "n", raw_data([]^Interface{&wl_pointer_interface})},
	{"get_keyboard", "n", raw_data([]^Interface{&wl_keyboard_interface})},
	{"get_touch", "n", raw_data([]^Interface{&wl_touch_interface})},
	{"release", "", raw_data([]^Interface{})},
}

wl_seat_events: []Message = []Message {
	{"capabilities", "u", raw_data([]^Interface{nil})},
	{"name", "s", raw_data([]^Interface{nil})},
}

seat_interface: Interface = {}
@(init)
init_seat_interface :: proc "contextless" () {
	seat_interface = {"wl_seat", 9, 4, &wl_seat_requests[0], 2, &wl_seat_events[0]}
}

Seat_Capability :: enum u32 {
	Pointer,
	Keyboard,
	Touch,
}

Seat_Capabilities :: bit_set[Seat_Capability; u32]

Pointer :: struct {}
Pointer_Listener :: struct {
	enter:                   proc "c" (
		data: rawptr,
		wl_pointer: ^Pointer,
		serial: u32,
		surface: ^Surface,
		surface_x: Fixed,
		surface_y: Fixed,
	),
	leave:                   proc "c" (
		data: rawptr,
		wl_pointer: ^Pointer,
		serial: u32,
		surface: ^Surface,
	),
	motion:                  proc "c" (
		data: rawptr,
		wl_pointer: ^Pointer,
		time: u32,
		surface_x: Fixed,
		surface_y: Fixed,
	),
	button:                  proc "c" (
		data: rawptr,
		wl_pointer: ^Pointer,
		serial: u32,
		time: u32,
		button: u32,
		state: u32,
	),
	axis:                    proc "c" (
		data: rawptr,
		wl_pointer: ^Pointer,
		time: u32,
		axis: u32,
		value: Fixed,
	),
	frame:                   proc "c" (data: rawptr, wl_pointer: ^Pointer),
	axis_source:             proc "c" (
		data: rawptr,
		wl_pointer: ^Pointer,
		axis_source: u32,
	),
	axis_stop:               proc "c" (
		data: rawptr,
		wl_pointer: ^Pointer,
		time: u32,
		axis: u32,
	),
	axis_discrete:           proc "c" (
		data: rawptr,
		wl_pointer: ^Pointer,
		axis: u32,
		discrete: c.int32_t,
	),
	axis_value120:           proc "c" (
		data: rawptr,
		wl_pointer: ^Pointer,
		axis: u32,
		value120: c.int32_t,
	),
	axis_relative_direction: proc "c" (
		data: rawptr,
		wl_pointer: ^Pointer,
		axis: u32,
		direction: u32,
	),
}

wl_pointer_add_listener :: proc(
	wl_pointer: ^Pointer,
	listener: ^Pointer_Listener,
	data: rawptr,
) -> c.int {

	return proxy_add_listener(cast(^Proxy)wl_pointer, cast(rawptr)listener, data)
}

wl_pointer_set_cursor :: proc "c" (
	_wl_pointer: ^Pointer,
	serial: u32,
	surface: ^Surface,
	hotspot_x: c.int32_t,
	hotspot_y: c.int32_t,
) {
	proxy_marshal_flags(
		cast(^Proxy)_wl_pointer,
		0,
		nil,
		proxy_get_version(cast(^Proxy)_wl_pointer),
		0,
		serial,
		surface,
		hotspot_x,
		hotspot_y,
	)

}

pointer_release :: proc "c" (_wl_pointer: ^Pointer) {
	proxy_marshal_flags(
		cast(^Proxy)_wl_pointer,
		1,
		nil,
		proxy_get_version(cast(^Proxy)_wl_pointer),
		MARSHAL_FLAG_DESTROY,
	)

}


wl_pointer_destroy :: proc "c" (wl_pointer: ^Pointer) {
	proxy_destroy(cast(^Proxy)wl_pointer)
}

wl_pointer_requests: []Message = []Message {
	{"set_cursor", "u?oii", raw_data([]^Interface{nil, &wl_surface_interface, nil, nil})},
	{"release", "", raw_data([]^Interface{})},
}

wl_pointer_events: []Message = []Message {
	{"enter", "uoff", raw_data([]^Interface{nil, &wl_surface_interface, nil, nil})},
	{"leave", "uo", raw_data([]^Interface{nil, &wl_surface_interface})},
	{"motion", "uff", raw_data([]^Interface{nil, nil, nil})},
	{"button", "uuuu", raw_data([]^Interface{nil, nil, nil, nil})},
	{"axis", "uuf", raw_data([]^Interface{nil, nil, nil})},
	{"frame", "", raw_data([]^Interface{})},
	{"axis_source", "u", raw_data([]^Interface{nil})},
	{"axis_stop", "uu", raw_data([]^Interface{nil, nil})},
	{"axis_discrete", "ui", raw_data([]^Interface{nil, nil})},
	{"axis_value120", "ui", raw_data([]^Interface{nil, nil})},
	{"axis_relative_direction", "uu", raw_data([]^Interface{nil, nil})},
}

wl_pointer_interface: Interface = {}
@(init)
init_wl_pointer_interface :: proc "contextless" () {
	wl_pointer_interface = {"wl_pointer", 9, 2, &wl_pointer_requests[0], 11, &wl_pointer_events[0]}
}

WL_POINTER_ERROR_ROLE :: 0
WL_POINTER_BUTTON_STATE_PRESSED :: 1
WL_POINTER_BUTTON_STATE_RELEASED :: 0
WL_POINTER_AXIS_VERTICAL_SCROLL :: 0
WL_POINTER_AXIS_HORIZONTAL_SCROLL :: 1
WL_POINTER_AXIS_SOURCE_CONTINUOUS :: 2
WL_POINTER_AXIS_SOURCE_WHEEL_TILT :: 3
WL_POINTER_AXIS_SOURCE_WHEEL :: 0
WL_POINTER_AXIS_SOURCE_FINGER :: 1
WL_POINTER_AXIS_RELATIVE_DIRECTION_IDENTICAL :: 0
WL_POINTER_AXIS_RELATIVE_DIRECTION_INVERTED :: 1

Keyboard :: struct {}
Keyboard_Listener :: struct {
	keymap:      proc "c" (
		data: rawptr,
		wl_keyboard: ^Keyboard,
		format: u32,
		fd: c.int32_t,
		size: u32,
	),
	enter:       proc "c" (
		data: rawptr,
		wl_keyboard: ^Keyboard,
		serial: u32,
		surface: ^Surface,
		keys: ^Array,
	),
	leave:       proc "c" (
		data: rawptr,
		wl_keyboard: ^Keyboard,
		serial: u32,
		surface: ^Surface,
	),
	key:         proc "c" (
		data: rawptr,
		wl_keyboard: ^Keyboard,
		serial: u32,
		time: u32,
		key: u32,
		state: u32,
	),
	modifiers:   proc "c" (
		data: rawptr,
		wl_keyboard: ^Keyboard,
		serial: u32,
		mods_depressed: u32,
		mods_latched: u32,
		mods_locked: u32,
		group: u32,
	),
	repeat_info: proc "c" (
		data: rawptr,
		wl_keyboard: ^Keyboard,
		rate: c.int32_t,
		delay: c.int32_t,
	),
}

keyboard_release :: proc "c" (_wl_keyboard: ^Keyboard) {
	proxy_marshal_flags(
		cast(^Proxy)_wl_keyboard,
		0,
		nil,
		proxy_get_version(cast(^Proxy)_wl_keyboard),
		MARSHAL_FLAG_DESTROY,
	)

}


wl_keyboard_destroy :: proc "c" (wl_keyboard: ^Keyboard) {
	proxy_destroy(cast(^Proxy)wl_keyboard)
}

wl_keyboard_requests: []Message = []Message{{"release", "", raw_data([]^Interface{})}}

wl_keyboard_events: []Message = []Message {
	{"keymap", "uhu", raw_data([]^Interface{nil, nil, nil})},
	{"enter", "uoa", raw_data([]^Interface{nil, &wl_surface_interface, nil})},
	{"leave", "uo", raw_data([]^Interface{nil, &wl_surface_interface})},
	{"key", "uuuu", raw_data([]^Interface{nil, nil, nil, nil})},
	{"modifiers", "uuuuu", raw_data([]^Interface{nil, nil, nil, nil, nil})},
	{"repeat_info", "ii", raw_data([]^Interface{nil, nil})},
}

wl_keyboard_interface: Interface = {}
@(init)
init_wl_keyboard_interface :: proc "contextless" () {
	wl_keyboard_interface = {
		"wl_keyboard",
		9,
		1,
		&wl_keyboard_requests[0],
		6,
		&wl_keyboard_events[0],
	}
}

WL_KEYBOARD_KEYMAP_FORMAT_NO_KEYMAP :: 0
WL_KEYBOARD_KEYMAP_FORMAT_XKB_V1 :: 1
WL_KEYBOARD_KEY_STATE_RELEASED :: 0
WL_KEYBOARD_KEY_STATE_PRESSED :: 1

wl_touch :: struct {}
wl_touch_listener :: struct {
	down:        proc "c" (
		data: rawptr,
		wl_touch: ^wl_touch,
		serial: u32,
		time: u32,
		surface: ^Surface,
		id: c.int32_t,
		x: Fixed,
		y: Fixed,
	),
	up:          proc "c" (
		data: rawptr,
		wl_touch: ^wl_touch,
		serial: u32,
		time: u32,
		id: c.int32_t,
	),
	motion:      proc "c" (
		data: rawptr,
		wl_touch: ^wl_touch,
		time: u32,
		id: c.int32_t,
		x: Fixed,
		y: Fixed,
	),
	frame:       proc "c" (data: rawptr, wl_touch: ^wl_touch),
	cancel:      proc "c" (data: rawptr, wl_touch: ^wl_touch),
	shape:       proc "c" (
		data: rawptr,
		wl_touch: ^wl_touch,
		id: c.int32_t,
		major: Fixed,
		minor: Fixed,
	),
	orientation: proc "c" (
		data: rawptr,
		wl_touch: ^wl_touch,
		id: c.int32_t,
		orientation: Fixed,
	),
}

wl_touch_add_listener :: proc(
	wl_touch: ^wl_touch,
	listener: ^wl_touch_listener,
	data: rawptr,
) -> c.int {

	return proxy_add_listener(cast(^Proxy)wl_touch, cast(rawptr)listener, data)
}

wl_touch_release :: proc "c" (_wl_touch: ^wl_touch) {
	proxy_marshal_flags(
		cast(^Proxy)_wl_touch,
		0,
		nil,
		proxy_get_version(cast(^Proxy)_wl_touch),
		MARSHAL_FLAG_DESTROY,
	)

}


wl_touch_destroy :: proc "c" (wl_touch: ^wl_touch) {
	proxy_destroy(cast(^Proxy)wl_touch)
}

wl_touch_requests: []Message = []Message{{"release", "", raw_data([]^Interface{})}}

wl_touch_events: []Message = []Message {
	{"down", "uuoiff", raw_data([]^Interface{nil, nil, &wl_surface_interface, nil, nil, nil})},
	{"up", "uui", raw_data([]^Interface{nil, nil, nil})},
	{"motion", "uiff", raw_data([]^Interface{nil, nil, nil, nil})},
	{"frame", "", raw_data([]^Interface{})},
	{"cancel", "", raw_data([]^Interface{})},
	{"shape", "iff", raw_data([]^Interface{nil, nil, nil})},
	{"orientation", "if", raw_data([]^Interface{nil, nil})},
}

wl_touch_interface: Interface = {}
@(init)
init_wl_touch_interface :: proc "contextless" () {
	wl_touch_interface = {"wl_touch", 9, 1, &wl_touch_requests[0], 7, &wl_touch_events[0]}
}


wl_output :: struct {}
wl_output_listener :: struct {
	geometry:    proc "c" (
		data: rawptr,
		wl_output: ^wl_output,
		x: c.int32_t,
		y: c.int32_t,
		physical_width: c.int32_t,
		physical_height: c.int32_t,
		subpixel: c.int32_t,
		make: cstring,
		model: cstring,
		transform: c.int32_t,
	),
	mode:        proc "c" (
		data: rawptr,
		wl_output: ^wl_output,
		flags: u32,
		width: c.int32_t,
		height: c.int32_t,
		refresh: c.int32_t,
	),
	done:        proc "c" (data: rawptr, wl_output: ^wl_output),
	scale:       proc "c" (data: rawptr, wl_output: ^wl_output, factor: c.int32_t),
	name:        proc "c" (data: rawptr, wl_output: ^wl_output, name: cstring),
	description: proc "c" (data: rawptr, wl_output: ^wl_output, description: cstring),
}

wl_output_add_listener :: proc(
	wl_output: ^wl_output,
	listener: ^wl_output_listener,
	data: rawptr,
) -> c.int {

	return proxy_add_listener(cast(^Proxy)wl_output, cast(rawptr)listener, data)
}

wl_output_release :: proc "c" (_wl_output: ^wl_output) {
	proxy_marshal_flags(
		cast(^Proxy)_wl_output,
		0,
		nil,
		proxy_get_version(cast(^Proxy)_wl_output),
		MARSHAL_FLAG_DESTROY,
	)

}


wl_output_destroy :: proc "c" (wl_output: ^wl_output) {
	proxy_destroy(cast(^Proxy)wl_output)
}

wl_output_requests: []Message = []Message{{"release", "", raw_data([]^Interface{})}}

wl_output_events: []Message = []Message {
	{"geometry", "iiiiissi", raw_data([]^Interface{nil, nil, nil, nil, nil, nil, nil, nil})},
	{"mode", "uiii", raw_data([]^Interface{nil, nil, nil, nil})},
	{"done", "", raw_data([]^Interface{})},
	{"scale", "i", raw_data([]^Interface{nil})},
	{"name", "s", raw_data([]^Interface{nil})},
	{"description", "s", raw_data([]^Interface{nil})},
}

wl_output_interface: Interface = {}
@(init)
init_wl_output_interface :: proc "contextless" () {
	wl_output_interface = {"wl_output", 4, 1, &wl_output_requests[0], 6, &wl_output_events[0]}
}

WL_OUTPUT_SUBPIXEL_NONE :: 1
WL_OUTPUT_SUBPIXEL_HORIZONTAL_RGB :: 2
WL_OUTPUT_SUBPIXEL_HORIZONTAL_BGR :: 3
WL_OUTPUT_SUBPIXEL_VERTICAL_RGB :: 4
WL_OUTPUT_SUBPIXEL_VERTICAL_BGR :: 5
WL_OUTPUT_SUBPIXEL_UNKNOWN :: 0
WL_OUTPUT_TRANSFORM_FLIPPED_270 :: 7
WL_OUTPUT_TRANSFORM_180 :: 2
WL_OUTPUT_TRANSFORM_FLIPPED_180 :: 6
WL_OUTPUT_TRANSFORM_FLIPPED_90 :: 5
WL_OUTPUT_TRANSFORM_270 :: 3
WL_OUTPUT_TRANSFORM_NORMAL :: 0
WL_OUTPUT_TRANSFORM_FLIPPED :: 4
WL_OUTPUT_TRANSFORM_90 :: 1
WL_OUTPUT_MODE_CURRENT :: 0x1
WL_OUTPUT_MODE_PREFERRED :: 0x2

wl_region :: struct {}
wl_region_listener :: struct {}

wl_region_add_listener :: proc(
	wl_region: ^wl_region,
	listener: ^wl_region_listener,
	data: rawptr,
) -> c.int {

	return proxy_add_listener(cast(^Proxy)wl_region, cast(rawptr)listener, data)
}

wl_region_destroy :: proc "c" (_wl_region: ^wl_region) {
	proxy_marshal_flags(
		cast(^Proxy)_wl_region,
		0,
		nil,
		proxy_get_version(cast(^Proxy)_wl_region),
		MARSHAL_FLAG_DESTROY,
	)

}

wl_region_add :: proc "c" (
	_wl_region: ^wl_region,
	x: c.int32_t,
	y: c.int32_t,
	width: c.int32_t,
	height: c.int32_t,
) {
	proxy_marshal_flags(
		cast(^Proxy)_wl_region,
		1,
		nil,
		proxy_get_version(cast(^Proxy)_wl_region),
		0,
		x,
		y,
		width,
		height,
	)

}

wl_region_subtract :: proc "c" (
	_wl_region: ^wl_region,
	x: c.int32_t,
	y: c.int32_t,
	width: c.int32_t,
	height: c.int32_t,
) {
	proxy_marshal_flags(
		cast(^Proxy)_wl_region,
		2,
		nil,
		proxy_get_version(cast(^Proxy)_wl_region),
		0,
		x,
		y,
		width,
		height,
	)

}

wl_region_requests: []Message = []Message {
	{"destroy", "", raw_data([]^Interface{})},
	{"add", "iiii", raw_data([]^Interface{nil, nil, nil, nil})},
	{"subtract", "iiii", raw_data([]^Interface{nil, nil, nil, nil})},
}

wl_region_events: []Message = []Message{}

wl_region_interface: Interface = {}
@(init)
init_wl_region_interface :: proc "contextless" () {
	wl_region_interface = {"wl_region", 1, 3, &wl_region_requests[0], 0, nil}
}


wl_subcompositor :: struct {}
wl_subcompositor_listener :: struct {}

wl_subcompositor_add_listener :: proc(
	wl_subcompositor: ^wl_subcompositor,
	listener: ^wl_subcompositor_listener,
	data: rawptr,
) -> c.int {

	return proxy_add_listener(cast(^Proxy)wl_subcompositor, cast(rawptr)listener, data)
}

wl_subcompositor_destroy :: proc "c" (_wl_subcompositor: ^wl_subcompositor) {
	proxy_marshal_flags(
		cast(^Proxy)_wl_subcompositor,
		0,
		nil,
		proxy_get_version(cast(^Proxy)_wl_subcompositor),
		MARSHAL_FLAG_DESTROY,
	)

}

wl_subcompositor_get_subsurface :: proc "c" (
	_wl_subcompositor: ^wl_subcompositor,
	surface: ^Surface,
	parent: ^Surface,
) -> ^wl_subsurface {
	id: ^Proxy
	id = proxy_marshal_flags(
		cast(^Proxy)_wl_subcompositor,
		1,
		&wl_subsurface_interface,
		proxy_get_version(cast(^Proxy)_wl_subcompositor),
		0,
		nil,
		surface,
		parent,
	)


	return cast(^wl_subsurface)id
}

wl_subcompositor_requests: []Message = []Message {
	{"destroy", "", raw_data([]^Interface{})},
	{
		"get_subsurface",
		"noo",
		raw_data(
			[]^Interface {
				&wl_subsurface_interface,
				&wl_surface_interface,
				&wl_surface_interface,
			},
		),
	},
}

wl_subcompositor_events: []Message = []Message{}

wl_subcompositor_interface: Interface = {}
@(init)
init_wl_subcompositor_interface :: proc "contextless" () {
	wl_subcompositor_interface = {"wl_subcompositor", 1, 2, &wl_subcompositor_requests[0], 0, nil}
}

WL_SUBCOMPOSITOR_ERROR_BAD_SURFACE :: 0
WL_SUBCOMPOSITOR_ERROR_BAD_PARENT :: 1

wl_subsurface :: struct {}
wl_subsurface_listener :: struct {}

wl_subsurface_add_listener :: proc(
	wl_subsurface: ^wl_subsurface,
	listener: ^wl_subsurface_listener,
	data: rawptr,
) -> c.int {

	return proxy_add_listener(cast(^Proxy)wl_subsurface, cast(rawptr)listener, data)
}

wl_subsurface_destroy :: proc "c" (_wl_subsurface: ^wl_subsurface) {
	proxy_marshal_flags(
		cast(^Proxy)_wl_subsurface,
		0,
		nil,
		proxy_get_version(cast(^Proxy)_wl_subsurface),
		MARSHAL_FLAG_DESTROY,
	)

}

wl_subsurface_set_position :: proc "c" (
	_wl_subsurface: ^wl_subsurface,
	x: c.int32_t,
	y: c.int32_t,
) {
	proxy_marshal_flags(
		cast(^Proxy)_wl_subsurface,
		1,
		nil,
		proxy_get_version(cast(^Proxy)_wl_subsurface),
		0,
		x,
		y,
	)

}

wl_subsurface_place_above :: proc "c" (_wl_subsurface: ^wl_subsurface, sibling: ^Surface) {
	proxy_marshal_flags(
		cast(^Proxy)_wl_subsurface,
		2,
		nil,
		proxy_get_version(cast(^Proxy)_wl_subsurface),
		0,
		sibling,
	)

}

wl_subsurface_place_below :: proc "c" (_wl_subsurface: ^wl_subsurface, sibling: ^Surface) {
	proxy_marshal_flags(
		cast(^Proxy)_wl_subsurface,
		3,
		nil,
		proxy_get_version(cast(^Proxy)_wl_subsurface),
		0,
		sibling,
	)

}

wl_subsurface_set_sync :: proc "c" (_wl_subsurface: ^wl_subsurface) {
	proxy_marshal_flags(
		cast(^Proxy)_wl_subsurface,
		4,
		nil,
		proxy_get_version(cast(^Proxy)_wl_subsurface),
		0,
	)

}

wl_subsurface_set_desync :: proc "c" (_wl_subsurface: ^wl_subsurface) {
	proxy_marshal_flags(
		cast(^Proxy)_wl_subsurface,
		5,
		nil,
		proxy_get_version(cast(^Proxy)_wl_subsurface),
		0,
	)

}

wl_subsurface_requests: []Message = []Message {
	{"destroy", "", raw_data([]^Interface{})},
	{"set_position", "ii", raw_data([]^Interface{nil, nil})},
	{"place_above", "o", raw_data([]^Interface{&wl_surface_interface})},
	{"place_below", "o", raw_data([]^Interface{&wl_surface_interface})},
	{"set_sync", "", raw_data([]^Interface{})},
	{"set_desync", "", raw_data([]^Interface{})},
}

wl_subsurface_events: []Message = []Message{}

wl_subsurface_interface: Interface = {}
@(init)
init_wl_subsurface_interface :: proc "contextless" () {
	wl_subsurface_interface = {"wl_subsurface", 1, 6, &wl_subsurface_requests[0], 0, nil}
}

WL_SUBSURFACE_ERROR_BAD_SURFACE :: 0
