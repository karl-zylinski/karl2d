package wayland

import "core:c"

xdg_wm_base :: struct {}
xdg_wm_base_listener :: struct {
	ping: proc "c" (
		data: rawptr,
		xdg_wm_base: ^xdg_wm_base,
		serial: c.uint32_t,
	),
}

xdg_wm_base_add_listener :: proc(
    xdg_wm_base: ^xdg_wm_base,
    listener: ^xdg_wm_base_listener,
    data: rawptr,
) -> c.int {

    return proxy_add_listener(cast(^wl_proxy)xdg_wm_base, cast(^Implementation)listener, data)
};

xdg_wm_base_destroy :: proc "c" (_xdg_wm_base: ^xdg_wm_base)
{
proxy_marshal_flags(
                cast(^wl_proxy)_xdg_wm_base,
		        0, nil, proxy_get_version(cast(^wl_proxy)_xdg_wm_base), WL_MARSHAL_FLAG_DESTROY);

}

xdg_wm_base_create_positioner :: proc "c" (_xdg_wm_base: ^xdg_wm_base)-> ^xdg_positioner {
	id: ^wl_proxy
	id = proxy_marshal_flags(
                cast(^wl_proxy)_xdg_wm_base,
		        1, &xdg_positioner_interface, proxy_get_version(cast(^wl_proxy)_xdg_wm_base), 0, nil);


	return cast(^xdg_positioner)id;
}

xdg_wm_base_get_xdg_surface :: proc "c" (_xdg_wm_base: ^xdg_wm_base,surface : ^wl_surface)-> ^xdg_surface {
	id: ^wl_proxy
	id = proxy_marshal_flags(
                cast(^wl_proxy)_xdg_wm_base,
		        2, &xdg_surface_interface, proxy_get_version(cast(^wl_proxy)_xdg_wm_base), 0, nil, surface);


	return cast(^xdg_surface)id;
}

xdg_wm_base_pong :: proc "c" (_xdg_wm_base: ^xdg_wm_base,serial : c.uint32_t)
{
proxy_marshal_flags(
                cast(^wl_proxy)_xdg_wm_base,
		        3, nil, proxy_get_version(cast(^wl_proxy)_xdg_wm_base), 0, serial);

}

xdg_wm_base_requests: []wl_message = []wl_message{
	{ "destroy", "", raw_data([]^wl_interface{}) },
	{ "create_positioner", "n", raw_data([]^wl_interface{&xdg_positioner_interface}) },
	{ "get_xdg_surface", "no", raw_data([]^wl_interface{&xdg_surface_interface, &wl_surface_interface}) },
	{ "pong", "u", raw_data([]^wl_interface{nil}) },
}

xdg_wm_base_events: []wl_message = []wl_message{
	{ "ping", "u", raw_data([]^wl_interface{nil}) },
}

xdg_wm_base_interface: wl_interface = {}
@(init)
init_xdg_wm_base_interface :: proc "contextless" () {
	xdg_wm_base_interface = {
		"xdg_wm_base",
		6,
		4,
		&xdg_wm_base_requests[0],
		1,
		&xdg_wm_base_events[0],
	}
}

XDG_WM_BASE_ERROR_INVALID_SURFACE_STATE :: 4
XDG_WM_BASE_ERROR_DEFUNCT_SURFACES :: 1
XDG_WM_BASE_ERROR_INVALID_POSITIONER :: 5
XDG_WM_BASE_ERROR_NOT_THE_TOPMOST_POPUP :: 2
XDG_WM_BASE_ERROR_UNRESPONSIVE :: 6
XDG_WM_BASE_ERROR_ROLE :: 0
XDG_WM_BASE_ERROR_INVALID_POPUP_PARENT :: 3

xdg_positioner :: struct {}
xdg_positioner_listener :: struct {
}

xdg_positioner_add_listener :: proc(
    xdg_positioner: ^xdg_positioner,
    listener: ^xdg_positioner_listener,
    data: rawptr,
) -> c.int {

    return proxy_add_listener(cast(^wl_proxy)xdg_positioner, cast(^Implementation)listener, data)
};

