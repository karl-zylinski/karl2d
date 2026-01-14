// This example shows how you can use `k2.get_events()` to fetch events. Most games would use
// procedures like `k2.mouse_button_went_down(.Left)` or `k2.key_is_held(.A)`. But if you want a
// list all events that happened this frame, then here is how to fetch them!
//
// This example stores a list of the 32 latest events and shows them on the screen. It also prints
// how many times the left mouse button has been clicked.
//
// If you rather want examples on how to use the `k2.key_is_held` etc procedures, then have a look
// at examples such as `basics`, `gamepads`, `mouse` and `snake`.
package karl2d_events_example

import k2 "../.."
import "core:fmt"

main :: proc() {
	k2.init(720, 1280, "Karl2D Events", options = { window_mode = .Windowed_Resizable })
	MAX_HISTORY :: 32
	event_history: [dynamic]k2.Event
	num_mouse_clicks := 0

	for k2.update() {
		events := k2.get_events()

		for event in events {
			#partial switch e in event {
			case k2.Event_Mouse_Button_Went_Down:
				if e.button == .Left {
					num_mouse_clicks += 1
				}
			}
		}

		append(&event_history, ..events)
		history_len := len(event_history)

		if history_len > MAX_HISTORY {
			copy(event_history[:], event_history[history_len - MAX_HISTORY:])
			resize(&event_history, MAX_HISTORY)
		}

		k2.clear(k2.LIGHT_BLUE)
		k2.draw_text(fmt.tprintf("Left mouse button pressed %v times", num_mouse_clicks), {10, 10}, 50)
		k2.draw_text(fmt.tprintf("%v latest events:", MAX_HISTORY), {10, 100}, 40)
		y_pos := f32(145)

		#reverse for te in event_history {
			k2.draw_text(fmt.tprint(te), {10, y_pos}, 30)
			y_pos += 35
		}

		k2.present()
		free_all(context.temp_allocator)
	}

	k2.shutdown()
}
