package karl2d_hardware_cursor_example

import k2 "../.."
import "core:image/png"
import "core:math/linalg"
import "core:slice"

pos: k2.Vec2
default: k2.Cursor
pointer: k2.Cursor

Cursor :: enum {
	DEFAULT,
	POINTER,
}
current_cursor: Cursor

main :: proc() {
	init()
	for step() {}
	shutdown()
}

init :: proc() {
	k2.init(1280, 720, "Karl2D Hardware Cursor Example")

	img, img_err := png.load_from_file("default.png")
	if img_err == nil {
		defer png.destroy(img)
		pixels := slice.reinterpret([]k2.Color, img.pixels.buf[:])
		default = k2.create_cursor(pixels, img.width, img.height, {7, 11})
	}

	img, img_err = png.load_from_file("pointer.png")
	if img_err == nil {
		defer png.destroy(img)
		pixels := slice.reinterpret([]k2.Color, img.pixels.buf[:])
		pointer = k2.create_cursor(pixels, img.width, img.height, {8, 10})
	}

	pos = {f32(k2.get_screen_width()) / 2, f32(k2.get_screen_height()) / 2}
}

step :: proc() -> bool {
	if !k2.update() {
		return false
	}

	current_cursor = .DEFAULT

	movement: k2.Vec2
	if k2.key_is_held(.Left)  do movement.x -= 1
	if k2.key_is_held(.Right) do movement.x += 1
	if k2.key_is_held(.Up)    do movement.y -= 1
	if k2.key_is_held(.Down)  do movement.y += 1
	pos += linalg.normalize0(movement) * k2.get_frame_time() * 400

	mouse_pos := k2.get_mouse_position()
	rect := k2.Rect{pos.x, pos.y, 50, 50}
	if  mouse_pos.x >= rect.x &&
		mouse_pos.x <= rect.x + rect.w &&
		mouse_pos.y >= rect.y &&
		mouse_pos.y <= rect.y + rect.h {
		current_cursor = .POINTER
	}

	// Set cursor at some point before present(), otherwise it flickers.
	set_cursor(current_cursor)

	if k2.mouse_button_went_down(.Right) {
		c: k2.Cursor
		switch current_cursor {
		case .DEFAULT: c = default
		case .POINTER: c = pointer
		}
		k2.destroy_cursor(c)
	}

	{ k2.clear(k2.BLACK)
		k2.draw_rect(rect, k2.DARK_GRAY)
	} k2.present()

	free_all(context.temp_allocator)
	return true
}

shutdown :: proc() {
	k2.shutdown()
}

set_cursor :: proc(cursor: Cursor) {
	c: k2.Cursor
	switch cursor {
	case .DEFAULT:
		c = default
	case .POINTER:
		c = pointer
	}
	k2.set_cursor(c)
}
