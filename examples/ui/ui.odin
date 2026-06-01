// Some simple UI things that show how to make a button and some advanced sizing tricks

package karl2d_ui_example

import k2 "../.."
import "core:fmt"
import "core:math/rand"
import "core:math"
import "core:strings"

Rect :: k2.Rect
Vec2 :: k2.Vec2

main :: proc() {
	k2.init(1280, 720, "Karl2D: Simple UI")
	button_click_count: int
	random_numbers: [dynamic]int
	input_builder := strings.builder_make()

	for k2.update() {
		k2.clear(k2.LIGHT_BLUE)

		text_input({15, 25}, &input_builder)

		if button({10, 100, 200, 40}, "Click Me") {
			button_click_count += 1
			sz := rand.int_max(9) + 1
			append(&random_numbers, rand.int_max(int(math.pow(f32(10), f32(sz)))))
		}

		k2.draw_text(
			fmt.tprintf("Button has been clicked %v times", button_click_count),
			{300, 105},
			30,
			k2.BLACK,
		)

		numbers_bg_rect := Rect { 10, 150, 500, f32(len(random_numbers) * 30 + 10)}
		k2.draw_rect(numbers_bg_rect, k2.LIGHT_GREEN)
		k2.draw_rect_outline(numbers_bg_rect, 1, k2.BLACK)

		for n, idx in random_numbers {
			k2.draw_text(fmt.tprint(n), {15, 155 + f32(idx) * 30}, 30, k2.BLACK)
		}

		k2.present()
		free_all(context.temp_allocator)
	}

	k2.shutdown()
}

text_input :: proc(pos: Vec2, builder: ^strings.Builder) {
	typed := k2.get_typed_runes()

	for t in typed {
		strings.write_rune(builder, t)
	}

	if k2.key_went_down(.Backspace, allow_repeat = true) {
		strings.pop_rune(builder)
	}

	typed_text := strings.to_string(builder^)

	nothing_typed := len(typed_text) == 0

	if nothing_typed {
		typed_text = "Type..."
	}

	typed_text_size := k2.measure_text(typed_text, 30)
	input_box := k2.rect_expand(k2.rect_from_pos_size(pos, typed_text_size), 5, 3)
	k2.draw_rect(input_box, k2.WHITE)
	k2.draw_rect_outline(input_box, 1, k2.BLACK)
	k2.draw_text(typed_text, pos, 30, k2.BLACK)
}

button :: proc(r: Rect, text: string) -> bool {
	in_rect := point_in_rect(k2.get_mouse_position(), r)

	bg_color := k2.LIGHT_GREEN

	if in_rect {
		bg_color = k2.LIGHT_RED

		if k2.mouse_button_is_held(.Left) {
			bg_color = k2.LIGHT_PURPLE
		}
	}
	
	k2.draw_rect(r, bg_color)
	k2.draw_rect_outline(r, 1, k2.DARK_BLUE)

	textr := inset_rect(r, 5, 5)
	text_width := k2.measure_text(text, textr.h).x
	k2.draw_text(text, {textr.x + textr.w/2 - text_width/2, textr.y}, textr.h, k2.BLACK)

	if in_rect && k2.mouse_button_went_down(.Left) {
		return true
	}

	return false
}

point_in_rect :: proc(p: Vec2, r: Rect) -> bool {
	return p.x >= r.x &&
	   p.x < r.x + r.w &&
	   p.y >= r.y &&
	   p.y < r.y + r.h
}

inset_rect :: proc(r: Rect, x: f32, y: f32) -> Rect {
	return {
		r.x + x,
		r.y + y,
		r.w - x * 2,
		r.h - y * 2,
	}
}