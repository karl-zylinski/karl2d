package karl2d_gamepad_example

import k2 "../.."
import "core:log"
import "core:fmt"

init :: proc() {
	k2.init(1000, 600, "Karl2D Mouse Demo")
}

wheel: f32

step :: proc() -> bool {
	k2.new_frame()
	k2.process_events()
	k2.clear(k2.BLUE)

	pos := k2.get_mouse_position()
	k2.draw_circle(pos, 50, k2.WHITE)

	left_pos := pos - {30, 20}
	middle_pos := pos - {0, 30}
	right_pos := pos - {-30, 20}

	left_color := k2.BLACK
	middle_color := k2.BLACK
	right_color := k2.BLACK

	if k2.mouse_button_went_down(.Left) {
		left_color = k2.GREEN
	} else if k2.mouse_button_is_held(.Left) {
		left_color = k2.YELLOW
	} else if k2.mouse_button_went_up(.Left) {
		left_color = k2.RED
	}

	if k2.mouse_button_went_down(.Middle) {
		middle_color = k2.GREEN
	} else if k2.mouse_button_is_held(.Middle) {
		middle_color = k2.YELLOW
	} else if k2.mouse_button_went_up(.Middle) {
		middle_color = k2.RED
	}

	if k2.mouse_button_went_down(.Right) {
		right_color = k2.GREEN
	} else if k2.mouse_button_is_held(.Right) {
		right_color = k2.YELLOW
	} else if k2.mouse_button_went_up(.Right) {
		right_color = k2.RED
	}

	k2.draw_circle(left_pos, 10, left_color)
	k2.draw_circle(middle_pos, 10, middle_color)
	k2.draw_circle(right_pos, 10, right_color)

	wheel += k2.get_mouse_wheel_delta()

	wheel_msg := fmt.tprintf("Wheel: %.1f", wheel)
	wheel_msg_width := k2.measure_text(wheel_msg, 20).x
	k2.draw_text(wheel_msg, pos + {-wheel_msg_width/2, 70}, 20, k2.WHITE)

	k2.present()
	free_all(context.temp_allocator)
	return !k2.shutdown_wanted()
}

shutdown :: proc() {
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
