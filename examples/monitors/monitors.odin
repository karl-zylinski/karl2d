package karl2d_monitors_example

import k2 "../.."
import "core:fmt"

main :: proc() {
	init()
	for step() {}
	shutdown()
}

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

	window_monitor := k2.get_window_monitor()
	y: f32 = 70

	for i in 0..<monitor_count {
		line := fmt.tprintf(
			"%v: %v x %v at %v%v",
			i,
			k2.get_monitor_width(i),
			k2.get_monitor_height(i),
			k2.get_monitor_position(i),
			i == window_monitor ? "  <- window is here" : "",
		)

		k2.draw_text(line, {20, y}, 24, i == window_monitor ? k2.YELLOW : k2.LIGHT_GREEN)
		y += 32
	}

	k2.present()
	free_all(context.temp_allocator)
	return true
}

shutdown :: proc() {
	k2.shutdown()
}
