package karl2d_minimal_example

import k2 "../.."
import "core:log"

main :: proc() {
	context.logger = log.create_console_logger()
	k2.init(1080, 1080, "Karl2D Minimal Program")
	k2.set_window_position(300, 100)

	cao_font := k2.load_font_from_file("cat_and_onion_dialogue_font.ttf")
	default_font := k2.get_default_font()

	for !k2.shutdown_wanted() {
		k2.process_events()
		k2.clear(k2.BLUE)

		font := cao_font 

		if k2.key_is_held(.K) {
			font = default_font
		}

		k2.draw_text_ex(font, "Hellöpe!", {20, 20}, 64, k2.WHITE)
		k2.present()
		free_all(context.temp_allocator)
	}

	k2.shutdown()
}
