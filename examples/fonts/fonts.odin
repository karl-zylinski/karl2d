package karl2d_fonts_example

import k2 "../.."
import "core:fmt"
import "core:unicode/utf8"
import "core:mem"

main :: proc() {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	context.allocator = mem.tracking_allocator(&track)

	init()
	for step() {}
	shutdown()

	if len(track.allocation_map) > 0 {
		fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
		for _, entry in track.allocation_map {
			fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
		}
	}
	mem.tracking_allocator_destroy(&track)
}

cat_and_onion_font: k2.Font

init :: proc() {
	k2.init(1080, 1080, "Karl2D Fonts Example")

	font_codepoints := utf8.string_to_runes(
		"abcdefghiklmnopqrstuvwxyzåäöABCDEFGHIKLMNOPQRSTUVWXYZÅÄÖ!()1234567890., :",
		context.temp_allocator,
	)

	cat_and_onion_font = k2.load_static_font_from_bytes(
		#load("cat_and_onion_dialogue_font.ttf"),
		48,
		font_codepoints,
	)
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