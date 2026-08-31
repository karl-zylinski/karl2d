// Lists the connected monitors and their sizes.
//
// Split into `init`, `step` and `shutdown` so it also builds for web, where the browser drives the
// frame loop and there is no place for a `for` loop of our own.
package karl2d_monitors_example

import k2 "../.."
import "core:fmt"

init :: proc() {
	k2.init(1000, 600, "Karl2D Monitors")
}

step :: proc() -> bool {
	if !k2.update() {
		return false
	}

	k2.clear(k2.DARK_GRAY)

	monitor_count := k2.get_monitor_count()
	k2.draw_text(fmt.tprintf("Monitors: %v", monitor_count), {20, 20}, 30, k2.WHITE)

	// Drag the window to another monitor and watch this follow it. This is the one you usually
	// want, since it is the display the player is looking at.
	current := k2.get_window_monitor()

	y: f32 = 70

	for i in 0..<monitor_count {
		line := fmt.tprintf(
			"%v: %v x %v at %v%v",
			i,
			k2.get_monitor_width(i),
			k2.get_monitor_height(i),
			k2.get_monitor_position(i),
			i == current ? "  <- window is here" : "",
		)

		k2.draw_text(line, {20, y}, 24, i == current ? k2.YELLOW : k2.LIGHT_GREEN)
		y += 32
	}

	if monitor_count == 0 {
		k2.draw_text("This platform does not report monitors.", {20, y}, 24, k2.RED)
	}

	k2.present()

	// `fmt.tprintf` above allocates using `context.temp_allocator`. Those allocations are not
	// needed for more than a frame, so they can be thrown away now.
	free_all(context.temp_allocator)
	return true
}

shutdown :: proc() {
	k2.shutdown()
}

// This is not run by the web version, but it makes this program also work on non-web!
main :: proc() {
	init()
	for step() {}
	shutdown()
}
