package karl2d_char_pressed_example

import k2 "../.."
import "core:fmt"
import "core:strings"

PADDING  :: f32(20)
BOX_X    :: f32(40)
BOX_Y    :: f32(280)
BOX_W    :: f32(1200)
BOX_H    :: f32(80)
FONT_SZ  :: f32(48)

builder: strings.Builder

main :: proc() {
	k2.init(1280, 720, "Karl2D char_pressed Example")

	for k2.update() {
		for ch := k2.get_char_pressed(); ch > 0; ch = k2.get_char_pressed() {
			strings.write_rune(&builder, ch)
		}

		if k2.key_went_down(.Backspace) || k2.key_went_down_repeat(.Backspace) {
			for len(builder.buf) > 0 {
				last := builder.buf[len(builder.buf)-1]
				resize(&builder.buf, len(builder.buf)-1)
				if last < 0x80 || last >= 0xC0 do break
			}
		}

		if k2.key_is_held(.Left_Control) && (k2.key_went_down(.V) || k2.key_went_down_repeat(.V)) {
			text := k2.get_clipboard_text(context.temp_allocator)
			strings.write_string(&builder, text)
		}

		if k2.key_went_down(.Escape) {
			clear(&builder.buf)
		}

		if k2.is_file_dropped() {
			paths := k2.get_dropped_files()
			defer k2.destroy_dropped_files(paths)
			for path in paths {
				fmt.println(path)
			}
		}

		typed := strings.to_string(builder)

		{ k2.clear(k2.DARK_GRAY)
			k2.draw_text("Type something:", {BOX_X, BOX_Y - 60}, FONT_SZ, k2.LIGHT_BLUE)
			k2.draw_rect({BOX_X, BOX_Y, BOX_W, BOX_H}, k2.BLACK)
			k2.draw_text(typed, {BOX_X + PADDING, BOX_Y + PADDING/2}, FONT_SZ, k2.WHITE)
			k2.draw_text("[Backspace] delete last char    [Escape] clear", {BOX_X, BOX_Y + BOX_H + 20}, 28, k2.LIGHT_BLUE)
			k2.draw_text(fmt.tprintf("Characters in buffer: %v", strings.rune_count(typed)), {BOX_X, BOX_Y + BOX_H + 60}, 28, k2.LIGHT_BLUE)
		} k2.present()

		free_all(context.temp_allocator)
	}

	k2.shutdown()
}
