package karl2d_hardware_cursors_example

import k2 "../.."

pos: k2.Vec2
gauntlet: k2.Cursor
pointer: k2.Cursor

Cursor :: enum {
	OS_ARROW,
	GAUNTLET,
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

	// create_cursor doesn't retain the image, so it's fine to destroy it right after.
	gauntlet_image := k2.load_image_from_bytes(#load("gauntlet.png"))
	gauntlet = k2.create_cursor(gauntlet_image, {2, 3})
	k2.destroy_image(gauntlet_image)

	pointer_image := k2.load_image_from_bytes(#load("pointer.png"))
	pointer = k2.create_cursor(pointer_image, {2, 3})
	k2.destroy_image(pointer_image)

	current_cursor = .GAUNTLET

	pos = {f32(k2.get_screen_width()) / 2, f32(k2.get_screen_height()) / 2}
}

step :: proc() -> bool {
	if !k2.update() {
		return false
	}

	btn_color := k2.RED
	mouse_pos := k2.get_mouse_position()
	rect := k2.Rect{pos.x, pos.y, 50, 50}
	if mouse_pos.x >= rect.x &&
		mouse_pos.x <= rect.x + rect.w &&
		mouse_pos.y >= rect.y &&
		mouse_pos.y <= rect.y + rect.h {
		current_cursor = .POINTER
		btn_color = k2.DARK_RED
	} else if current_cursor == .POINTER {
		current_cursor = .GAUNTLET
	}

	if k2.key_went_down(.X) {
		// Pass `nil` to k2.set_cursor to use the default OS arrow.
		current_cursor = .OS_ARROW
	}

	if k2.mouse_button_went_down(.Right) {
		c: Maybe(k2.Cursor)
		#partial switch current_cursor {
		case .GAUNTLET: c = gauntlet
		case .POINTER:  c = pointer
		}
		// This demo intentionally doesn't remove the local cursors from some list you may have.
		// destroy_cursor and set_cursor detect a stale handle and log an error rather than
		// misbehaving, but you should still stop using one once it's destroyed.
		if to_destroy, ok := c.?; ok {
			k2.destroy_cursor(to_destroy)
		}
	}

	c: Maybe(k2.Cursor)
	switch current_cursor {
	case .OS_ARROW: c = nil
	case .GAUNTLET: c = gauntlet
	case .POINTER:  c = pointer
	}

	// Set cursor at some point before present(), otherwise it may flicker.
	k2.set_cursor(c)

	k2.clear(k2.BLACK)
	k2.draw_rect(rect, btn_color)
	k2.present()

	free_all(context.temp_allocator)
	return true
}

shutdown :: proc() {
	k2.shutdown()
}
