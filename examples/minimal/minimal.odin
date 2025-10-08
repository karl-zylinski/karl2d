package karl2d_minimal_example

import k2 "../.."
import "core:log"

main :: proc() {
	context.logger = log.create_console_logger()
	k2.init(1080, 1080, "Karl2D Minimal Program")
	k2.set_window_position(300, 100)

	img := k2.load_texture_from_file("sixten.jpg")
	
	for !k2.shutdown_wanted() {
		k2.process_events()
		k2.clear(k2.BLUE)
		k2.draw_text("Hellope!", {10, 10}, 32, k2.WHITE)

		k2.draw_texture(img, {50, 50}, k2.WHITE)
		k2.present()
		free_all(context.temp_allocator)
	}

	k2.shutdown()
}
