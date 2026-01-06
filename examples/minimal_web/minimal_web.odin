// A small program that draws some shapes, some texts and a texture.
//
// This is the same as `../minimal`, but adapted to work on web. Compile the web version using the
// command-line. Navigate to the `karl2d` folder and run:
//
//    odin run build_web -- examples/minimal_web
//
// The built web application will be in examples/minimal_web/bin/web.
package karl2d_minimal_example_web

import k2 "../.."
import "core:log"
import "core:fmt"
import "core:math"

_ :: fmt

tex: k2.Texture

init :: proc() {
	k2.init(1080, 1080, "Karl2D Minimal Program")

	// Note that we #load the texture: This bakes it into the program's data. WASM has no filesystem
	// so in order to bundle textures with your game, you need to store them somewhere it can fetch
	// them.
	tex = k2.load_texture_from_bytes(#load("../minimal/sixten.jpg"))
}

step :: proc() -> bool {
	if !k2.update() {
		return false
	}

	k2.clear(k2.LIGHT_BLUE)

	t := k2.get_time()

	pos_x := f32(math.sin(t*10)*10)
	rot := f32(t*50)
	k2.draw_texture_ex(tex, {0, 0, f32(tex.width), f32(tex.height)}, {pos_x + 400, 450, 900, 500}, {450, 250}, rot)

	k2.draw_rect({10, 10, 60, 60}, k2.GREEN)
	k2.draw_rect({20, 20, 40, 40}, k2.LIGHT_GREEN)
	k2.draw_circle({120, 40}, 30, k2.DARK_RED)
	k2.draw_circle({120, 40}, 20, k2.RED)

	k2.draw_rect({4, 95, 512, 152}, k2.color_alpha(k2.DARK_GRAY, 192))
	
	k2.draw_text("Hellöpe!", {10, 100}, 48, k2.LIGHT_RED)

	msg1 := fmt.tprintf("Time since start: %.3f s", t)
	msg2 := fmt.tprintf("Last frame time: %.5f s", k2.get_frame_time())
	k2.draw_text(msg1, {10, 148}, 48, k2.ORANGE)
	k2.draw_text(msg2, {10, 196}, 48, k2.LIGHT_PURPLE)

	k2.present()
	free_all(context.temp_allocator)

	return true
}

shutdown :: proc() {
	k2.destroy_texture(tex)
	k2.shutdown()
}

// This is not run by the web version, but it makes this program also work on non-web!
main :: proc() {
	context.logger = log.create_console_logger()
	init()

	run := true
	for run {
		if !step() {
			run = false
		}
	}

	shutdown()
}
