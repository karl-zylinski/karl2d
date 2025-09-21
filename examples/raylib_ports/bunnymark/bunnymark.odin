// This is a port of https://www.raylib.com/examples/textures/loader.html?name=textures_bunnymark

package karl2d_bunnymark

import k2 "../../.."
import "core:math/rand"
import "core:log"

MAX_BUNNIES :: 50000

Bunny :: struct {
	position: k2.Vec2,
	speed: k2.Vec2,
	color: k2.Color,
}

main :: proc() {
	context.logger = log.create_console_logger()

	SCREEN_WIDTH :: 800
	SCREEN_HEIGHT :: 450

	k2.init(SCREEN_WIDTH, SCREEN_HEIGHT, "bunnymark (raylib port)")

	tex_bunny := k2.load_texture_from_file("wabbit_alpha.png")

	bunnies: [dynamic]Bunny

	for !k2.shutdown_wanted() {
		if k2.mouse_button_is_held(.Left) {
			for _ in 0..<100 {
				append(&bunnies, Bunny {
					position = k2.get_mouse_position(),
					speed = {
						rand.float32_range(-250, 250)/60,
						rand.float32_range(-250, 250)/60,
					},
					color = {
						u8(rand.int_max(190) + 50),
						u8(rand.int_max(160) + 80),
						u8(rand.int_max(140) + 100),
						255,
					},
				})
			}
		}

		for &b in bunnies {
			b.position += b.speed

			if (b.position.x + f32(tex_bunny.width/2) > f32(k2.get_screen_width())) || ((b.position.x + f32(tex_bunny.width/2)) < 0) {
				b.speed.x *= -1
			}

			if (b.position.y + f32(tex_bunny.height/2) > f32(k2.get_screen_height())) || ((b.position.y + f32(tex_bunny.height/2)) < 0) {
				b.speed.y *= -1
			}
		}

		k2.process_events()
		k2.clear(k2.RL_RAYWHITE)

		for &b in bunnies {
			k2.draw_texture(tex_bunny, b.position, b.color)
		}

		k2.present()
	}

	delete(bunnies)
	k2.destroy_texture(tex_bunny)

	k2.shutdown()
}