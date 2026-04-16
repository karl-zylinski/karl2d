package karl2d_fonts_example

import k2 "../.."
import "core:fmt"

main :: proc() {
	init()
	for step() {}
	shutdown()
}

cat_and_onion_font: k2.Font

init :: proc() {
	k2.init(1080, 1080, "Karl2D Fonts Example")
	cat_and_onion_font = k2.load_font_from_bytes(#load("cat_and_onion_dialogue_font.ttf"))
}

step :: proc() -> bool {
	if !k2.update() {
		return false
	}
	
	k2.clear(k2.BLUE)

	font := k2.FONT_DEFAULT

	if k2.key_is_held(.K) {
		font = cat_and_onion_font
	}

	msg := "Hellöpe! Hold K to swap font.\nLine breaks work too!"
	k2.draw_text(msg, {20, 20}, 64, k2.WHITE, font)

	size := k2.measure_text(msg, 64, font)
	size_msg := fmt.tprintf("The text above uses %.1f x %.1f pixels of space", size.x, size.y)

	k2.draw_text(size_msg, {20, 200}, 32, k2.BLACK)

	ROTATING_TEXT :: "rotating text!"
	ROTATING_TEXT_SIZE :: 50

	rotating_text_origin := k2.measure_text(ROTATING_TEXT, ROTATING_TEXT_SIZE, font) * 0.5
	k2.draw_text(
		ROTATING_TEXT,
		{400, 400},
		ROTATING_TEXT_SIZE,
		k2.YELLOW,
		font,
		rotating_text_origin,
		f32(k2.get_time()),
	)

	k2.present()
	free_all(context.temp_allocator)
	return true
}

shutdown :: proc() {
	k2.destroy_font(cat_and_onion_font)
	k2.shutdown()
}