package karl2d_hardware_cursors_example

import k2 "../.."
import "core:fmt"

pos: k2.Vec2
gauntlet: k2.Cursor
pointer: k2.Cursor

Cursor :: enum {
	OS_ARROW,
	GAUNTLET,
	POINTER,
	SHAPE,
}
current_cursor: Cursor
current_shape: k2.Cursor_Shape

main :: proc() {
	init()
	for step() {}
	shutdown()
}

init :: proc() {
	k2.init(1280, 720, "Karl2D Hardware Cursor Example")

	// A cursor covers as many physical pixels as its image has pixels: Karl2D does no automatic
	// scaling, so a 64x64 cursor is the same size on screen as a 64x64 sprite you draw. That makes
	// these look like a normal cursor at 200% display scaling and chunky at 100%. A game that
	// wants the same apparent size everywhere should pick its cursor art based on
	// `k2.get_window_scale()`, the same way the docs suggest handling resolution.
	//
	// create_cursor doesn't retain the image, so it's fine to destroy it right after.
	gauntlet_image := k2.load_image_from_bytes(#load("gauntlet.png"))
	gauntlet = k2.create_cursor(gauntlet_image, {4, 6})
	k2.destroy_image(gauntlet_image)

	pointer_image := k2.load_image_from_bytes(#load("pointer.png"))
	pointer = k2.create_cursor(pointer_image, {4, 5})
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

	// Step through the cursor shapes the OS provides. Not every platform has every shape, so some
	// of them show the closest match instead. See the `Cursor_Shape` docs.
	if k2.key_went_down(.Space) {
		if current_cursor == .SHAPE {
			current_shape = k2.Cursor_Shape((int(current_shape) + 1) % len(k2.Cursor_Shape))
		} else {
			current_cursor = .SHAPE
			current_shape = .Default
		}
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

	// Set cursor at some point before present(), otherwise it may flicker.
	switch current_cursor {
	case .OS_ARROW: k2.set_cursor(nil)
	case .GAUNTLET: k2.set_cursor(gauntlet)
	case .POINTER:  k2.set_cursor(pointer)
	case .SHAPE:    k2.set_cursor_shape(current_shape)
	}

	k2.clear(k2.BLACK)
	k2.draw_rect(rect, btn_color)

	k2.draw_text("Space: step through the OS cursor shapes", {20, 20}, 30, k2.WHITE)
	k2.draw_text("X: default OS cursor", {20, 55}, 30, k2.GRAY)
	k2.draw_text("Right click: destroy the active cursor", {20, 90}, 30, k2.GRAY)

	if current_cursor == .SHAPE {
		label := fmt.tprintf("Cursor_Shape.%v", current_shape)
		k2.draw_text(label, {20, 140}, 40, k2.YELLOW)
	}

	k2.present()

	free_all(context.temp_allocator)
	return true
}

shutdown :: proc() {
	k2.shutdown()
}
