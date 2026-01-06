// Based on https://github.com/raysan5/raylib/blob/master/examples/shaders/shaders_texture_waves.c

package raylib_example_shaders_texture_waves

import k2 "../../.."
import "core:log"

SCREEN_WIDTH :: 800
SCREEN_HEIGHT :: 450

main :: proc() {
	context.logger = log.create_console_logger()

	k2.init(SCREEN_WIDTH, SCREEN_HEIGHT, "Karl2D: texture waves (raylib [shaders] example - texture waves)")

	texture := k2.load_texture_from_file("space.png")

	WAVE_SHADER_DATA :: #load("wave.hlsl")

	shader := k2.load_shader_from_bytes(WAVE_SHADER_DATA, WAVE_SHADER_DATA)
	seconds_loc := shader.constant_lookup["seconds"]
	freq_x_loc := shader.constant_lookup["freqX"]
	freq_y_loc := shader.constant_lookup["freqY"]
	amp_x_loc := shader.constant_lookup["ampX"]
	amp_y_loc := shader.constant_lookup["ampY"]
	speed_x_loc := shader.constant_lookup["speedX"]
	speed_y_loc := shader.constant_lookup["speedY"]

	freq_x := f32(25)
	freq_y := f32(25)
	amp_x := f32(5)
	amp_y := f32(5)
	speed_x := f32(8)
	speed_y := f32(8)

	screen_size := [2]f32 { f32(k2.get_screen_width()),	f32(k2.get_screen_height()) }
	k2.set_shader_constant(shader, shader.constant_lookup["size"], screen_size)
	k2.set_shader_constant(shader, freq_x_loc, freq_x)
	k2.set_shader_constant(shader, freq_y_loc, freq_y)
	k2.set_shader_constant(shader, amp_x_loc, amp_x)
	k2.set_shader_constant(shader, amp_y_loc, amp_y)
	k2.set_shader_constant(shader, speed_x_loc, speed_x)
	k2.set_shader_constant(shader, speed_y_loc, speed_y)

	for k2.update() {
		k2.set_shader_constant(shader, seconds_loc, f32(k2.get_time()))
		k2.set_shader(shader)

		k2.draw_texture(texture, {0, 0})
		k2.draw_texture(texture, {f32(texture.width), 0})

		k2.set_shader(nil)
		k2.present()
	}

	k2.destroy_shader(shader)
	k2.destroy_texture(texture)

	k2.shutdown()
}