package karl2d_example_monitors

import k2 "../.."
import "core:strings"
import "core:fmt"

main :: proc() {
	init()
	for step() {}
	shutdown()
}

init :: proc() {
	// Can be called before `k2.init`. Here we use temp allocator. Note that the slice returned
	// contains allocated monitor names. We don't need to care about that since temp allocator is
	// used.
	start_monitors := k2.get_monitors(context.temp_allocator)

	biggest_monitor: k2.Monitor_Id
	biggest_monitor_size: int

	for m in start_monitors {
		sz := m.physical_size.x * m.physical_size.y

		if sz > biggest_monitor_size {
			biggest_monitor = m.id
			biggest_monitor_size = sz
		}
	}

	// biggest_monitor may be 0 if the API retrned physical_size as 0 for all monitors. That's fine
	// the zero value means that the platform will pick on its own.
	k2.init(1280, 720, "Monitors Example", { monitor = biggest_monitor })
}

step :: proc() -> bool {
	if !k2.update() {
		return false
	}

	monitors := k2.get_monitors(context.temp_allocator)
	k2.clear(k2.DARK_BROWN)

	cam := k2.Camera {
		zoom = k2.get_window_scale(),
	}

	k2.set_camera(cam)

	current_monitor := k2.get_window_monitor()

	draw_pos := k2.Vec2 {20, 20}

	for m in monitors {
		if m.id == current_monitor {
			info_b := strings.builder_make(context.temp_allocator)
			strings.write_string(&info_b, "Current Monitor: ")
			strings.write_string(&info_b, m.name)
			strings.write_string(&info_b, " | Resolution: ")
			strings.write_int(&info_b, m.size.x)
			strings.write_string(&info_b, " x ")
			strings.write_int(&info_b, m.size.y)

			strings.write_string(&info_b, fmt.tprintf(" | Scale: %.2f ", m.scale))

			if m.physical_size != 0 {
				strings.write_string(&info_b, " | Physical Size: ")
				strings.write_int(&info_b, m.physical_size.x)
				strings.write_string(&info_b, " x ")
				strings.write_int(&info_b, m.physical_size.y)
				strings.write_string(&info_b, " mm")
			}

			k2.draw_text(strings.to_string(info_b), draw_pos, 20, k2.WHITE)
			draw_pos.y += 40
			break
		}
	}

	k2.draw_text("Click a button to switch screen:", draw_pos, 20, k2.WHITE)
	draw_pos.y += 25

	for m in monitors {
		r := k2.rect_from_pos_size(draw_pos, {300, 20})
		
		if k2.ui_button(r, m.name) {
			k2.set_window_monitor(m.id)
		}

		if current_monitor == m.id {
			k2.draw_text("<-- Current!", k2.rect_top_right(r) + {10, 0}, 20, k2.WHITE)
		}

		draw_pos.y += r.h + 5
	}

	draw_pos.y += 20
	is_fullscreen := k2.get_window_mode() == .Borderless_Fullscreen

	if k2.ui_button(
		k2.rect_from_pos_size(draw_pos, {300, 20}),
		is_fullscreen ? "Windowed" : "Fullscreen",
	) {
		k2.set_window_mode(is_fullscreen ? .Windowed : .Borderless_Fullscreen)
	}

	k2.present()
	free_all(context.temp_allocator)
	return true
}

shutdown :: proc() {
	k2.shutdown()
}