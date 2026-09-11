package karl2d_measure_text_example

// Fonts used:
// 1. https://fonts.google.com/specimen/Josefin+Slab
// 2. https://fonts.google.com/specimen/Merienda
// 3. https://fonts.google.com/specimen/Momo+Trust+Display
// 4. https://poppyworks.itch.io/silver
// The first 3 fonts are licensed under the SIL Open Font License, Version 1.1
// - Link: https://openfontlicense.org
// - File: OFL.txt
// The last font is licensed under Attribution 4.0 International with an additional commercial
// production budget threshold
// - Link: https://creativecommons.org/licenses/by/4.0/
// - File: Sliver-LICENSE.txt

import k2 "../.."
import "core:fmt"
import "core:unicode/utf8"

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
	{ name="Silver", 				bytes=#load("Silver.ttf") },
}

current_font_idx: int
current_font_size := f32(50)

init :: proc() {
	k2.init(1600, 900, "Karl2D Measure Text Example", { window_mode = .Windowed_Resizable })

	for &f in fonts {
		f.font = f.bytes != nil\
			? k2.load_dynamic_font_from_bytes(f.bytes)\
			: k2.FONT_DEFAULT
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

			k2.draw_text(text, pos, UI_FONT_SIZE, k2.BLACK)
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
		k2.draw_text(text, pos, UI_FONT_SIZE, k2.BLACK)
	}

	// CURRENT FONT FACE
	{
		LEFT, TOP :: 400, 30
		font := fonts[current_font_idx].font

		pos := Vec2 { LEFT, TOP }
		for char in ' '..='~' {
			text := string([]u8 { u8(char) })
			size := k2.measure_text(text, current_font_size, font)
			k2.draw_rect_vec(pos, size, k2.LIGHT_RED)
			k2.draw_text(text, pos, current_font_size, k2.BLACK, font)

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
			size := k2.measure_text(text, current_font_size, font)
			k2.draw_rect_vec(pos1, size, k2.LIGHT_RED)
			k2.draw_text(text, pos1, current_font_size, k2.BLACK, font)
		}

		pos = { LEFT+400, pos.y + 2*current_font_size }
		text := "/*\nHellöpe Karl2D!\nNext line goes here\nAnd one more\n*/"
		size := k2.measure_text(text, current_font_size, font)
		k2.draw_rect_vec(pos, size, k2.LIGHT_RED)
		k2.draw_text(text, pos, current_font_size, k2.BLACK, font)

		// CJK SECTION
		{
			pos = { LEFT, pos.y + size.y + current_font_size }
			header_text := "CJK characters (Silver only)"
			header_size := k2.measure_text(header_text, current_font_size, font)
			k2.draw_rect_vec(pos, header_size, k2.LIGHT_RED)
			k2.draw_text(header_text, pos, current_font_size, k2.BLACK, font)

			pos = { LEFT, pos.y + 2*current_font_size }
			cjkText := "道可道非常道。义、礼、说、选、权吾輩は猫である。다람쥐 헌 쳇바퀴에 타고파."
			for character in cjkText {
				buf, n := utf8.encode_rune(character)
				text = string(buf[:n])
				size := k2.measure_text(text, current_font_size, font)
				k2.draw_rect_vec(pos, size, k2.LIGHT_RED)
				k2.draw_text(text, pos, current_font_size, k2.BLACK, font)

				pos.x += current_font_size
				if pos.x+current_font_size > screen_size.x-40 {
					pos = { LEFT, pos.y+current_font_size }
				}
			}
		}
	}

	// HINTS
	{
		hits_text := fmt.tprintf("Press 1..%i to change font\nPress +/- to change size", len(fonts))
		hits_pos := Vec2 { 40, screen_size.y-30-2*UI_FONT_SIZE }
		k2.draw_text(hits_text, hits_pos, UI_FONT_SIZE, k2.BLACK)
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
