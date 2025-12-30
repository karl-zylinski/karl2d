package karl2d_palette

import k2 "../.."
import "core:log"
import "core:fmt"
import "core:reflect"

_ :: fmt

tex: k2.Texture

PAD :: 20
SW :: 50
SH :: 50
MID_WIDTH :: (len(COLOR_BY_NAME) - 1) * SW + PAD*2

init :: proc() {
	k2.init(290*2 + MID_WIDTH, (len(COLOR_BY_NAME) - 1)*(SH + PAD*2), "Karl2D Palette Demo")
}

step :: proc() -> bool {
	k2.new_frame()
	k2.process_events()
	k2.clear(k2.WHITE)
	k2.draw_rect({0, 0, f32(k2.get_screen_width() / 2), f32(k2.get_screen_height())}, k2.BLACK)

	x := f32(290)
	y := f32(0)

	for c, name in COLOR_BY_NAME {
		if name == .BLANK {
			continue
		}

		k2.draw_rect({x, y, MID_WIDTH, SH+PAD*2}, c)

		k2.draw_text(reflect.enum_string(name), {x + MID_WIDTH+PAD, y+25}, 40, c)

		color_name_width := k2.measure_text(reflect.enum_string(name), 40)
		k2.draw_text(reflect.enum_string(name), {290-color_name_width.x-PAD, y+25}, 40, c)

		for c2, c2_name in COLOR_BY_NAME {
			if c2_name == .BLANK {
				continue
			}

			k2.draw_rect({x + PAD, y + PAD, SW, SH}, c2)
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

Color_Name :: enum {
	BLACK,
	WHITE,
	BLANK,
	GRAY,
	DARK_GRAY,
	BLUE,
	DARK_BLUE,
	LIGHT_BLUE,
	GREEN,
	DARK_GREEN,
	LIGHT_GREEN,
	ORANGE,
	RED,
	DARK_RED,
	LIGHT_RED,
	BROWN,
	DARK_BROWN,
	LIGHT_BROWN,
	PURPLE,
	LIGHT_PURPLE,
	MAGENTA,
	YELLOW,
	LIGHT_YELLOW,
}

COLOR_BY_NAME :: [Color_Name]k2.Color {
	.BLACK = k2.BLACK,
	.WHITE = k2.WHITE,
	.BLANK = k2.BLANK,
	.GRAY = k2.GRAY,
	.DARK_GRAY = k2.DARK_GRAY,
	.BLUE = k2.BLUE,
	.DARK_BLUE = k2.DARK_BLUE,
	.LIGHT_BLUE = k2.LIGHT_BLUE,
	.GREEN = k2.GREEN,
	.DARK_GREEN = k2.DARK_GREEN,
	.LIGHT_GREEN = k2.LIGHT_GREEN,
	.ORANGE = k2.ORANGE,
	.RED = k2.RED,
	.DARK_RED = k2.DARK_RED,
	.LIGHT_RED = k2.LIGHT_RED,
	.BROWN = k2.BROWN,
	.DARK_BROWN = k2.DARK_BROWN,
	.LIGHT_BROWN = k2.LIGHT_BROWN,
	.PURPLE = k2.PURPLE,
	.LIGHT_PURPLE = k2.LIGHT_PURPLE,
	.MAGENTA = k2.MAGENTA,
	.YELLOW = k2.YELLOW,
	.LIGHT_YELLOW = k2.LIGHT_YELLOW,
}