// Demonstrates the split of `k2.init` into `init_platform`, `open_window`, `init_rendering` and
// `init_sound`. Queries the connected monitors right after `init_platform`, before a window
// exists, and uses that to pick a window size based on the primary monitor.
package karl2d_monitors_example

import k2 "../.."
import "core:fmt"

init :: proc() {
	k2.init_platform()

	monitor_count := k2.get_monitor_count()
	fmt.printfln("Monitor count: %v", monitor_count)

	for i in 0..<monitor_count {
		fmt.printfln(
			"Monitor %v: size %v, position %v, scale %v",
			i,
			k2.get_monitor_size(i),
			k2.get_monitor_position(i),
			k2.get_monitor_scale(i),
		)
	}

	// Half the primary monitor's size, so the window comfortably fits on screen. Not every platform
	// can report monitors: Wayland reports none at all right now, see
	// `platform_linux_window_wayland.odin`. So check the count before asking, and keep a fixed size
	// to fall back on.
	window_width := 640
	window_height := 480

	if monitor_count > 0 {
		primary_size := k2.get_monitor_size(0)

		if primary_size.x > 0 && primary_size.y > 0 {
			window_width = primary_size.x/2
			window_height = primary_size.y/2
		}
	}

	k2.open_window(
		window_width,
		window_height,
		"Karl2D Monitors",
		options = { window_mode = .Windowed_Resizable },
	)

	k2.init_rendering()
	k2.init_sound()
}

step :: proc() -> bool {
	if !k2.update() {
		return false
	}

	k2.clear(k2.DARK_GRAY)

	monitor_count := k2.get_monitor_count()
	y: f32 = 20

	k2.draw_text(fmt.tprintfln("Monitor count: %v", monitor_count), {20, y}, 28, k2.WHITE)
	y += 40

	for i in 0..<monitor_count {
		line := fmt.tprintfln(
			"Monitor %v: size %v, position %v, scale %v",
			i,
			k2.get_monitor_size(i),
			k2.get_monitor_position(i),
			k2.get_monitor_scale(i),
		)

		k2.draw_text(line, {20, y}, 28, k2.LIGHT_GREEN)
		y += 34
	}

	k2.present()

	// `fmt.tprintfln` above allocates using `context.temp_allocator`. Those allocations are not
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
