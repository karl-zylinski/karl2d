// Draws a scene in three layers: background, middle and foreground. With depth testing enabled,
// the z value set with `set_z` decides which layer ends up in front. Within a single layer
// (things at the same z), the drawing order still decides what's on top, just like when depth
// testing is off.
//
// The layers are drawn in a deliberately "wrong" order (foreground first, background last) to
// show that the z value, not the drawing order, decides what ends up in front across layers.
package karl2d_depth_test

import k2 "../.."

init :: proc() {
	k2.init(1280, 720, "Depth test", options = { depth_test = true })
}

step :: proc() -> bool {
	if !k2.update() {
		return false
	}

	k2.clear(k2.LIGHT_BLUE)

	// FOREGROUND (z == 1). Drawn first, but ends up in front of everything.
	k2.set_z(1)
	k2.draw_rect({100, 400, 300, 150}, k2.DARK_GREEN)
	k2.draw_rect({700, 350, 250, 200}, k2.DARK_GREEN)
	k2.draw_circle({1050, 500}, 80, k2.DARK_GRAY)

	// MIDDLE (z == 0, the default). Three overlapping items at the same z: the drawing order
	// decides between them, just like when depth testing is off.
	k2.set_z(0)
	k2.draw_rect({250, 300, 120, 200}, k2.RED)
	k2.draw_rect({330, 340, 120, 160}, k2.YELLOW)
	k2.draw_circle({420, 320}, 60, k2.WHITE)

	// BACKGROUND (z == -1). Drawn last, but ends up behind everything.
	k2.set_z(-1)
	k2.draw_rect({0, 450, 1280, 270}, k2.GREEN)
	k2.draw_circle({300, 250}, 100, k2.GRAY)
	k2.draw_circle({500, 280}, 130, k2.LIGHT_GRAY)

	// Note that depth testing does not mix well with transparency: if you draw something
	// semi-transparent at a low z after drawing something at a higher z, then the overlapping
	// part is skipped completely instead of showing through the thing in front. So transparent
	// things still need to be drawn in order, background first. Within a single layer this is
	// not a problem, since things at the same z use the drawing order.

	k2.present()
	free_all(context.temp_allocator)
	return true
}

shutdown :: proc() {
	k2.shutdown()
}

main :: proc() {
	init()
	for step() {}
	shutdown()
}