xdg_positioner_destroy :: proc "c" (_xdg_positioner: ^xdg_positioner)
{
proxy_marshal_flags(
                cast(^wl_proxy)_xdg_positioner,
		        0, nil, proxy_get_version(cast(^wl_proxy)_xdg_positioner), WL_MARSHAL_FLAG_DESTROY);

}

xdg_positioner_set_size :: proc "c" (_xdg_positioner: ^xdg_positioner,width : c.int32_t,height : c.int32_t)
{
proxy_marshal_flags(
                cast(^wl_proxy)_xdg_positioner,
		        1, nil, proxy_get_version(cast(^wl_proxy)_xdg_positioner), 0, width, height);

}

xdg_positioner_set_anchor_rect :: proc "c" (_xdg_positioner: ^xdg_positioner,x : c.int32_t,y : c.int32_t,width : c.int32_t,height : c.int32_t)
{
proxy_marshal_flags(
                cast(^wl_proxy)_xdg_positioner,
		        2, nil, proxy_get_version(cast(^wl_proxy)_xdg_positioner), 0, x, y, width, height);

}

xdg_positioner_set_anchor :: proc "c" (_xdg_positioner: ^xdg_positioner,anchor : c.uint32_t)
{
proxy_marshal_flags(
                cast(^wl_proxy)_xdg_positioner,
		        3, nil, proxy_get_version(cast(^wl_proxy)_xdg_positioner), 0, anchor);

}

xdg_positioner_set_gravity :: proc "c" (_xdg_positioner: ^xdg_positioner,gravity : c.uint32_t)
{
proxy_marshal_flags(
                cast(^wl_proxy)_xdg_positioner,
		        4, nil, proxy_get_version(cast(^wl_proxy)_xdg_positioner), 0, gravity);

}

xdg_positioner_set_constraint_adjustment :: proc "c" (_xdg_positioner: ^xdg_positioner,constraint_adjustment : c.uint32_t)
{
proxy_marshal_flags(
                cast(^wl_proxy)_xdg_positioner,
		        5, nil, proxy_get_version(cast(^wl_proxy)_xdg_positioner), 0, constraint_adjustment);

}

xdg_positioner_set_offset :: proc "c" (_xdg_positioner: ^xdg_positioner,x : c.int32_t,y : c.int32_t)
{
proxy_marshal_flags(
                cast(^wl_proxy)_xdg_positioner,
		        6, nil, proxy_get_version(cast(^wl_proxy)_xdg_positioner), 0, x, y);

}

xdg_positioner_set_reactive :: proc "c" (_xdg_positioner: ^xdg_positioner)
{
proxy_marshal_flags(
                cast(^wl_proxy)_xdg_positioner,
		        7, nil, proxy_get_version(cast(^wl_proxy)_xdg_positioner), 0);

}

xdg_positioner_set_parent_size :: proc "c" (_xdg_positioner: ^xdg_positioner,parent_width : c.int32_t,parent_height : c.int32_t)
{
proxy_marshal_flags(
                cast(^wl_proxy)_xdg_positioner,
		        8, nil, proxy_get_version(cast(^wl_proxy)_xdg_positioner), 0, parent_width, parent_height);

}

xdg_positioner_set_parent_configure :: proc "c" (_xdg_positioner: ^xdg_positioner,serial : c.uint32_t)
{
proxy_marshal_flags(
                cast(^wl_proxy)_xdg_positioner,
		        9, nil, proxy_get_version(cast(^wl_proxy)_xdg_positioner), 0, serial);

}

