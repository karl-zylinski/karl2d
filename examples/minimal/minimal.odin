// A small program that draws some shapes, some texts and a texture.
//
// The name is "minimal", but it's really a "smallest program that does anything useful": It draws
// some graphics on the screen.
//
// There is a web version of this example in `../minimal_web` -- Many other examples work on web out
// of the box. But the web support requires slight changes to the structure of the program. Here we
// want to keep things as simple as possible, which is why this `minimal` example has a separate web
// version.
package karl2d_minimal_example

import k2 "../.."
import "core:log"
import "core:math"
import "core:fmt"

main :: proc() {
	context.logger = log.create_console_logger()

	k2.init(1080, 1080, "Karl2D Minimal Program")
	tex := k2.load_texture_from_file("sixten.jpg")

	for k2.update() {
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
	}

	k2.destroy_texture(tex)
	k2.shutdown()
}
