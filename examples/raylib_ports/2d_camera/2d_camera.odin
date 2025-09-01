// This is a port of https://github.com/raysan5/raylib/blob/master/examples/core/core_2d_camera.c

package raylib_example_2d_camera

import k2 "../../.."
import "core:math/rand"
import "core:math"
import "core:log"

MAX_BUILDINGS :: 100
SCREEN_WIDTH :: 800
SCREEN_HEIGHT :: 450

main :: proc() {
	context.logger = log.create_console_logger()
	k2.init(SCREEN_WIDTH, SCREEN_HEIGHT, "Karl2D: 2d camera (raylib [core] example - 2d camera)")
	k2.set_window_position(500, 100)

	player := k2.Rect { 400, 280, 40, 40 }
	buildings: [MAX_BUILDINGS]k2.Rect
	building_colors: [MAX_BUILDINGS]k2.Color

	spacing: f32

	for i in 0..<MAX_BUILDINGS {
		w := rand.float32_range(50, 200)
		h := rand.float32_range(100, 800)

		buildings[i] = {
			x = -6000 + spacing,
			y = SCREEN_HEIGHT - 130 - h,
			w = w,
			h = h,
		}

		spacing += w

		building_colors[i] = {
			u8(rand.int_max(40) + 200),
			u8(rand.int_max(40) + 200),
			u8(rand.int_max(50) + 200),
			255,
		}
	}

	camera := k2.Camera {
		origin = { SCREEN_WIDTH / 2, SCREEN_HEIGHT / 2},
		zoom = 1,
	}

	for !k2.close_window_wanted() {
		k2.process_events()

		if k2.key_is_held(.Right) { player.x += 2 }
		else if k2.key_is_held(.Left) { player.x -= 2 }

		camera.target = { player.x + 20, player.y + 20 }

		if k2.key_is_held(.A) { camera.rotation -= 1 }
		else if k2.key_is_held(.S)  { camera.rotation += 1 }

		if camera.rotation > 40 { camera.rotation = 40 }
		else if camera.rotation < -40 { camera.rotation = -40 }

		camera.zoom = math.exp(math.log(camera.zoom, math.E) + f32(k2.get_mouse_wheel_delta() * 0.1))

		if camera.zoom > 3 { camera.zoom = 3 }
		else if camera.zoom < 0.1 { camera.zoom = 0.1 }

		if k2.key_went_down(.R) {
			camera.zoom = 1
			camera.rotation = 0
		}

		k2.clear({ 245, 245, 245, 255 })
		k2.set_camera(camera)
		k2.draw_rect({-6000, 320, 13000, 8000}, k2.DARKGRAY)

		for i in 0..<MAX_BUILDINGS {
			k2.draw_rect(buildings[i], building_colors[i])
		}

		k2.draw_rect(player, k2.RED)
		k2.draw_line({camera.target.x, -SCREEN_HEIGHT * 10}, {camera.target.x, SCREEN_HEIGHT * 10 }, 1, k2.GREEN)
		k2.draw_line({-SCREEN_WIDTH*10, camera.target.y}, {SCREEN_WIDTH*10, camera.target.y}, 1, k2.GREEN)

		k2.set_camera(nil)
		k2.draw_text("SCREEN AREA", {640, 10}, 20, k2.RED)

		k2.draw_rect({0, 0, SCREEN_WIDTH, 5}, k2.RED)
		k2.draw_rect({0, 5, 5, SCREEN_HEIGHT - 10}, k2.RED)
		k2.draw_rect({SCREEN_WIDTH - 5, 5, 5, SCREEN_HEIGHT - 10}, k2.RED)
		k2.draw_rect({0, SCREEN_HEIGHT - 5, SCREEN_WIDTH, 5}, k2.RED)

		k2.draw_rect({10, 10, 250, 113}, {102, 191, 255, 128})
		k2.draw_rect_outline({10, 10, 250, 113}, 1, k2.BLUE)

		k2.draw_text("Free 2d camera controls:", {20, 20}, 10, k2.BLACK)
		k2.draw_text("- Right/Left to move Offset", {40, 40}, 10, k2.DARKGRAY)
		k2.draw_text("- Mouse Wheel to Zoom in-out", {40, 60}, 10, k2.DARKGRAY)
		k2.draw_text("- A / S to Rotate", {40, 80}, 10, k2.DARKGRAY)
		k2.draw_text("- R to reset Zoom and Rotation", {40, 100}, 10, k2.DARKGRAY)

		k2.present()
	}

	k2.shutdown()
}