xdg_positioner_requests: []wl_message = []wl_message{
	{ "destroy", "", raw_data([]^wl_interface{}) },
	{ "set_size", "ii", raw_data([]^wl_interface{nil, nil}) },
	{ "set_anchor_rect", "iiii", raw_data([]^wl_interface{nil, nil, nil, nil}) },
	{ "set_anchor", "u", raw_data([]^wl_interface{nil}) },
	{ "set_gravity", "u", raw_data([]^wl_interface{nil}) },
	{ "set_constraint_adjustment", "u", raw_data([]^wl_interface{nil}) },
	{ "set_offset", "ii", raw_data([]^wl_interface{nil, nil}) },
	{ "set_reactive", "", raw_data([]^wl_interface{}) },
	{ "set_parent_size", "ii", raw_data([]^wl_interface{nil, nil}) },
	{ "set_parent_configure", "u", raw_data([]^wl_interface{nil}) },
}

xdg_positioner_events: []wl_message = []wl_message{
}

xdg_positioner_interface: wl_interface = {}
@(init)
init_xdg_positioner_interface :: proc "contextless" () {
	xdg_positioner_interface = {
		"xdg_positioner",
		6,
		10,
		&xdg_positioner_requests[0],
		0,
		nil,
	}
}

XDG_POSITIONER_ERROR_INVALID_INPUT :: 0
XDG_POSITIONER_ANCHOR_TOP :: 1
XDG_POSITIONER_ANCHOR_LEFT :: 3
XDG_POSITIONER_ANCHOR_TOP_RIGHT :: 7
XDG_POSITIONER_ANCHOR_BOTTOM :: 2
XDG_POSITIONER_ANCHOR_BOTTOM_RIGHT :: 8
XDG_POSITIONER_ANCHOR_BOTTOM_LEFT :: 6
XDG_POSITIONER_ANCHOR_NONE :: 0
XDG_POSITIONER_ANCHOR_TOP_LEFT :: 5
XDG_POSITIONER_ANCHOR_RIGHT :: 4
XDG_POSITIONER_GRAVITY_TOP :: 1
XDG_POSITIONER_GRAVITY_NONE :: 0
XDG_POSITIONER_GRAVITY_BOTTOM_RIGHT :: 8
XDG_POSITIONER_GRAVITY_TOP_LEFT :: 5
XDG_POSITIONER_GRAVITY_RIGHT :: 4
XDG_POSITIONER_GRAVITY_BOTTOM_LEFT :: 6
XDG_POSITIONER_GRAVITY_LEFT :: 3
XDG_POSITIONER_GRAVITY_TOP_RIGHT :: 7
XDG_POSITIONER_GRAVITY_BOTTOM :: 2
XDG_POSITIONER_CONSTRAINT_ADJUSTMENT_SLIDE_Y :: 2
XDG_POSITIONER_CONSTRAINT_ADJUSTMENT_FLIP_X :: 4
XDG_POSITIONER_CONSTRAINT_ADJUSTMENT_SLIDE_X :: 1
XDG_POSITIONER_CONSTRAINT_ADJUSTMENT_RESIZE_Y :: 32
XDG_POSITIONER_CONSTRAINT_ADJUSTMENT_NONE :: 0
XDG_POSITIONER_CONSTRAINT_ADJUSTMENT_FLIP_Y :: 8
XDG_POSITIONER_CONSTRAINT_ADJUSTMENT_RESIZE_X :: 16

xdg_surface :: struct {}
xdg_surface_listener :: struct {
	configure: proc "c" (
		data: rawptr,
		xdg_surface: ^xdg_surface,
		serial: c.uint32_t,
	),
}

xdg_surface_add_listener :: proc(
    xdg_surface: ^xdg_surface,
    listener: ^xdg_surface_listener,
    data: rawptr,
) -> c.int {

    return proxy_add_listener(cast(^wl_proxy)xdg_surface, cast(^Implementation)listener, data)
};

xdg_surface_destroy :: proc "c" (_xdg_surface: ^xdg_surface)
{
proxy_marshal_flags(
                cast(^wl_proxy)_xdg_surface,
		        0, nil, proxy_get_version(cast(^wl_proxy)_xdg_surface), WL_MARSHAL_FLAG_DESTROY);

}

