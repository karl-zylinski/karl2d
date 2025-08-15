// Based on https://github.com/raysan5/raylib/blob/master/examples/shaders/shaders_texture_waves.c

package raylib_example_shaders_texture_waves

import k2 "../../.."
import "core:time"

SCREEN_WIDTH :: 800
SCREEN_HEIGHT :: 450

main :: proc() {
    k2.init(SCREEN_WIDTH, SCREEN_HEIGHT, "Karl2D: texture waves (raylib [shaders] example - texture waves)")

    texture := k2.load_texture_from_file("space.png")
    shader := k2.load_shader("", "wave.fs")

    seconds_loc := k2.get_shader_location(shader, "seconds")
    freq_x_loc := k2.get_shader_location(shader, "freqX")
    freq_y_loc := k2.get_shader_location(shader, "freqY")
    amp_x_loc := k2.get_shader_location(shader, "ampX")
    amp_y_loc := k2.get_shader_location(shader, "ampY")
    speed_x_loc := k2.get_shader_location(shader, "speedX")
    speed_y_loc := k2.get_shader_location(shader, "speedY")

    freq_x := f32(25)
    freq_y := f32(25)
    amp_x := f32(5)
    amp_y := f32(5)
    speed_x := f32(8)
    speed_y := f32(8)

    screen_size := [2]f32 { f32(k2.get_screen_width()),	f32(k2.get_screen_height()) }
    k2.set_shader_value(shader, k2.get_shader_location(shader, "size"), screen_size)
    k2.set_shader_value(shader, freq_x_loc, freq_x)
    k2.set_shader_value(shader, freq_y_loc, freq_y)
    k2.set_shader_value(shader, amp_x_loc, amp_x)
    k2.set_shader_value(shader, amp_y_loc, amp_y)
    k2.set_shader_value(shader, speed_x_loc, speed_x)
    k2.set_shader_value(shader, speed_y_loc, speed_y)

    seconds: f32

    last_frame_time := time.now()

    for !k2.window_should_close() {
    	k2.process_events()
    	now := time.now()
    	dt := f32(time.duration_seconds(time.diff(last_frame_time, now)))
    	last_frame_time = now
    	seconds += dt

		k2.set_shader_value(shader, seconds_loc, seconds)
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