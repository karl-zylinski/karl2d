package karl2d_hardware_cursors_example

import k2 "../.."
import "core:fmt"

pos: k2.Vec2

// A Maybe so that destroying the gauntlet can be recorded by clearing the handle.
gauntlet: Maybe(k2.Custom_Cursor)
pointer: k2.Custom_Cursor

// What to show when the mouse isn't over the button. A k2.Cursor holds either kind, so this needs
// no separate state for which kind it currently is.
selected: k2.Cursor

main :: proc() {
	init()
	for step() {}
	shutdown()
}

// A cursor covers as many physical pixels as its image has, with no automatic scaling. These are
// sized for 200% display scaling, so they look chunky at 100%. Pick the art based on
// `k2.get_window_scale()` to get the same apparent size everywhere.
make_custom_cursor :: proc(png: []u8, hotspot: [2]int) -> k2.Custom_Cursor {
	image := k2.load_image_from_bytes(png)
	defer k2.destroy_image(image)
	return k2.create_custom_cursor(image, hotspot)
}

// Made in two places: at startup and again after a right click destroys it.
make_gauntlet :: proc() -> k2.Custom_Cursor {
	return make_custom_cursor(#load("gauntlet.png"), {4, 6})
}

init :: proc() {
	k2.init(1280, 720, "Karl2D Hardware Cursor Example")

	c := make_gauntlet()
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
		// Make it again if a right click destroyed it.
		c, ok := gauntlet.?
		if !ok {
			c = make_gauntlet()
			gauntlet = c
		}

		selected = c
	}

	if k2.key_went_down(.X) {
		selected = k2.Standard_Cursor.Default
	}

	// Not every platform has all the standard cursors; some show the closest match.
	if k2.key_went_down(.Space) {
		if standard, is_standard := selected.(k2.Standard_Cursor); is_standard {
			selected = k2.Standard_Cursor((int(standard) + 1) % len(k2.Standard_Cursor))
		} else {
			selected = k2.Standard_Cursor.Default
		}
	}

	if k2.mouse_button_went_down(.Right) {
		// Using a destroyed cursor logs rather than misbehaves, but it logs every frame you do.
		// Clearing the handle is what stops that.
		if c, ok := gauntlet.?; ok {
			k2.destroy_custom_cursor(c)
			gauntlet = nil

			if selected == k2.Cursor(c) {
				selected = k2.Standard_Cursor.Default
			}
		}
	}

	// Set the cursor before present(), otherwise it may flicker. Hovering shows the pointer without
	// disturbing `selected`, the way a game swaps the cursor over a UI element.
	if hovering {
		k2.set_cursor(pointer)
	} else {
		k2.set_cursor(selected)
	}

	k2.clear(k2.BLACK)
	k2.draw_rect(rect, hovering ? k2.DARK_RED : k2.RED)

	k2.draw_text("Space: step through the standard OS cursors", {20, 20}, 30, k2.WHITE)
	k2.draw_text("X: default OS cursor", {20, 55}, 30, k2.GRAY)
	k2.draw_text("Right click: destroy the gauntlet cursor", {20, 90}, 30, k2.GRAY)

	if gauntlet == nil {
		k2.draw_text("G: create the gauntlet cursor again", {20, 125}, 30, k2.YELLOW)
	} else {
		k2.draw_text("G: gauntlet cursor", {20, 125}, 30, k2.GRAY)
	}

	if standard, is_standard := selected.(k2.Standard_Cursor); is_standard {
		label := fmt.tprintf("Standard_Cursor.%v", standard)
		k2.draw_text(label, {20, 175}, 40, k2.YELLOW)
	}

	k2.present()

	free_all(context.temp_allocator)
	return true
}

shutdown :: proc() {
	k2.shutdown()
}
