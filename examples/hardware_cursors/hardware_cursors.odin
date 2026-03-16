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

	gauntlet = k2.create_cursor(#load("gauntlet.png"), {7, 11})
	pointer  = k2.create_cursor(#load("pointer.png"), {8, 10})

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
	if  mouse_pos.x >= rect.x &&
		mouse_pos.x <= rect.x + rect.w &&
		mouse_pos.y >= rect.y &&
		mouse_pos.y <= rect.y + rect.h {
		current_cursor = .POINTER
		btn_color = k2.DARK_RED
	} else if current_cursor == .POINTER {
		current_cursor = .GAUNTLET
	}

	if k2.key_went_down(.X) {
		// Use "Cursor(0)" to set the cursor to the default OS arrow.
		current_cursor = .OS_ARROW
	}

	if k2.mouse_button_went_down(.Right) {
		c: k2.Cursor
		#partial switch current_cursor {
		case .GAUNTLET: c = gauntlet
		case .POINTER:  c = pointer
		}
		// This demo intentionally doesn't remove the local cursors from some list you may have.
		// But that is something you should do, so that you don't send a destroyed cursor to k2d.
		k2.destroy_cursor(c)
	}

	c: k2.Cursor
	switch current_cursor {
	case .OS_ARROW: c = k2.DEFAULT_CURSOR
	case .GAUNTLET: c = gauntlet
	case .POINTER:  c = pointer
	}
	
	// Set cursor at some point before present(), otherwise it may flicker.
	k2.set_cursor(c)

	{ k2.clear(k2.BLACK)
		k2.draw_rect(rect, btn_color)
	} k2.present()

	free_all(context.temp_allocator)
	return true
}

shutdown :: proc() {
	k2.shutdown()
}
