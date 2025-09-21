// This is a port of https://www.raylib.com/examples/textures/loader.html?name=textures_bunnymark

package karl2d_bunnymark

import k2 "../../.."
import "core:math/rand"
import "core:log"
import "core:fmt"
import "core:time"

MAX_BUNNIES :: 50000

Bunny :: struct {
	position: k2.Vec2,
	speed: k2.Vec2,
	rot: f32,
	rot_speed: f32,
	color: k2.Color,
}

main :: proc() {
	context.logger = log.create_console_logger()

	SCREEN_WIDTH :: 800
	SCREEN_HEIGHT :: 450

	k2.init(SCREEN_WIDTH, SCREEN_HEIGHT, "bunnymark (raylib port)", window_creation_flags = { .Resizable })

	tex_bunny := k2.load_texture_from_file("wabbit_alpha.png")

	bunnies: [dynamic]Bunny
	prev_time := time.now()

	for !k2.shutdown_wanted() {
		cur_time := time.now()
		dt := f32(time.duration_seconds(time.diff(prev_time, cur_time)))
		prev_time = cur_time

		if k2.mouse_button_is_held(.Left) {
			for _ in 0..<100 {
				append(&bunnies, Bunny {
					position = k2.get_mouse_position(),
					speed = {
						rand.float32_range(-250, 250)/60,
						rand.float32_range(-250, 250)/60,
					},
					rot_speed = rand.float32_range(-5, 5),
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
			b.rot += b.rot_speed

			if b.position.x > f32(k2.get_screen_width()) || b.position.x < 0 {
				b.speed.x *= -1
				b.rot_speed = rand.float32_range(-5, 5)
			}

			if b.position.y > f32(k2.get_screen_height()) || b.position.y < 0 {
				b.speed.y *= -1
				b.rot_speed = rand.float32_range(-5, 5)
			}
		}

		k2.process_events()
		k2.clear(k2.RL_WHITE)

		src := k2.Rect {
			0, 0,
			f32(tex_bunny.width), f32(tex_bunny.height),
		}

		for &b in bunnies {
			dest := src
			dest.x = b.position.x 
			dest.y = b.position.y
			k2.draw_texture_ex(tex_bunny, src, dest, {dest.w/2, dest.h/2}, b.rot, b.color)
		}
		
		if k2.key_went_down(.B) {
			fmt.println(len(bunnies))
			fmt.println(1/dt)
		}

		k2.present()
	}

	delete(bunnies)
	k2.destroy_texture(tex_bunny)

	k2.shutdown()
}