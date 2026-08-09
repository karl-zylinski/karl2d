package karl2d_hardware_cursors_example

import k2 "../.."
import "core:fmt"

pos: k2.Vec2

// Kept as Maybe so destroying the gauntlet can be recorded by clearing the handle. set_cursor
// takes a k2.Cursor, which a Custom_Cursor converts into implicitly, so a destroyed cursor needs
// no special case at the point where it's used - only where it's stored.
gauntlet: Maybe(k2.Custom_Cursor)
pointer: k2.Custom_Cursor

// What to show when the mouse isn't over the button. A single k2.Cursor is enough for this: it is
// either an OS shape or the gauntlet, and the union means both fit in the same variable rather than
// needing separate state for "which kind" and "which one".
selected: k2.Cursor

main :: proc() {
	init()
	for step() {}
	shutdown()
}

// A cursor covers as many physical pixels as its image has pixels: Karl2D does no automatic
// scaling, so a 64x64 cursor is the same size on screen as a 64x64 sprite you draw. That makes
// these look like a normal cursor at 200% display scaling and chunky at 100%. A game that wants
// the same apparent size everywhere should pick its cursor art based on `k2.get_window_scale()`,
// the same way the docs suggest handling resolution.
//
// create_custom_cursor doesn't retain the image, so it's fine to destroy it right after.
make_custom_cursor :: proc(png: []u8, hotspot: [2]int) -> k2.Custom_Cursor {
	image := k2.load_image_from_bytes(png)
	defer k2.destroy_image(image)
	return k2.create_custom_cursor(image, hotspot)
}

init :: proc() {
	k2.init(1280, 720, "Karl2D Hardware Cursor Example")

	c := make_custom_cursor(#load("gauntlet.png"), {4, 6})
	gauntlet = c
	pointer = make_custom_cursor(#load("pointer.png"), {4, 5})

	selected = c

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
		// Make it again if a right click destroyed it. Cursors are cheap to create and there is
		// nothing special about doing it partway through the game.
		c, ok := gauntlet.?
		if !ok {
			c = make_custom_cursor(#load("gauntlet.png"), {4, 6})
			gauntlet = c
		}

		selected = c
	}

	if k2.key_went_down(.X) {
		selected = k2.Cursor_Shape.Default
	}

	// Step through the cursor shapes the OS provides. Not every platform has every shape, so some
	// of them show the closest match instead. See the `Cursor_Shape` docs.
	if k2.key_went_down(.Space) {
		if shape, is_shape := selected.(k2.Cursor_Shape); is_shape {
			selected = k2.Cursor_Shape((int(shape) + 1) % len(k2.Cursor_Shape))
		} else {
			selected = k2.Cursor_Shape.Default
		}
	}

	if k2.mouse_button_went_down(.Right) {
		// Destroy the gauntlet and clear the handle so nothing reaches for it again. Karl2D would
		// notice a destroyed cursor and log rather than misbehave, but a game that keeps using one
		// gets that error every frame it does - clearing the handle is what actually stops it.
		if c, ok := gauntlet.?; ok {
			k2.destroy_custom_cursor(c)
			gauntlet = nil

			if selected == k2.Cursor(c) {
				selected = k2.Cursor_Shape.Default
			}
		}
	}

	// Set cursor at some point before present(), otherwise it may flicker.
	//
	// Hovering the button shows the pointer cursor whatever else is set, the way a game swaps the
	// cursor over a UI element without losing track of what it was showing before.
	if hovering {
		k2.set_cursor(pointer)
	} else {
		k2.set_cursor(selected)
	}

	k2.clear(k2.BLACK)
	k2.draw_rect(rect, hovering ? k2.DARK_RED : k2.RED)

	k2.draw_text("Space: step through the OS cursor shapes", {20, 20}, 30, k2.WHITE)
	k2.draw_text("X: default OS cursor", {20, 55}, 30, k2.GRAY)
	k2.draw_text("Right click: destroy the gauntlet cursor", {20, 90}, 30, k2.GRAY)

	if gauntlet == nil {
		k2.draw_text("G: create the gauntlet cursor again", {20, 125}, 30, k2.YELLOW)
	} else {
		k2.draw_text("G: gauntlet cursor", {20, 125}, 30, k2.GRAY)
	}

	if shape, is_shape := selected.(k2.Cursor_Shape); is_shape {
		label := fmt.tprintf("Cursor_Shape.%v", shape)
		k2.draw_text(label, {20, 175}, 40, k2.YELLOW)
	}

	k2.present()

	free_all(context.temp_allocator)
	return true
}

shutdown :: proc() {
	k2.shutdown()
}
