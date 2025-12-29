package karl2d_minimal_example

import k2 "../.."
import "core:mem"
import "core:log"
import "core:fmt"

_ :: fmt
_ :: mem

main :: proc() {
	context.logger = log.create_console_logger()

	when ODIN_DEBUG {
		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		context.allocator = mem.tracking_allocator(&track)

		defer {
			if len(track.allocation_map) > 0 {
				for _, entry in track.allocation_map {
					fmt.eprintf("%v leaked: %v bytes\n", entry.location, entry.size)
				}
			}
			mem.tracking_allocator_destroy(&track)
		}
	}

	init()

	for !k2.shutdown_wanted() {
		if !step(0) {
			break
		}
	}

	shutdown()
}

render_texture: k2.Render_Texture

init :: proc() {
	k2.init(1080, 1080, "Karl2D Render Texture Example")
	render_texture = k2.create_render_texture(75, 48)
}

step :: proc(dt: f32) -> bool {
	k2.process_events()

	k2.set_render_texture(render_texture)
	k2.clear(k2.BLUE)

	k2.draw_rect({1, 1, 12, 12}, k2.GREEN)
	k2.draw_rect({2, 2, 10, 10}, k2.BLACK)
	k2.draw_circle({20, 7}, 6, k2.BLACK)
	k2.draw_circle({20, 7}, 5, k2.GREEN)
	k2.draw_text("Hellöpe!", {1, 20}, 20, k2.WHITE)
	
	k2.set_render_texture(nil)

	k2.clear(k2.WHITE)

	rt_size := k2.get_texture_rect(render_texture.texture)

	k2.draw_texture_ex(render_texture.texture, rt_size, {0, 0, rt_size.w * 5, rt_size.h * 5}, {}, 0, k2.WHITE)
	k2.draw_texture(render_texture.texture, {400, 20}, k2.WHITE)
	k2.draw_texture_ex(render_texture.texture, rt_size, {512, 512, rt_size.w * 5, rt_size.h * 5}, {}, 70, k2.WHITE)

	k2.present()
	free_all(context.temp_allocator)
	return true
}

shutdown :: proc() {
	k2.destroy_render_texture(render_texture)
	k2.shutdown()
}