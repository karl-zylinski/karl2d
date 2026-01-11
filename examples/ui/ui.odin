// Some simple UI things that show how to make a button and some advanced sizing tricks

package karl2d_ui_example

import k2 "../.."
import "core:fmt"
import "core:math/rand"
import "core:math"

Rect :: k2.Rect
Vec2 :: k2.Vec2

main :: proc() {
	k2.init(1280, 720, "Karl2D: Simple UI")
	button_click_count: int
	random_numbers: [dynamic]int

	for k2.update() {
		k2.clear(k2.LIGHT_BLUE)

		if button({10, 10, 200, 40}, "Click Me") {
			button_click_count += 1
			sz := rand.int_max(9) + 1
			append(&random_numbers, rand.int_max(int(math.pow(f32(10), f32(sz)))))
		}

		k2.draw_text(fmt.tprintf("Button has been clicked %v times", button_click_count), {300, 15}, 30)

		numbers_bg_rect := Rect { 10, 100, 400, f32(len(random_numbers) * 30)}
		k2.draw_rect(numbers_bg_rect, k2.LIGHT_GREEN)
		k2.draw_rect_outline(numbers_bg_rect, 1, k2.BLACK)

		for n, idx in random_numbers {
			k2.draw_text(fmt.tprint(n), {10, 100 + f32(idx) * 30}, 30)
		}

		k2.present()
		free_all(context.temp_allocator)
	}

	k2.shutdown()
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
	text_width := k2.measure_text(text, r.h).x
	k2.draw_text(text, {r.x + r.w/2 - text_width/2, r.y}, r.h)

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