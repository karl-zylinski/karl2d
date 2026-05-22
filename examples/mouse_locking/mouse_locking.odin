// Shows how to lock/capture mouse cursor so that you can use it for non-cursor input.
package karl2d_mouse_locking_example

import k2 "../.."

init :: proc() {
	k2.init(1280, 720, "Karl2D Mouse Locking", options = {window_mode = .Windowed_Resizable})
	pos = k2.get_screen_size() * 0.5
}

pos: k2.Vec2

step :: proc() -> bool {
	if !k2.update() {
		return false
	}

	delta := k2.get_mouse_delta()

	if k2.key_went_down(.Escape) {
		k2.set_cursor_locked(false)
	}

	if k2.mouse_button_went_down(.Left) {
		k2.set_cursor_locked(true)
	}

	if k2.is_cursor_locked() {
		if !k2.is_cursor_hidden() {
			k2.set_cursor_hidden(true)
		}

		pos += delta * k2.get_frame_time() * 100
	} else {
		if k2.is_cursor_hidden() {
			k2.set_cursor_hidden(false)
		}
	}

	if pos.x > f32(k2.get_screen_width()) {
		pos.x = 0
	}

	if pos.y > f32(k2.get_screen_height()) {
		pos.y = 0
	}

	if pos.x < 0 {
		pos.x = f32(k2.get_screen_width())
	}

	if pos.y < 0 {
		pos.y = f32(k2.get_screen_height())
	}

	k2.clear(k2.LIGHT_BLUE)
	k2.draw_circle(pos, 10, k2.RED)
	k2.present()
	return true
}

shutdown :: proc() {
	k2.shutdown()
}

main :: proc() {
	init()
	for step() {}
	shutdown()
}
