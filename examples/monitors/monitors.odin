// Demonstrates the monitor query procedures. The interesting part is that they work before
// `k2.init`, which lets a program size its window from the display it is about to open on.
package karl2d_monitors_example

import k2 "../.."
import "core:fmt"

Monitor_Reading :: struct {
	size: [2]int,
	position: [2]int,
	scale: f32,
}

MAX_MONITORS :: 16

main :: proc() {
	// No k2.init yet. These work before the library is initialized, which is the point: you can
	// size the window from the display it is about to open on.
	monitor_count := k2.get_monitor_count()

	// Queried once and stored: each call to the getters does a fresh OS query, and on X11 that
	// opens a display connection, so this should not happen every frame.
	monitors: [MAX_MONITORS]Monitor_Reading
	stored_count := min(monitor_count, MAX_MONITORS)

	for i in 0..<stored_count {
		monitors[i] = {
			size = k2.get_monitor_size(i),
			position = k2.get_monitor_position(i),
			scale = k2.get_monitor_scale(i),
		}
	}

	// Half the primary monitor. Not every platform can report monitors (Wayland reports none), so
	// keep a fixed size to fall back on.
	window_width := 640
	window_height := 480

	if stored_count > 0 {
		size := monitors[0].size

		if size.x > 0 && size.y > 0 {
			window_width = size.x/2
			window_height = size.y/2
		}
	}

	k2.init(window_width, window_height, "Karl2D Monitors", options = {
		window_mode = .Windowed_Resizable,
	})

	for k2.update() {
		k2.clear(k2.LIGHT_BLUE)

		y: f32 = 20

		if stored_count == 0 {
			k2.draw_text("No monitors reported on this platform.", {20, y}, 32, k2.DARK_BLUE)
			y += 40
		}

		for i in 0..<stored_count {
			m := monitors[i]

			line := fmt.tprintf(
				"Monitor %v: size %vx%v, position (%v, %v), scale %v",
				i, m.size.x, m.size.y, m.position.x, m.position.y, m.scale,
			)

			k2.draw_text(line, {20, y}, 32, k2.DARK_BLUE)
			y += 40
		}

		k2.present()

		// fmt.tprintf above allocates using context.temp_allocator. Thrown away now that this
		// frame's text has been drawn.
		free_all(context.temp_allocator)
	}

	k2.shutdown()
}
