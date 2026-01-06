package karl2d_gamepad_example

import k2 "../.."
import "core:fmt"
import "core:log"

gamepad_demo :: proc(gamepad: k2.Gamepad_Index, offset: k2.Vec2) {
	if !k2.is_gamepad_active(gamepad) {
		title := fmt.tprintf("Gamepad %v (not connected)", gamepad + 1)
		ts := k2.measure_text(title, 30)
		k2.draw_text(title, offset + {250, 60} - {ts.x/2, 0}, 30, k2.WHITE)
		return
	}

	title := fmt.tprintf("Gamepad %v", gamepad + 1)
	ts := k2.measure_text(title, 30)
	k2.draw_text(title, offset + {250, 60} - {ts.x/2, 0}, 30, k2.WHITE)

	button_color :: proc(
		gamepad: k2.Gamepad_Index,
		button: k2.Gamepad_Button,
		active := k2.WHITE,
		inactive := k2.GRAY,
	) -> k2.Color {
		return k2.gamepad_button_is_held(gamepad, button) ? active : inactive
	}

	g := gamepad
	o := offset
	k2.draw_circle(o + {120, 120}, 10, button_color(g, .Left_Face_Up))
	k2.draw_circle(o + {120, 160}, 10, button_color(g, .Left_Face_Down))
	k2.draw_circle(o + {100, 140}, 10, button_color(g, .Left_Face_Left))
	k2.draw_circle(o + {140, 140}, 10, button_color(g, .Left_Face_Right))

	k2.draw_circle(o + {320+50, 120}, 10, button_color(g, .Right_Face_Up))
	k2.draw_circle(o + {320+50, 160}, 10, button_color(g, .Right_Face_Down))
	k2.draw_circle(o + {300+50, 140}, 10, button_color(g, .Right_Face_Left))
	k2.draw_circle(o + {340+50, 140}, 10, button_color(g, .Right_Face_Right))

	k2.draw_rect_vec(o + {250 - 30, 140}, {20, 10}, button_color(g, .Middle_Face_Left))
	k2.draw_rect_vec(o + {250 + 10, 140}, {20, 10}, button_color(g, .Middle_Face_Right))

	left_stick := k2.Vec2 {
		k2.get_gamepad_axis(gamepad, .Left_Stick_X),
		k2.get_gamepad_axis(gamepad, .Left_Stick_Y),
	}

	right_stick := k2.Vec2 {
		k2.get_gamepad_axis(gamepad, .Right_Stick_X),
		k2.get_gamepad_axis(gamepad, .Right_Stick_Y),
	}

	left_trigger  := k2.get_gamepad_axis(gamepad, .Left_Trigger)
	right_trigger := k2.get_gamepad_axis(gamepad, .Right_Trigger)

	k2.set_gamepad_vibration(gamepad, left_trigger, right_trigger)

	k2.draw_rect_vec(o + {80, 50}, {20, 10}, button_color(g, .Left_Shoulder))
	k2.draw_rect_vec(o + {50, 50} + {0, left_trigger * 20}, {20, 10}, button_color(g, .Left_Trigger, k2.WHITE, k2.GRAY))

	k2.draw_rect_vec(o + {420, 50}, {20, 10}, button_color(g, .Right_Shoulder))
	k2.draw_rect_vec(o + {450, 50} + {0, right_trigger * 20}, {20, 10}, button_color(g, .Right_Trigger, k2.WHITE, k2.GRAY))
	k2.draw_circle(o + {200, 200} + 20 * left_stick, 20, button_color(g, .Left_Stick_Press, k2.WHITE, k2.GRAY))
	k2.draw_circle(o + {300, 200} + 20 * right_stick, 20, button_color(g, .Right_Stick_Press, k2.WHITE, k2.GRAY))
}

main :: proc() {
	context.logger = log.create_console_logger()
	init()
	for step() {}
	shutdown()
}

init :: proc() {
	k2.init(1000, 600, "Karl2D Gamepad Demo")
}

step :: proc() -> bool {
	if !k2.update() {
		return false
	}

	k2.clear(k2.BLACK)

	gamepad_demo(0, {0, 0})
	gamepad_demo(1, {500, 0})
	gamepad_demo(2, {0, 300})
	gamepad_demo(3, {500, 300})

	k2.present()
	free_all(context.temp_allocator)
	return true
}

shutdown :: proc() {
	k2.shutdown()
}