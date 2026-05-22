package wayland

import "core:c"

foreign import lib_cursor "system:wayland-cursor"

// wl_shm — needed to load a cursor theme

SHM :: struct {
	using proxy: Proxy,
}

shm_interface := Interface {
	"wl_shm",
	2,
	1,
	raw_data([]Message{{"create_pool", "nhi", raw_data([]^Interface{nil, nil, nil})}}),
	1,
	raw_data([]Message{{"format", "u", raw_data([]^Interface{nil})}}),
}

// libwayland-cursor types and bindings

Cursor_Image :: struct {
	width:     u32,
	height:    u32,
	hotspot_x: u32,
	hotspot_y: u32,
	delay:     u32,
}

Cursor :: struct {
	image_count: u32,
	images:      [^]^Cursor_Image,
	name:        cstring,
}

Cursor_Theme :: struct {}

@(default_calling_convention = "c", link_prefix = "wl_")
foreign lib_cursor {
	cursor_theme_load    :: proc(name: cstring, size: c.int, shm: ^SHM) -> ^Cursor_Theme ---
	cursor_theme_destroy :: proc(theme: ^Cursor_Theme) ---
	cursor_theme_get_cursor :: proc(theme: ^Cursor_Theme, name: cstring) -> ^Cursor ---
	cursor_image_get_buffer :: proc(image: ^Cursor_Image) -> ^Buffer ---
}