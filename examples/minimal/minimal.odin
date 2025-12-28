package karl2d_minimal_example

import k2 "../.."
import "core:mem"
import "core:log"
import "core:fmt"
import "core:math"
import "core:time"

_ :: fmt
_ :: mem

tex: k2.Texture

init :: proc() {
	k2.init(1080, 1080, "Karl2D Minimal Program")
	tex = k2.load_texture_from_bytes(#load("sixten.jpg"))
}

t: f32

step :: proc(dt: f32) -> bool {
	k2.process_events()
	k2.clear(k2.BLUE)

	t += dt

	pos := math.sin(t*10)*10
	rot := t*50
	k2.draw_texture_ex(tex, {0, 0, f32(tex.width), f32(tex.height)}, {pos + 400, 450, 900, 500}, {450, 250}, rot)

	k2.draw_rect({10, 10, 60, 60}, k2.GREEN)
	k2.draw_rect({20, 20, 40, 40}, k2.BLACK)
	k2.draw_circle({120, 40}, 30, k2.BLACK)
	k2.draw_circle({120, 40}, 20, k2.GREEN)
	k2.draw_text("Hellöpe!", {10, 100}, 64, k2.WHITE)

	if k2.key_went_down(.R) {
		k2.set_window_flags({.Resizable})
	}

	if k2.key_went_down(.N) {
		k2.set_window_flags({})
	}
	

	k2.present()
	free_all(context.temp_allocator)

	res := true

	if k2.key_went_down(.Escape) {
		res = false
	}

	return res
}

shutdown :: proc() {
	k2.destroy_texture(tex)
	k2.shutdown()
}

main :: proc() {
	context.logger = log.create_console_logger()

	init()

	prev_time := time.now()

	for !k2.shutdown_wanted() {
		now := time.now()
		since := time.diff(prev_time, now)
		dt := f32(time.duration_seconds(since))
		prev_time = now
		
		if !step(dt) {
			break
		}
	}

	shutdown()
}
