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
	k2.set_window_size(int(f32(width) * k2.get_window_scale()), int(f32(height)*k2.get_window_scale()))

	for k2.update() {
		events := k2.get_events()

		for event in events {
			#partial switch e in event {
			case k2.Event_Window_Scale_Changed:
				k2.set_window_size(int(f32(width) * e.scale), int(f32(height) * e.scale))

			case k2.Event_Resize:
				scl := k2.get_window_scale()
				width = int(f32(e.width) / scl)
				height = int(f32(e.height) / scl)
			}
		}

		k2.clear(k2.LIGHT_BLUE)
		
		camera := k2.Camera {
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
