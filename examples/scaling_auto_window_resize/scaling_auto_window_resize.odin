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
	
	// We change the windwo size just after creation so the window scale gets taken into account.
	//
	// Perhaps we should change the library so that you can query the scale before creating the
	// window.
	k2.set_screen_size(int(f32(width) * k2.get_window_scale()), int(f32(height)*k2.get_window_scale()))

	for k2.update() {
		events := k2.get_events()

		for event in events {
			#partial switch e in event {
			case k2.Event_Window_Scale_Changed:
				// Karl2D does not automatically resize the window when the scale changes. Instead
				// you can do that yourself by looking for this event.
				k2.set_screen_size(int(f32(width) * e.scale), int(f32(height) * e.scale))

			case k2.Event_Screen_Resize:
				// When a window is resized, then it is good if we update our local `width` and
				// `height` variables so that they store a value without the scale. We remove the
				// scale so that later calls to `k2.set_window_size` can scale the size properly
				// using any future scale.
				scl := k2.get_window_scale()
				width = int(f32(e.width) / scl)
				height = int(f32(e.height) / scl)
			}
		}

		k2.clear(k2.LIGHT_BLUE)

		camera := k2.Camera {
			// Zoom the game up using the window scale to compensate for the extra size of the window.
			zoom = k2.get_window_scale(),
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
