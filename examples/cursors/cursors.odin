// This example lets you choose between the standard OS cursors as well as a loaded custom cursor.
package karl2d_cursors_example

import k2 "../.."
import "core:fmt"

pos: k2.Vec2

// Set back to CUSTOM_CURSOR_NONE when destroyed, so the rest of the code can tell it is gone.
gauntlet: k2.Custom_Cursor
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
create_custom_cursor :: proc(image_data: []u8, hotspot: [2]int) -> k2.Custom_Cursor {
	image := k2.load_image_from_bytes(image_data)
	custom_cursor := k2.create_custom_cursor(image, hotspot)
	k2.destroy_image(image)
	return custom_cursor
}

// Can be used in two places: at startup and again after a right click destroys it.
create_gauntlet_cursor :: proc() -> k2.Custom_Cursor {
	return create_custom_cursor(#load("gauntlet.png"), {4, 6})
}

init :: proc() {
	k2.init(1280, 720, "Karl2D Cursors Example")

	gauntlet = create_gauntlet_cursor()
	pointer = create_custom_cursor(#load("pointer.png"), {4, 5})
	selected = gauntlet

	pos = {f32(k2.get_screen_width()) / 2, f32(k2.get_screen_height()) / 2}
}

step :: proc() -> bool {
	if !k2.update() {
		return false
	}

	mouse_pos := k2.get_mouse_position()
	rect := k2.Rect{pos.x, pos.y, 50, 50}

	hovering := mouse_pos.x >= rect.x &&
	            mouse_pos.x <= rect.x + rect.w &&
	            mouse_pos.y >= rect.y &&
	            mouse_pos.y <= rect.y + rect.h

	if k2.key_went_down(.G) {
		if gauntlet == k2.CUSTOM_CURSOR_NONE {
			gauntlet = create_gauntlet_cursor()
		}

		selected = gauntlet
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
		if gauntlet != k2.CUSTOM_CURSOR_NONE {
			if selected == gauntlet {
				selected = .Default
			}

			k2.destroy_custom_cursor(gauntlet)
			gauntlet = k2.CUSTOM_CURSOR_NONE
		}
	}

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

	if gauntlet == k2.CUSTOM_CURSOR_NONE {
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