xdg_surface_get_toplevel :: proc "c" (_xdg_surface: ^xdg_surface)-> ^xdg_toplevel {
	id: ^wl_proxy
	id = proxy_marshal_flags(
                cast(^wl_proxy)_xdg_surface,
		        1, &xdg_toplevel_interface, proxy_get_version(cast(^wl_proxy)_xdg_surface), 0, nil);


	return cast(^xdg_toplevel)id;
}

xdg_surface_get_popup :: proc "c" (_xdg_surface: ^xdg_surface,parent : ^xdg_surface,positioner : ^xdg_positioner)-> ^xdg_popup {
	id: ^wl_proxy
	id = proxy_marshal_flags(
                cast(^wl_proxy)_xdg_surface,
		        2, &xdg_popup_interface, proxy_get_version(cast(^wl_proxy)_xdg_surface), 0, nil, parent, positioner);


	return cast(^xdg_popup)id;
}

xdg_surface_set_window_geometry :: proc "c" (_xdg_surface: ^xdg_surface,x : c.int32_t,y : c.int32_t,width : c.int32_t,height : c.int32_t)
{
proxy_marshal_flags(
                cast(^wl_proxy)_xdg_surface,
		        3, nil, proxy_get_version(cast(^wl_proxy)_xdg_surface), 0, x, y, width, height);

}

xdg_surface_ack_configure :: proc "c" (_xdg_surface: ^xdg_surface,serial : c.uint32_t)
{
proxy_marshal_flags(
                cast(^wl_proxy)_xdg_surface,
		        4, nil, proxy_get_version(cast(^wl_proxy)_xdg_surface), 0, serial);

}

xdg_surface_requests: []wl_message = []wl_message{
	{ "destroy", "", raw_data([]^wl_interface{}) },
	{ "get_toplevel", "n", raw_data([]^wl_interface{&xdg_toplevel_interface}) },
	{ "get_popup", "n?oo", raw_data([]^wl_interface{&xdg_popup_interface, &xdg_surface_interface, &xdg_positioner_interface}) },
	{ "set_window_geometry", "iiii", raw_data([]^wl_interface{nil, nil, nil, nil}) },
	{ "ack_configure", "u", raw_data([]^wl_interface{nil}) },
}

xdg_surface_events: []wl_message = []wl_message{
	{ "configure", "u", raw_data([]^wl_interface{nil}) },
}

xdg_surface_interface: wl_interface = {}
@(init)
init_xdg_surface_interface :: proc "contextless" () {
	xdg_surface_interface = {
		"xdg_surface",
		6,
		5,
		&xdg_surface_requests[0],
		1,
		&xdg_surface_events[0],
	}
}

XDG_SURFACE_ERROR_ALREADY_CONSTRUCTED :: 2
XDG_SURFACE_ERROR_INVALID_SIZE :: 5
XDG_SURFACE_ERROR_UNCONFIGURED_BUFFER :: 3
XDG_SURFACE_ERROR_NOT_CONSTRUCTED :: 1
XDG_SURFACE_ERROR_DEFUNCT_ROLE_OBJECT :: 6
XDG_SURFACE_ERROR_INVALID_SERIAL :: 4

xdg_toplevel :: struct {}
xdg_toplevel_listener :: struct {
	configure: proc "c" (
		data: rawptr,
		xdg_toplevel: ^xdg_toplevel,
		width: c.int32_t,
		height: c.int32_t,
		states: ^wl_array,
	),
	close: proc "c" (
		data: rawptr,
		xdg_toplevel: ^xdg_toplevel,
	),
	configure_bounds: proc "c" (
		data: rawptr,
		xdg_toplevel: ^xdg_toplevel,
		width: c.int32_t,
		height: c.int32_t,
	),
	wm_capabilities: proc "c" (
		data: rawptr,
		xdg_toplevel: ^xdg_toplevel,
		capabilities: ^wl_array,
	),
}

xdg_toplevel_add_listener :: proc(
    xdg_toplevel: ^xdg_toplevel,
    listener: ^xdg_toplevel_listener,
    data: rawptr,
) -> c.int {

    return proxy_add_listener(cast(^wl_proxy)xdg_toplevel, cast(^Implementation)listener, data)
};

