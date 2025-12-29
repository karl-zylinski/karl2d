package karl2d_minimal_example

import k2 "../.."
import "core:log"

main :: proc() {
	context.logger = log.create_console_logger()

	init()

	for !k2.shutdown_wanted() {
		step(0)
	}

	shutdown()
}

cat_and_onion_font: k2.Font_Handle

init :: proc() {
	k2.init(1080, 1080, "Karl2D Fonts Program")

	cat_and_onion_font = k2.load_font_from_bytes(#load("cat_and_onion_dialogue_font.ttf"))
}

step :: proc(dt: f32) -> bool {
	k2.process_events()
	k2.clear(k2.BLUE)

	font := k2.get_default_font() 

	if k2.key_is_held(.K) {
		font = cat_and_onion_font
	}

	k2.draw_text_ex(font, "Hellöpe! Hold K to swap font", {20, 20}, 64, k2.WHITE)
	k2.present()
	free_all(context.temp_allocator)
	return true
}

shutdown :: proc() {
	k2.destroy_font(cat_and_onion_font)
	k2.shutdown()
}