package karl2d_minimal_example

import k2 "../.."
import "core:mem"
import "core:log"
import "core:math"
import "core:fmt"

_ :: fmt
_ :: mem

main :: proc() {
	context.logger = log.create_console_logger()
	init()
	run := true

	for run {
		run = step()
	}

	shutdown()
}

render_texture: k2.Render_Texture

init :: proc() {
	k2.init(1080, 1080, "Karl2D Render Texture Example")
	render_texture = k2.create_render_texture(75, 48)
}

rot: f32

step :: proc() -> bool {
	k2.new_frame()
	k2.process_events()

	k2.set_render_texture(render_texture)
	k2.clear(k2.ORANGE)

	rot += k2.get_frame_time() * 500

	if rot > 360 {
		rot -= 360
	}

	k2.draw_rect_ex({12, 12, 12, 12}, {6, 6}, rot, k2.BLACK)
	k2.draw_text("Hellöpe!", {f32(math.sin(k2.get_time() * 10))*5 + 7, 20}, 20, k2.BLACK)
	
	k2.set_render_texture(nil)

	k2.clear(k2.BLACK)

	rt_size := k2.get_texture_rect(render_texture.texture)

	k2.draw_texture_ex(render_texture.texture, rt_size, {0, 0, rt_size.w * 5, rt_size.h * 5}, {}, 0)
	k2.draw_texture(render_texture.texture, {400, 20})
	k2.draw_texture_ex(render_texture.texture, rt_size, {512, 512, rt_size.w * 5, rt_size.h * 5}, {}, 70, k2.WHITE)

	k2.present()
	free_all(context.temp_allocator)
	return !k2.shutdown_wanted()
}

shutdown :: proc() {
	k2.destroy_render_texture(render_texture)
	k2.shutdown()
}