xdg_toplevel_destroy :: proc "c" (_xdg_toplevel: ^xdg_toplevel)
{
proxy_marshal_flags(
                cast(^wl_proxy)_xdg_toplevel,
		        0, nil, proxy_get_version(cast(^wl_proxy)_xdg_toplevel), WL_MARSHAL_FLAG_DESTROY);

}

xdg_toplevel_set_parent :: proc "c" (_xdg_toplevel: ^xdg_toplevel,parent : ^xdg_toplevel)
{
proxy_marshal_flags(
                cast(^wl_proxy)_xdg_toplevel,
		        1, nil, proxy_get_version(cast(^wl_proxy)_xdg_toplevel), 0, parent);

}

xdg_toplevel_set_title :: proc "c" (_xdg_toplevel: ^xdg_toplevel,title : cstring)
{
proxy_marshal_flags(
                cast(^wl_proxy)_xdg_toplevel,
		        2, nil, proxy_get_version(cast(^wl_proxy)_xdg_toplevel), 0, title);

}

xdg_toplevel_set_app_id :: proc "c" (_xdg_toplevel: ^xdg_toplevel,app_id : cstring)
{
proxy_marshal_flags(
                cast(^wl_proxy)_xdg_toplevel,
		        3, nil, proxy_get_version(cast(^wl_proxy)_xdg_toplevel), 0, app_id);

}

xdg_toplevel_show_window_menu :: proc "c" (_xdg_toplevel: ^xdg_toplevel,seat : ^wl_seat,serial : c.uint32_t,x : c.int32_t,y : c.int32_t)
{
proxy_marshal_flags(
                cast(^wl_proxy)_xdg_toplevel,
		        4, nil, proxy_get_version(cast(^wl_proxy)_xdg_toplevel), 0, seat, serial, x, y);

}

xdg_toplevel_move :: proc "c" (_xdg_toplevel: ^xdg_toplevel,seat : ^wl_seat,serial : c.uint32_t)
{
proxy_marshal_flags(
                cast(^wl_proxy)_xdg_toplevel,
		        5, nil, proxy_get_version(cast(^wl_proxy)_xdg_toplevel), 0, seat, serial);

}

xdg_toplevel_resize :: proc "c" (_xdg_toplevel: ^xdg_toplevel,seat : ^wl_seat,serial : c.uint32_t,edges : c.uint32_t)
{
proxy_marshal_flags(
                cast(^wl_proxy)_xdg_toplevel,
		        6, nil, proxy_get_version(cast(^wl_proxy)_xdg_toplevel), 0, seat, serial, edges);

}

xdg_toplevel_set_max_size :: proc "c" (_xdg_toplevel: ^xdg_toplevel,width : c.int32_t,height : c.int32_t)
{
proxy_marshal_flags(
                cast(^wl_proxy)_xdg_toplevel,
		        7, nil, proxy_get_version(cast(^wl_proxy)_xdg_toplevel), 0, width, height);

}

xdg_toplevel_set_min_size :: proc "c" (_xdg_toplevel: ^xdg_toplevel,width : c.int32_t,height : c.int32_t)
{
proxy_marshal_flags(
                cast(^wl_proxy)_xdg_toplevel,
		        8, nil, proxy_get_version(cast(^wl_proxy)_xdg_toplevel), 0, width, height);

}

xdg_toplevel_set_maximized :: proc "c" (_xdg_toplevel: ^xdg_toplevel)
{
proxy_marshal_flags(
                cast(^wl_proxy)_xdg_toplevel,
		        9, nil, proxy_get_version(cast(^wl_proxy)_xdg_toplevel), 0);

}

xdg_toplevel_unset_maximized :: proc "c" (_xdg_toplevel: ^xdg_toplevel)
{
proxy_marshal_flags(
                cast(^wl_proxy)_xdg_toplevel,
		        10, nil, proxy_get_version(cast(^wl_proxy)_xdg_toplevel), 0);

}

