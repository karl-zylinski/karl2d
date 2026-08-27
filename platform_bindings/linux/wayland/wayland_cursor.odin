package wayland

import "core:c"

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

cursor_theme_load: proc "c" (name: cstring, size: c.int, shm: ^SHM) -> ^Cursor_Theme

cursor_theme_destroy: proc "c" (theme: ^Cursor_Theme)

cursor_theme_get_cursor: proc "c" (theme: ^Cursor_Theme, name: cstring) -> ^Cursor

cursor_image_get_buffer: proc "c" (image: ^Cursor_Image) -> ^Buffer