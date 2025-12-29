package karl2d_fonts_example

import k2 "../.."
import "core:log"
import "core:fmt"

main :: proc() {
	context.logger = log.create_console_logger()
	init()
	run := true

	for run {
		run = step()
	}

	shutdown()
}

cat_and_onion_font: k2.Font_Handle

init :: proc() {
	k2.init(1080, 1080, "Karl2D Fonts Example")
	cat_and_onion_font = k2.load_font_from_bytes(#load("cat_and_onion_dialogue_font.ttf"))
}

step :: proc() -> bool {
	k2.new_frame()
	k2.process_events()
	k2.clear(k2.BLUE)

	font := k2.get_default_font() 

	if k2.key_is_held(.K) {
		font = cat_and_onion_font
	}

	msg := "Hellöpe! Hold K to swap font"
	k2.draw_text_ex(font, msg, {20, 20}, 64, k2.WHITE)

	size := k2.measure_text_ex(font, msg, 64)
	size_msg := fmt.tprintf("The text above takes %.1f x %.1f pixels of space", size.x, size.y)

	k2.draw_text(size_msg, {20, 100}, 32)

	k2.present()
	free_all(context.temp_allocator)
	return !k2.shutdown_wanted()
}

shutdown :: proc() {
	k2.destroy_font(cat_and_onion_font)
	k2.shutdown()
}