xdg_toplevel_set_fullscreen :: proc "c" (_xdg_toplevel: ^xdg_toplevel,output : ^wl_output)
{
proxy_marshal_flags(
                cast(^wl_proxy)_xdg_toplevel,
		        11, nil, proxy_get_version(cast(^wl_proxy)_xdg_toplevel), 0, output);

}

xdg_toplevel_unset_fullscreen :: proc "c" (_xdg_toplevel: ^xdg_toplevel)
{
proxy_marshal_flags(
                cast(^wl_proxy)_xdg_toplevel,
		        12, nil, proxy_get_version(cast(^wl_proxy)_xdg_toplevel), 0);

}

xdg_toplevel_set_minimized :: proc "c" (_xdg_toplevel: ^xdg_toplevel)
{
proxy_marshal_flags(
                cast(^wl_proxy)_xdg_toplevel,
		        13, nil, proxy_get_version(cast(^wl_proxy)_xdg_toplevel), 0);

}

xdg_toplevel_requests: []wl_message = []wl_message{
	{ "destroy", "", raw_data([]^wl_interface{}) },
	{ "set_parent", "?o", raw_data([]^wl_interface{&xdg_toplevel_interface}) },
	{ "set_title", "s", raw_data([]^wl_interface{nil}) },
	{ "set_app_id", "s", raw_data([]^wl_interface{nil}) },
	{ "show_window_menu", "ouii", raw_data([]^wl_interface{&wl_seat_interface, nil, nil, nil}) },
	{ "move", "ou", raw_data([]^wl_interface{&wl_seat_interface, nil}) },
	{ "resize", "ouu", raw_data([]^wl_interface{&wl_seat_interface, nil, nil}) },
	{ "set_max_size", "ii", raw_data([]^wl_interface{nil, nil}) },
	{ "set_min_size", "ii", raw_data([]^wl_interface{nil, nil}) },
	{ "set_maximized", "", raw_data([]^wl_interface{}) },
	{ "unset_maximized", "", raw_data([]^wl_interface{}) },
	{ "set_fullscreen", "?o", raw_data([]^wl_interface{&wl_output_interface}) },
	{ "unset_fullscreen", "", raw_data([]^wl_interface{}) },
	{ "set_minimized", "", raw_data([]^wl_interface{}) },
}

xdg_toplevel_events: []wl_message = []wl_message{
	{ "configure", "iia", raw_data([]^wl_interface{nil, nil, nil}) },
	{ "close", "", raw_data([]^wl_interface{}) },
	{ "configure_bounds", "ii", raw_data([]^wl_interface{nil, nil}) },
	{ "wm_capabilities", "a", raw_data([]^wl_interface{nil}) },
}

xdg_toplevel_interface: wl_interface = {}
@(init)
init_xdg_toplevel_interface :: proc "contextless" () {
	xdg_toplevel_interface = {
		"xdg_toplevel",
		6,
		14,
		&xdg_toplevel_requests[0],
		4,
		&xdg_toplevel_events[0],
	}
}

