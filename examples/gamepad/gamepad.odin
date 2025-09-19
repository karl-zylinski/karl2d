package karl2d_gamepad_example

import k2 "../.."
import "core:log"

Vec2 :: [2]f32

button_color :: proc(button: k2.Gamepad_Button, active := k2.WHITE, inactive := k2.GRAY) -> k2.Color {
	return k2.gamepad_button_is_held(0, button) ? active : inactive
}

main :: proc() {
	context.logger = log.create_console_logger()
	k2.init(500, 300, "Karl2D Gamepad Demo")
	k2.set_window_position(300, 100)

	for !k2.shutdown_wanted() {
		k2.process_events()
		k2.clear(k2.BLACK)

		log.info(k2.get_window_scale())

		k2.draw_circle({120, 120}, 10, button_color(.Left_Face_Up))
		k2.draw_circle({120, 160}, 10, button_color(.Left_Face_Down))
		k2.draw_circle({100, 140}, 10, button_color(.Left_Face_Left))
		k2.draw_circle({140, 140}, 10, button_color(.Left_Face_Right))

		k2.draw_circle({320+50, 120}, 10, button_color(.Right_Face_Up))
		k2.draw_circle({320+50, 160}, 10, button_color(.Right_Face_Down))
		k2.draw_circle({300+50, 140}, 10, button_color(.Right_Face_Left))
		k2.draw_circle({340+50, 140}, 10, button_color(.Right_Face_Right))

		k2.draw_rect_vec({250 - 30, 140}, {20, 10}, button_color(.Middle_Face_Left))
		k2.draw_rect_vec({250 + 10, 140}, {20, 10}, button_color(.Middle_Face_Right))

		left_stick := Vec2 {
			k2.get_gamepad_axis(0, .Left_Stick_X),
			k2.get_gamepad_axis(0, .Left_Stick_Y),
		}

		right_stick := Vec2 {
			k2.get_gamepad_axis(0, .Right_Stick_X),
			k2.get_gamepad_axis(0, .Right_Stick_Y),
		}

		left_trigger  := k2.get_gamepad_axis(0, .Left_Trigger)
		right_trigger := k2.get_gamepad_axis(0, .Right_Trigger)

		k2.set_gamepad_vibration(0, left_trigger, right_trigger)

		k2.draw_rect_vec({80, 50}, {20, 10}, button_color(.Left_Shoulder))
		k2.draw_rect_vec({50, 50} + {0, left_trigger * 20}, {20, 10}, button_color(.Left_Trigger, k2.WHITE, k2.GRAY))

		k2.draw_rect_vec({420, 50}, {20, 10}, button_color(.Right_Shoulder))
		k2.draw_rect_vec({450, 50} + {0, right_trigger * 20}, {20, 10}, button_color(.Right_Trigger, k2.WHITE, k2.GRAY))
		k2.draw_circle({200, 200} + 20 * left_stick, 20, button_color(.Left_Stick_Press, k2.WHITE, k2.GRAY))
		k2.draw_circle({300, 200} + 20 * right_stick, 20, button_color(.Right_Stick_Press, k2.WHITE, k2.GRAY))

		k2.present()
		free_all(context.temp_allocator)
	}

	k2.shutdown()
}