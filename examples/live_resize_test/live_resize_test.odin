// This example demonstrates live window resize rendering on macOS and Windows.
// Without set_live_resize_callback, the window would freeze during resize.
// With it, the content updates continuously while resizing.

package live_resize_test

import k2 "../.."
import "core:fmt"
import "core:math"

main :: proc() {
	k2.init(1280, 720, "Karl2D Live Resize Test", k2.Init_Options{window_mode = .Windowed_Resizable})

	// Enable live resize rendering (macOS and Windows - no effect on other platforms)
	k2.set_live_resize_callback(draw_frame)

	frame_count := 0
	for k2.update() {
		draw_frame()
		frame_count += 1
	}

	k2.shutdown()
}

draw_frame :: proc() {
	// Clear with an animated color
	time := k2.get_time()
	r := u8((math.sin(time) * 0.5 + 0.5) * 255)
	g := u8((math.cos(time * 0.7) * 0.5 + 0.5) * 255)
	b := u8((math.sin(time * 1.3) * 0.5 + 0.5) * 255)
	k2.clear({r, g, b, 255})

	// Draw some text
	width := k2.get_screen_width()
	height := k2.get_screen_height()

	k2.draw_text(
		fmt.tprintf("Window Size: %d x %d", width, height),
		{10, 10},
		40,
		k2.WHITE,
	)

	k2.draw_text(
		"Try resizing this window!",
		{10, 60},
		30,
		k2.WHITE,
	)

	k2.draw_text(
		"The background color and size text update continuously.",
		{10, 100},
		25,
		k2.WHITE,
	)

	// Draw a moving rectangle
	center_x := f32(width) / 2
	center_y := f32(height) / 2
	offset_x := math.sin(f32(time)) * 100
	offset_y := math.cos(f32(time)) * 100

	k2.draw_rect({center_x + offset_x - 50, center_y + offset_y - 50, 100, 100}, k2.YELLOW)

	k2.present()

	// Clear temp allocator used by fmt.tprintf
	free_all(context.temp_allocator)
}
