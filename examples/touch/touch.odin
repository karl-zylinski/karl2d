package karl2d_touch_example

// Touch-only for now: this example never reads the mouse. Windows and web currently still turn a
// touch into an emulated mouse click behind the scenes, so if this example also handled the mouse
// the same way `examples/camera` does, a one-finger drag would pan the map twice and jump. A later
// change takes that emulation over from the OS and brings the mouse fallback back here.

import k2 "../.."
import "core:fmt"
import "core:math"
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

// Which two touches are driving the pinch, so the pair keeps a consistent order between frames.
// Position in the touch list is not enough: if the two swapped places, the angle between them would
// flip by pi and spin the camera half a turn, while the distance between them (and so the zoom)
// would look perfectly fine.
pinch_ids: [2]k2.Touch_Id
pinch_active: bool

markers: [dynamic]Vec2

// Brings an angle into (-pi, pi].
wrap_angle :: proc(a: f32) -> f32 {
	wrapped := math.mod(a + math.PI, 2*math.PI)

	if wrapped < 0 {
		wrapped += 2*math.PI
	}

	return wrapped - math.PI
}

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
		if t.went_down && fingers_count < len(fingers) {
			fingers[fingers_count] = { id = t.id }
			fingers_count += 1
		}

		for i in 0..<fingers_count {
			f := &fingers[i]
			if f.id != t.id {
				continue
			}

			f.travelled += linalg.length(t.delta)

			// A quick tap can go down and up within the same frame, so this has to run even for a
			// finger that was added just above. Otherwise its slot is never freed.
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

		// The drag is in screen pixels but `target` lives in world space, so it has to be un-rotated
		// as well as un-zoomed. Without the rotation part, panning heads off at an angle as soon as
		// the map has been rotated.
		rotation_matrix := linalg.matrix2_rotate(-camera.rotation)
		camera.target -= rotation_matrix * ((drag/f32(gesture_count)) / camera.zoom)
	}

	// PINCH ZOOM AND ROTATE
	//
	// Two fingers: compare their positions now to where they were last frame (`position - delta` is
	// where a finger was last frame, so no extra state is needed) to get both a zoom ratio and a
	// rotation angle out of the same pair of points.

	if gesture_count == 2 {
		a, b := gesture[0], gesture[1]

		// Keep whichever finger was `a` last frame as `a` this frame. See `pinch_ids`.
		if pinch_active && a.id == pinch_ids[1] && b.id == pinch_ids[0] {
			a, b = b, a
		}

		pinch_ids = { a.id, b.id }
		pinch_active = true

		now_a, now_b := a.position, b.position
		prev_a, prev_b := a.position - a.delta, b.position - b.delta

		dist := linalg.distance(now_a, now_b)
		prev_dist := linalg.distance(prev_a, prev_b)

		if dist > 1 && prev_dist > 1 {
			// Apply zoom and rotation around the point between the fingers, so whatever bit of the
			// map is under the pinch stays under the pinch. This works the same way as the camera
			// zoom below: read the world point under the pinch center before changing anything,
			// then nudge `target` so that same world point is back under the pinch center after.
			pinch_center := (now_a + now_b) / 2
			anchor := k2.screen_to_world(pinch_center, camera)

			camera.zoom = clamp(camera.zoom * (dist/prev_dist), MIN_ZOOM, MAX_ZOOM)

			now_angle := math.atan2(now_b.y - now_a.y, now_b.x - now_a.x)
			prev_angle := math.atan2(prev_b.y - prev_a.y, prev_b.x - prev_a.x)

			// atan2 jumps between +pi and -pi, so a gesture crossing that line would otherwise
			// report a whole extra turn in a single frame.
			camera.rotation += wrap_angle(now_angle - prev_angle)

			camera.target += anchor - k2.screen_to_world(pinch_center, camera)
		}
	} else {
		pinch_active = false
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

	// DRAW UI
	//
	// Everything from here on is screen-space: one `k2.set_camera(nil)` for the touch markers, the
	// stats, the hints and the buttons, so none of it pans, zooms or rotates with the world camera
	// above. A finger stays under its own circle no matter how far the map underneath has been
	// pinched or spun.
	//
	// Sizes here are all multiplied by `ui_scale`. The screen is measured in physical pixels, so on
	// a phone with a 3x display anything drawn at a fixed pixel size comes out a third of the size
	// it does on a desktop monitor. Scaling by the window scale corrects that, and is separate from
	// the world camera's zoom.
	//
	// The scale is capped, since following it all the way up overshoots: a phone's screen is
	// physically much smaller than a monitor, so UI that measures the same in display-independent
	// pixels eats a far bigger share of it.

	k2.set_camera(nil)

	MAX_UI_SCALE :: 2

	ui_scale := min(k2.get_window_scale(), MAX_UI_SCALE)

	for t in touches {
		color := k2.WHITE

		if t.went_down {
			color = k2.GREEN
		} else if t.cancelled {
			color = k2.RED
		} else if t.went_up {
			color = k2.BLUE
		}

		k2.draw_circle_outline(t.position, 60*ui_scale, 4*ui_scale, color)
		k2.draw_text(
			fmt.tprintf("%v", t.id),
			t.position + Vec2 { 70, -12 }*ui_scale,
			24*ui_scale,
			color,
		)
	}

	if gesture_count == 2 {
		k2.draw_line(gesture[0].position, gesture[1].position, 2*ui_scale, k2.YELLOW)
	}

	font_size := 28*ui_scale
	text_pos := Vec2 { 20, 20 }*ui_scale

	draw_stat :: proc(text: string, pos: ^Vec2, font_size: f32) {
		k2.draw_text(text, pos^, font_size, k2.WHITE)
		pos.y += font_size
	}

	draw_stat(fmt.tprintf("touches: %v", len(touches)), &text_pos, font_size)
	draw_stat(fmt.tprintf("zoom: x%.2f", camera.zoom), &text_pos, font_size)
	draw_stat(fmt.tprintf("rotation: %.0f deg", math.to_degrees(camera.rotation)), &text_pos, font_size)
	draw_stat(fmt.tprintf("markers: %v", len(markers)), &text_pos, font_size)

	font_size = 24*ui_scale
	text_color := k2.YELLOW
	text_pos = { 20*ui_scale, screen_size.y - 20*ui_scale - font_size }

	k2.draw_text("tap to drop a marker", text_pos, font_size, text_color)
	text_pos.y -= font_size

	k2.draw_text("pinch with two fingers to zoom and rotate", text_pos, font_size, text_color)
	text_pos.y -= font_size

	k2.draw_text("drag with one or more fingers to pan", text_pos, font_size, text_color)
	text_pos.y -= font_size

	screen_rect := k2.rect_from_pos_size({}, k2.get_screen_size())
	bottom_bar := k2.rect_cut_bottom(&screen_rect, 36*ui_scale, 0)
	bottom_bar = k2.rect_shrink(bottom_bar, 4*ui_scale, 4*ui_scale)

	button_rect :: proc(text: string, r: ^k2.Rect, ui_scale: f32) -> k2.Rect {
		return k2.rect_cut_right(r, k2.ui_button_width(text, r.h) + 25*ui_scale, 5*ui_scale)
	}

	if k2.ui_button(button_rect("Source code", &bottom_bar, ui_scale), "Source Code") {
		k2.open_url("https://github.com/karl-zylinski/karl2d/blob/master/examples/touch/touch.odin")
	}

	if k2.ui_button(button_rect("Fullscreen", &bottom_bar, ui_scale), "Fullscreen") {
		k2.set_window_mode(.Borderless_Fullscreen)
	}

	if k2.ui_button(button_rect("Windowed", &bottom_bar, ui_scale), "Windowed") {
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
