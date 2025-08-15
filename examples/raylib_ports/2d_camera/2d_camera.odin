// This is a port of https://github.com/raysan5/raylib/blob/master/examples/core/core_2d_camera.c

package raylib_example_2d_camera

import kl "../../.."
import "core:math/rand"
import "core:math"

MAX_BUILDINGS :: 100
SCREEN_WIDTH :: 800
SCREEN_HEIGHT :: 450

main :: proc() {
	kl.init(SCREEN_WIDTH, SCREEN_HEIGHT, "karlib: 2d camera (raylib [core] example - 2d camera)")

	player := kl.Rect { 400, 280, 40, 40 }
    buildings: [MAX_BUILDINGS]kl.Rect
    building_colors: [MAX_BUILDINGS]kl.Color

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

    camera := kl.Camera {
    	origin = { SCREEN_WIDTH / 2, SCREEN_HEIGHT / 2},
    	zoom = 1,
    }

    for !kl.window_should_close() {
    	kl.process_events()

    	if kl.key_is_held(.Right) { player.x += 2 }
    	else if kl.key_is_held(.Left) { player.x -= 2 }

        camera.target = { player.x + 20, player.y + 20 }

        if kl.key_is_held(.A) { camera.rotation -= 1 }
        else if kl.key_is_held(.S)  { camera.rotation += 1 }

        if camera.rotation > 40 { camera.rotation = 40 }
        else if camera.rotation < -40 { camera.rotation = -40 }

        camera.zoom = math.exp(math.log(camera.zoom, math.E) + f32(kl.get_mouse_wheel_delta() * 0.1))
      
        if camera.zoom > 3 { camera.zoom = 3 }
        else if camera.zoom < 0.1 { camera.zoom = 0.1 }

        if kl.key_went_down(.R) {
        	camera.zoom = 1
        	camera.rotation = 0
        }

        kl.clear({ 245, 245, 245, 255 })
        kl.set_camera(camera)
        kl.draw_rect({-6000, 320, 13000, 8000}, kl.DARKGRAY)

        for i in 0..<MAX_BUILDINGS {
            kl.draw_rect(buildings[i], building_colors[i])
        }

        kl.draw_rect(player, kl.RED)
        kl.draw_line({camera.target.x, -SCREEN_HEIGHT * 10}, {camera.target.x, SCREEN_HEIGHT * 10 }, 1, kl.GREEN)
        kl.draw_line({-SCREEN_WIDTH*10, camera.target.y}, {SCREEN_WIDTH*10, camera.target.y}, 1, kl.GREEN)

        kl.set_camera(nil)
        kl.draw_text("SCREEN AREA", {640, 10}, 20, kl.RED)

        kl.draw_rect({0, 0, SCREEN_WIDTH, 5}, kl.RED)
        kl.draw_rect({0, 5, 5, SCREEN_HEIGHT - 10}, kl.RED)
        kl.draw_rect({SCREEN_WIDTH - 5, 5, 5, SCREEN_HEIGHT - 10}, kl.RED)
        kl.draw_rect({0, SCREEN_HEIGHT - 5, SCREEN_WIDTH, 5}, kl.RED)

        kl.draw_rect({10, 10, 250, 113}, {102, 191, 255, 128})
        kl.draw_rect_outline({10, 10, 250, 113}, 1, kl.BLUE)

        kl.draw_text("Free 2d camera controls:", {20, 20}, 10, kl.BLACK)
        kl.draw_text("- Right/Left to move Offset", {40, 40}, 10, kl.DARKGRAY)
        kl.draw_text("- Mouse Wheel to Zoom in-out", {40, 60}, 10, kl.DARKGRAY)
        kl.draw_text("- A / S to Rotate", {40, 80}, 10, kl.DARKGRAY)
        kl.draw_text("- R to reset Zoom and Rotation", {40, 100}, 10, kl.DARKGRAY)

    	kl.present()
    }

    kl.shutdown()
}

