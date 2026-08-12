package karl2d_touch_example

// Touch-only for now: this example never reads the mouse. Windows and web currently still turn a
// touch into an emulated mouse click behind the scenes, so if this example also handled the mouse
// the same way `examples/camera` does, a one-finger drag would pan the map twice and jump. A later
// change takes that emulation over from the OS and brings the mouse fallback back here.

import k2 "../.."
import "core:fmt"
import "core:math/linalg"

Vec2 :: k2.Vec2

camera: k2.Camera

MIN_ZOOM :: 0.25
MAX_ZOOM :: 8
TAP_SLOP :: 20 // pixels of finger wobble we still count as a tap

// Taps need to know how far a finger has travelled since it went down, which isn't in `k2.Touch`.
// We keep our own small table for that, keyed on the touch id.
Finger :: struct {
	id: k2.Touch_Id,
	travelled: f32,
}

fingers: [k2.MAX_TOUCHES]Finger
fingers_count: int

markers: [dynamic]Vec2

init :: proc() {
	k2.init(1280, 720, "Karl2D Touch Demo", { window_mode = .Windowed_Resizable })
	camera = { zoom = 1 }
}

step :: proc() -> bool {
	if !k2.update() {
		return false
	}

	screen_size := k2.get_screen_size()
	camera.offset = screen_size/2

	touches := k2.get_touches()

	// TRACK FINGERS
	//
	// A touch that ended stays in `touches` for exactly this one frame (`went_up` is set), which is
	// what makes the tap check below work.

	for t in touches {
		if t.went_down {
			if fingers_count < len(fingers) {
				fingers[fingers_count] = { id = t.id }
				fingers_count += 1
			}
			continue
		}

		for i in 0..<fingers_count {
			f := &fingers[i]
			if f.id != t.id {
				continue
			}

			f.travelled += linalg.length(t.delta)

			if t.went_up {
				if !t.cancelled && f.travelled < TAP_SLOP {
					append(&markers, k2.screen_to_world(t.position, camera))
				}

				fingers[i] = fingers[fingers_count - 1]
				fingers_count -= 1
			}

			break
		}
	}

	// COLLECT THE FINGERS THAT CAN DRIVE A GESTURE
	//
	// A finger that just landed or just left doesn't have a meaningful delta yet (or anymore), so
	// it is left out of panning and pinching.

	gesture: [k2.MAX_TOUCHES]k2.Touch
	gesture_count: int

	for t in touches {
		if t.went_down || t.went_up {
			continue
		}

		gesture[gesture_count] = t
		gesture_count += 1
	}

	// PAN
	//
	// Average the individual finger deltas, rather than tracking the midpoint between the fingers.
	// That way putting down or lifting a finger mid-gesture doesn't make the map jump, since each
	// remaining finger still reports how far it personally moved.

	if gesture_count > 0 {
		drag: Vec2

		for t in gesture[:gesture_count] {
			drag += t.delta
		}

		camera.target -= (drag/f32(gesture_count)) / camera.zoom
	}

	// PINCH ZOOM
	//
	// Two fingers: compare how far apart they are now with how far apart they were last frame.
	// `position - delta` is where a finger was last frame, so no extra state is needed for this.

	if gesture_count == 2 {
		a, b := gesture[0], gesture[1]

		dist := linalg.distance(a.position, b.position)
		prev_dist := linalg.distance(a.position - a.delta, b.position - b.delta)

		if dist > 1 && prev_dist > 1 {
			// Zoom around the point between the fingers, so whatever bit of the map is under the
			// pinch stays under the pinch.
			pinch_center := (a.position + b.position) / 2
			anchor := k2.screen_to_world(pinch_center, camera)

			camera.zoom = clamp(camera.zoom * (dist/prev_dist), MIN_ZOOM, MAX_ZOOM)

			camera.target += anchor - k2.screen_to_world(pinch_center, camera)
		}
	}

	// DRAW MAP

	k2.set_camera(camera)
	k2.clear({ 20, 24, 32, 255 })

	TILE :: 128

	for y in -8..=8 {
		for x in -8..=8 {
			tile := k2.Rect { f32(x)*TILE, f32(y)*TILE, TILE - 4, TILE - 4 }
			shade := u8(40 + ((x + y) %% 2)*14)
			k2.draw_rect(tile, { shade, shade + 10, shade + 6, 255 })
		}
	}

	for m in markers {
		k2.draw_circle(m, 14, k2.YELLOW)
		k2.draw_circle_outline(m, 22, 3, k2.color_alpha(k2.YELLOW, 120))
	}

	// DRAW TOUCHES

	k2.set_camera(nil)

	for t in touches {
		color := k2.WHITE

		if t.went_down {
			color = k2.GREEN
		} else if t.cancelled {
			color = k2.RED
		} else if t.went_up {
			color = k2.BLUE
		}

		k2.draw_circle_outline(t.position, 60, 4, color)
		k2.draw_text(fmt.tprintf("%v", t.id), t.position + { 70, -12 }, 24, color)
	}

	if gesture_count == 2 {
		k2.draw_line(gesture[0].position, gesture[1].position, 2, k2.YELLOW)
	}

	// DRAW STATS

	font_size := f32(28)
	text_pos := Vec2 { 20, 20 }

	draw_stat :: proc(text: string, pos: ^Vec2, font_size: f32) {
		k2.draw_text(text, pos^, font_size, k2.WHITE)
		pos.y += font_size
	}

	draw_stat(fmt.tprintf("touches: %v", len(touches)), &text_pos, font_size)
	draw_stat(fmt.tprintf("zoom: x%.2f", camera.zoom), &text_pos, font_size)
	draw_stat(fmt.tprintf("markers: %v", len(markers)), &text_pos, font_size)

	// DRAW HINTS

	font_size = 24
	text_color := k2.YELLOW
	text_pos = { 20, screen_size.y - 20 - font_size }

	k2.draw_text("tap to drop a marker", text_pos, font_size, text_color)
	text_pos.y -= font_size

	k2.draw_text("pinch with two fingers to zoom", text_pos, font_size, text_color)
	text_pos.y -= font_size

	k2.draw_text("drag with one or more fingers to pan", text_pos, font_size, text_color)
	text_pos.y -= font_size

	screen_rect := k2.rect_from_pos_size({}, k2.get_screen_size())
	bottom_bar := k2.rect_cut_bottom(&screen_rect, 36, 0)
	bottom_bar = k2.rect_shrink(bottom_bar, 4, 4)

	button_rect :: proc(text: string, r: ^k2.Rect) -> k2.Rect {
		return k2.rect_cut_right(r, k2.ui_button_width(text, r.h) + 25, 5)
	}

	if k2.ui_button(button_rect("Source code", &bottom_bar), "Source Code") {
		k2.open_url("https://github.com/karl-zylinski/karl2d/blob/master/examples/touch/touch.odin")
	}

	if k2.ui_button(button_rect("Fullscreen", &bottom_bar), "Fullscreen") {
		k2.set_window_mode(.Borderless_Fullscreen)
	}

	if k2.ui_button(button_rect("Windowed", &bottom_bar), "Windowed") {
		k2.set_window_mode(.Windowed_Resizable)
	}

	k2.present()
	free_all(context.temp_allocator)
	return true
}

shutdown :: proc() {
	delete(markers)
	k2.shutdown()
}

main :: proc() {
	init()
	for step() {}
	shutdown()
}
