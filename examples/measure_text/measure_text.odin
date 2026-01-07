package karl2d_measure_text_example

// Fonts used:
// - https://fonts.google.com/specimen/Josefin+Slab
// - https://fonts.google.com/specimen/Merienda
// - https://fonts.google.com/specimen/Momo+Trust+Display
// These fonts are licensed under the SIL Open Font License, Version 1.1
// - Link: https://openfontlicense.org
// - File: OFL.txt

import k2 "../.."
import "core:fmt"

Vec2 :: k2.Vec2

Font :: struct {
	name: string,
	bytes: []u8,
	font: k2.Font,
}

fonts := [?] Font {
	{ name="<Default>" },
	{ name="Momo Trust Display", 	bytes=#load("MomoTrustDisplay-Regular.ttf") },
	{ name="Josefin Slab", 			bytes=#load("JosefinSlab-Bold.ttf") },
	{ name="Merienda", 				bytes=#load("Merienda-Bold.ttf") },
}

current_font_idx: int
current_font_size := f32(50)

init :: proc() {
	k2.init(1280, 720, "Karl2D Measure Text Example", { window_mode = .Windowed_Resizable })

	for &f in fonts {
		f.font = f.bytes != nil\
			? k2.load_font_from_bytes(f.bytes)\
			: k2.get_default_font()
	}
}

step :: proc() -> bool {
	if !k2.update() {
		return false
	}

	UI_FONT_SIZE :: 30
	screen_size := Vec2 { f32(k2.get_screen_width()), f32(k2.get_screen_height()) }
	frame_time := k2.get_frame_time()

	k2.clear(k2.LIGHT_BROWN)

	// FONT SELECTOR
	{
		for f, i in fonts {
			text := fmt.tprintf("%i. %s", i+1, f.name)
			pos := Vec2 { 40, 30 + f32(i)*UI_FONT_SIZE }

			i_key_n := k2.Keyboard_Key(i + int(k2.Keyboard_Key.N1))
			i_key_np := k2.Keyboard_Key(i + int(k2.Keyboard_Key.NP_1))
			if k2.key_went_down(i_key_n) ||k2.key_went_down(i_key_np)  {
				current_font_idx = i
			}

			if i == current_font_idx {
				size := k2.measure_text(text, UI_FONT_SIZE)
				k2.draw_rect_vec(pos, size, k2.LIGHT_YELLOW)
			}

			k2.draw_text(text, pos, UI_FONT_SIZE)
		}
	}

	// CURRENT FONT SIZE
	{
		sign: f32
		if k2.key_is_held(.Equal) || k2.key_is_held(.NP_Add) 		{ sign = +1 }
		if k2.key_is_held(.Minus) || k2.key_is_held(.NP_Subtract)	{ sign = -1 }
		if sign != 0 {
			FONT_SIZE_CHANGE_SPEED :: 20 // in px/sec
			current_font_size += sign * FONT_SIZE_CHANGE_SPEED * frame_time
			current_font_size = clamp(current_font_size, 10, 100)
		}

		text := fmt.tprintf("[+/-] Font size: %.1f", current_font_size)
		pos := Vec2 { 40, 30 + (len(fonts)+1)*UI_FONT_SIZE }
		k2.draw_text(text, pos, UI_FONT_SIZE)
	}

	// CURRENT FONT FACE
	{
		LEFT, TOP :: 400, 30
		font := fonts[current_font_idx].font

		pos := Vec2 { LEFT, TOP }
		for char in ' '..='~' {
			text := string([]u8 { u8(char) })
			size := k2.measure_text_ex(font, text, current_font_size)
			k2.draw_rect_vec(pos, size, k2.LIGHT_RED)
			k2.draw_text_ex(font, text, pos, current_font_size)

			pos.x += current_font_size
			if pos.x+current_font_size > screen_size.x-40 {
				pos = { LEFT, pos.y+current_font_size }
			}
		}

		for text, i in ([?] string {
			"000,0,000",
			" 000,1,000 ",
			"  000,2,000  ",
			"   000,3,000   ",
			"    000,4,000    ",
		}) {
			pos1 := Vec2 { LEFT, pos.y + f32(i+2)*current_font_size }
			size := k2.measure_text_ex(font, text, current_font_size)
			k2.draw_rect_vec(pos1, size, k2.LIGHT_RED)
			k2.draw_text_ex(font, text, pos1, current_font_size)
		}

		pos = { LEFT+400, pos.y + 2*current_font_size }
		text := "/*\nHellöpe Karl2D!\nNext line goes here\nAnd one more\n*/"
		size := k2.measure_text_ex(font, text, current_font_size)
		k2.draw_rect_vec(pos, size, k2.LIGHT_RED)
		k2.draw_text_ex(font, text, pos, current_font_size)
	}

	// HINTS
	{
		hits_text := fmt.tprintf("Press 1..%i to change font\nPress +/- to change size", len(fonts))
		hits_pos := Vec2 { 40, screen_size.y-30-2*UI_FONT_SIZE }
		k2.draw_text(hits_text, hits_pos, UI_FONT_SIZE)
	}

	k2.present()
	free_all(context.temp_allocator)
	return true
}

shutdown :: proc() {
	for f in fonts {
		if f.bytes != nil {
			k2.destroy_font(f.font)
		}
	}
	k2.shutdown()
}

main :: proc() {
	init()
	for step() {}
	shutdown()
}
