// This example shows how to make your window resize automatically when the scale or "DPI setting"
// changes. That setting may change when you move the window to another monitor that has a different
// setting, or when you explicitly change the setting while the program is running.
//
// This is an "advanced example". Not everybody needs this. Many games are fine with the user being
// able to pick a resolution, with optional UI scale.
//
// Note: This example currently only works as expected on Windows. I am still adding the proper DPI
// scaling settings for the other platforms.
package karl2d_scaling_example

import k2 "../.."
import "core:fmt"

_ :: fmt

Rect :: k2.Rect
Vec2 :: k2.Vec2

main :: proc() {
	width := 1000
	height := 1000
	k2.init(width, height, "Karl2D: Auto resize when DPI changes", options = { window_mode = .Windowed_Resizable})

	for k2.update() {
		k2.clear(k2.LIGHT_BLUE)
		
		camera := k2.Camera {
			// Zoom the game up using the window scale to compensate for the extra size of the window.
			zoom = 1,
		}

		k2.set_camera(camera)
		k2.draw_rect({0, 0, 500, 500}, k2.DARK_GREEN)
		k2.draw_text("500x500", {10, 10}, 40, k2.WHITE)
		k2.draw_circle({250, 250}, 100, k2.WHITE)
		k2.present()
		free_all(context.temp_allocator)
	}

	k2.shutdown()
}
