package karl2d_hardware_cursors_example

import k2 "../.."
import "core:fmt"

pos: k2.Vec2

// Kept as Maybe so that destroying one can be recorded by clearing the handle. set_cursor takes a
// Maybe(Cursor) already, and nil means the OS default, so a destroyed cursor needs no special case
// at the point where it's used.
gauntlet: Maybe(k2.Cursor)
pointer: Maybe(k2.Cursor)

// What to show when the mouse isn't over the button.
Base_Cursor :: enum {
	Gauntlet,
	Os_Arrow,
	Shape,
}

base: Base_Cursor
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

	pos = {f32(k2.get_screen_width()) / 2, f32(k2.get_screen_height()) / 2}
}

step :: proc() -> bool {
	if !k2.update() {
		return false
	}

	mouse_pos := k2.get_mouse_position()
	rect := k2.Rect{pos.x, pos.y, 50, 50}

	hovering := mouse_pos.x >= rect.x && mouse_pos.x <= rect.x + rect.w &&
		mouse_pos.y >= rect.y && mouse_pos.y <= rect.y + rect.h

	if k2.key_went_down(.G) {
		base = .Gauntlet
	}

	if k2.key_went_down(.X) {
		base = .Os_Arrow
	}

	// Step through the cursor shapes the OS provides. Not every platform has every shape, so some
	// of them show the closest match instead. See the `Cursor_Shape` docs.
	if k2.key_went_down(.Space) {
		if base == .Shape {
			current_shape = k2.Cursor_Shape((int(current_shape) + 1) % len(k2.Cursor_Shape))
		} else {
			base = .Shape
			current_shape = .Default
		}
	}

	if k2.mouse_button_went_down(.Right) {
		// Destroy whichever custom cursor is on screen, and clear the handle so nothing reaches
		// for it again. Karl2D would notice a destroyed cursor and log rather than misbehave, but
		// a game that keeps using one gets that error every frame it does - clearing the handle is
		// what actually stops it. A nil Maybe(Cursor) is just the OS default, so pressing G after
		// destroying the gauntlet leaves you on the default cursor rather than erroring.
		destroy_target := hovering ? &pointer : &gauntlet

		if c, ok := destroy_target.?; ok {
			k2.destroy_cursor(c)
			destroy_target^ = nil
		}
	}

	// Set cursor at some point before present(), otherwise it may flicker.
	//
	// Hovering the button shows the pointer cursor whatever else is set, the way a game swaps the
	// cursor over a UI element without losing track of what it was showing before.
	if hovering {
		k2.set_cursor(pointer)
	} else {
		switch base {
		case .Gauntlet: k2.set_cursor(gauntlet)
		case .Os_Arrow: k2.set_cursor(nil)
		case .Shape:    k2.set_cursor_shape(current_shape)
		}
	}

	k2.clear(k2.BLACK)
	k2.draw_rect(rect, hovering ? k2.DARK_RED : k2.RED)

	k2.draw_text("Space: step through the OS cursor shapes", {20, 20}, 30, k2.WHITE)
	k2.draw_text("G: gauntlet cursor    X: default OS cursor", {20, 55}, 30, k2.GRAY)
	k2.draw_text("Right click: destroy the cursor on screen", {20, 90}, 30, k2.GRAY)

	if base == .Shape {
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
