package karl2d_palette

import k2 "../.."
import "core:log"
import "core:fmt"

_ :: fmt

tex: k2.Texture

init :: proc() {
	k2.init(1470, 1530, "Karl2D Palette Demo")
}

step :: proc() -> bool {
	k2.new_frame()
	k2.process_events()
	k2.clear(k2.WHITE)
	k2.draw_rect({0, 0, f32(k2.get_screen_width() / 2), f32(k2.get_screen_height())}, k2.BLACK)

	colors := [?]k2.Color {
		k2.BLACK,
		k2.WHITE,
		k2.GRAY,
		k2.DARK_GRAY,
		k2.BLUE,
		k2.DARK_BLUE,
		k2.LIGHT_BLUE,
		k2.GREEN,
		k2.DARK_GREEN,
		k2.LIGHT_GREEN,
		k2.RED,
		k2.LIGHT_RED,
		k2.DARK_RED,
		k2.LIGHT_PURPLE,
		k2.YELLOW,
		k2.LIGHT_YELLOW,
		k2.MAGENTA,
	}

	color_names := [?]string {
		"BLACK",
		"WHITE",
		"GRAY",
		"DARK_GRAY",
		"BLUE",
		"DARK_BLUE",
		"LIGHT_BLUE",
		"GREEN",
		"DARK_GREEN",
		"LIGHT_GREEN",
		"RED",
		"LIGHT_RED",
		"DARK_RED",
		"LIGHT_PURPLE",
		"YELLOW",
		"LIGHT_YELLOW",
		"MAGENTA",
	}

	x := f32(290)
	y := f32(0)
	PAD :: 20
	SW :: 50
	SH :: 50

	for bg, i in colors {
		k2.draw_rect({x, y, 890, SH+PAD*2}, bg)

		k2.draw_text(color_names[i], {x + 890+PAD, y+25}, 40, bg)

		color_name_width := k2.measure_text(color_names[i], 40)
		k2.draw_text(color_names[i], {290-color_name_width.x-PAD, y+25}, 40, bg)

		for c in colors {
			k2.draw_rect({x + PAD, y + PAD, SW, SH}, c)
			x += SW
		}

		x = 290
		y += SH + PAD*2
	}

	k2.present()
	free_all(context.temp_allocator)

	return !k2.shutdown_wanted()
}

shutdown :: proc() {
	k2.destroy_texture(tex)
	k2.shutdown()
}

main :: proc() {
	context.logger = log.create_console_logger()
	init()

	run := true
	for run {
		run = step() 
	}

	shutdown()
}