XDG_TOPLEVEL_ERROR_INVALID_PARENT :: 1
XDG_TOPLEVEL_ERROR_INVALID_SIZE :: 2
XDG_TOPLEVEL_ERROR_INVALID_RESIZE_EDGE :: 0
XDG_TOPLEVEL_RESIZE_EDGE_LEFT :: 4
XDG_TOPLEVEL_RESIZE_EDGE_TOP :: 1
XDG_TOPLEVEL_RESIZE_EDGE_TOP_RIGHT :: 9
XDG_TOPLEVEL_RESIZE_EDGE_BOTTOM :: 2
XDG_TOPLEVEL_RESIZE_EDGE_BOTTOM_RIGHT :: 10
XDG_TOPLEVEL_RESIZE_EDGE_BOTTOM_LEFT :: 6
XDG_TOPLEVEL_RESIZE_EDGE_NONE :: 0
XDG_TOPLEVEL_RESIZE_EDGE_TOP_LEFT :: 5
XDG_TOPLEVEL_RESIZE_EDGE_RIGHT :: 8
XDG_TOPLEVEL_STATE_MAXIMIZED :: 1
XDG_TOPLEVEL_STATE_RESIZING :: 3
XDG_TOPLEVEL_STATE_SUSPENDED :: 9
XDG_TOPLEVEL_STATE_TILED_TOP :: 7
XDG_TOPLEVEL_STATE_FULLSCREEN :: 2
XDG_TOPLEVEL_STATE_TILED_LEFT :: 5
XDG_TOPLEVEL_STATE_TILED_RIGHT :: 6
XDG_TOPLEVEL_STATE_TILED_BOTTOM :: 8
XDG_TOPLEVEL_STATE_ACTIVATED :: 4
XDG_TOPLEVEL_WM_CAPABILITIES_MINIMIZE :: 4
XDG_TOPLEVEL_WM_CAPABILITIES_FULLSCREEN :: 3
XDG_TOPLEVEL_WM_CAPABILITIES_MAXIMIZE :: 2
XDG_TOPLEVEL_WM_CAPABILITIES_WINDOW_MENU :: 1

xdg_popup :: struct {}
xdg_popup_listener :: struct {
	configure: proc "c" (
		data: rawptr,
		xdg_popup: ^xdg_popup,
		x: c.int32_t,
		y: c.int32_t,
		width: c.int32_t,
		height: c.int32_t,
	),
	popup_done: proc "c" (
		data: rawptr,
		xdg_popup: ^xdg_popup,
	),
	repositioned: proc "c" (
		data: rawptr,
		xdg_popup: ^xdg_popup,
		token: c.uint32_t,
	),
}

xdg_popup_add_listener :: proc(
    xdg_popup: ^xdg_popup,
    listener: ^xdg_popup_listener,
    data: rawptr,
) -> c.int {

    return proxy_add_listener(cast(^wl_proxy)xdg_popup, cast(^Implementation)listener, data)
};

xdg_popup_destroy :: proc "c" (_xdg_popup: ^xdg_popup)
{
proxy_marshal_flags(
                cast(^wl_proxy)_xdg_popup,
		        0, nil, proxy_get_version(cast(^wl_proxy)_xdg_popup), WL_MARSHAL_FLAG_DESTROY);

}

xdg_popup_grab :: proc "c" (_xdg_popup: ^xdg_popup,seat : ^wl_seat,serial : c.uint32_t)
{
proxy_marshal_flags(
                cast(^wl_proxy)_xdg_popup,
		        1, nil, proxy_get_version(cast(^wl_proxy)_xdg_popup), 0, seat, serial);

}

xdg_popup_reposition :: proc "c" (_xdg_popup: ^xdg_popup,positioner : ^xdg_positioner,token : c.uint32_t)
{
proxy_marshal_flags(
                cast(^wl_proxy)_xdg_popup,
		        2, nil, proxy_get_version(cast(^wl_proxy)_xdg_popup), 0, positioner, token);

}

xdg_popup_requests: []wl_message = []wl_message{
	{ "destroy", "", raw_data([]^wl_interface{}) },
	{ "grab", "ou", raw_data([]^wl_interface{&wl_seat_interface, nil}) },
	{ "reposition", "ou", raw_data([]^wl_interface{&xdg_positioner_interface, nil}) },
}

xdg_popup_events: []wl_message = []wl_message{
	{ "configure", "iiii", raw_data([]^wl_interface{nil, nil, nil, nil}) },
	{ "popup_done", "", raw_data([]^wl_interface{}) },
	{ "repositioned", "u", raw_data([]^wl_interface{nil}) },
}

xdg_popup_interface: wl_interface = {}
@(init)
init_xdg_popup_interface :: proc "contextless" () {
	xdg_popup_interface = {
		"xdg_popup",
		6,
		3,
		&xdg_popup_requests[0],
		3,
		&xdg_popup_events[0],
	}
}

XDG_POPUP_ERROR_INVALID_GRAB :: 0

