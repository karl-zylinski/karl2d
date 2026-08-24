// This example shows multi touch input: drag with one finger to pan, pinch with two to zoom and
// rotate, tap to drop a marker. Touch screens are only supported on web, so run this as a web
// build to use one. On desktop, press M to have the mouse produce touches instead.
package karl2d_touch_example

import k2 "../.."
import "core:fmt"
import "core:math"
import "core:math/linalg"

Vec2 :: k2.Vec2

camera: k2.Camera

MIN_ZOOM :: 0.25
MAX_ZOOM :: 8
TAP_SLOP :: 20 // display-independent pixels of finger wobble we still count as a tap
TEXT_MARGIN :: 20 // in display-independent pixels

// Tracks how far a finger has travelled since it went down, for the tap check below.
Finger :: struct {
	id: k2.Touch_Id,
	travelled: f32,
}

fingers: [k2.MAX_TOUCHES]Finger
fingers_count: int

// Keeps the pinch pair in a consistent order between frames. If the two touches swapped places in
// the list, the angle between them would flip by pi while the zoom would look perfectly fine.
pinch_ids: [2]k2.Touch_Id
pinch_active: bool

markers: [dynamic]Vec2

// Whether the M key has turned on mouse-to-touch emulation.
mouse_emulates_touch: bool

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

	// This example handles both touches and the mouse itself, so the mouse must not also produce
	// touches: one drag would pan the camera twice. Press M to turn that back on.
	k2.set_touch_events_from_mouse(false)
}

step :: proc() -> bool {
	if !k2.update() {
		return false
	}

	screen_size := k2.get_screen_size()
	camera.offset = screen_size/2

	// The screen is in physical pixels, so anything sized in display-independent ones scales by
	// this. Also the UI camera's zoom further down.
	ui_scale := k2.get_window_scale()

	if k2.key_went_down(.M) {
		mouse_emulates_touch = !mouse_emulates_touch
		k2.set_touch_events_from_mouse(mouse_emulates_touch)
	}

	touches := k2.get_touches()

	// TRACK FINGERS

	for t in touches {
		if t.went_down && fingers_count < len(fingers) {
			fingers[fingers_count] = { id = t.id }
			fingers_count += 1
		}
	}

	tap_slop := TAP_SLOP*ui_scale

	// Fingers added just above are in here too, which is what makes a tap that goes down and up
	// inside a single frame still count.
	for t in touches {
		for i in 0..<fingers_count {
			f := &fingers[i]

			if f.id != t.id {
				continue
			}

			f.travelled += linalg.length(t.delta)

			if t.went_up {
				if !t.cancelled && f.travelled < tap_slop {
					append(&markers, k2.screen_to_camera(t.position, camera))
				}

				fingers[i] = fingers[fingers_count - 1]
				fingers_count -= 1
			}

			break
		}
	}

	// COLLECT THE FINGERS THAT CAN DRIVE A GESTURE
	//
	// A finger that just landed or just left has no meaningful delta, so it sits this frame out.

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
	// One finger only. Two fingers are a pinch, which does its own panning below.

	if gesture_count == 1 {
		// The drag is in screen pixels but `target` is in world space: un-rotate and un-zoom it.
		rotation_matrix := linalg.matrix2_rotate(-camera.rotation)
		camera.target -= rotation_matrix * (gesture[0].delta / camera.zoom)
	}

	// PINCH ZOOM AND ROTATE
	//
	// `position - delta` is where a finger was last frame, so comparing the pair now and then gives
	// both a zoom ratio and a rotation angle without any extra state.

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
			// Grab the world point that was between the fingers last frame, then put it back
			// between them after zooming and rotating. Moving the fingers across the screen moves
			// that point with them, so this one correction pans as well.
			anchor := k2.screen_to_camera((prev_a + prev_b) / 2, camera)

			camera.zoom = clamp(camera.zoom * (dist/prev_dist), MIN_ZOOM, MAX_ZOOM)

			now_angle := math.atan2(now_b.y - now_a.y, now_b.x - now_a.x)
			prev_angle := math.atan2(prev_b.y - prev_a.y, prev_b.x - prev_a.x)

			// Wrapped, or crossing atan2's +/-pi line would report a whole extra turn.
			camera.rotation += wrap_angle(now_angle - prev_angle)

			camera.target += anchor - k2.screen_to_camera((now_a + now_b) / 2, camera)
		}
	} else {
		pinch_active = false
	}

	// MOUSE FALLBACK
	//
	// Touch emulation is off (see `init`), so the mouse drives the camera directly here. Skipped
	// while M has the mouse producing touches, or the same drag would pan twice.

	if !mouse_emulates_touch {
		if k2.mouse_button_is_held(.Left) {
			rotation_matrix := linalg.matrix2_rotate(-camera.rotation)
			camera.target -= rotation_matrix * (k2.get_mouse_delta() / camera.zoom)
		}

		if wheel := k2.get_mouse_wheel_delta(); wheel != 0 {
			// Same anchor trick as the pinch above, just with one point instead of two.
			mouse_pos := k2.get_mouse_position()
			anchor := k2.screen_to_camera(mouse_pos, camera)

			camera.zoom = clamp(camera.zoom * (wheel > 0 ? 1.1 : 0.9), MIN_ZOOM, MAX_ZOOM)

			camera.target += anchor - k2.screen_to_camera(mouse_pos, camera)
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

	// DRAW UI
	//
	// Drawn through `ui_camera`, so nothing here pans, zooms or rotates with the map. Its zoom is
	// the display scale: the screen is in physical pixels, so fixed sizes would come out tiny on a
	// 3x phone display. Everything below is in display-independent pixels.

	ui_camera := k2.Camera { zoom = ui_scale }

	k2.set_camera(ui_camera)

	// The size of the UI camera's view, which the layout below is positioned against.
	ui_size := screen_size/ui_scale

	for t in touches {
		color := k2.WHITE

		if t.went_down {
			color = k2.GREEN
		} else if t.cancelled {
			color = k2.RED
		} else if t.went_up {
			color = k2.BLUE
		}

		// Touches are in physical screen pixels, so bring them into the UI camera's space.
		position := k2.screen_to_camera(t.position, ui_camera)

		id_text := fmt.tprintf("%v", t.id)

		if t.id == k2.EMULATED_TOUCH_ID {
			id_text = "mouse"
		}

		k2.draw_circle_outline(position, 30, 4, color)
		k2.draw_text(id_text, position + { 60, -12 }, 24, color)
	}

	if gesture_count == 2 {
		k2.draw_line(
			k2.screen_to_camera(gesture[0].position, ui_camera),
			k2.screen_to_camera(gesture[1].position, ui_camera),
			2,
			k2.YELLOW,
		)
	}

	// The help text is the widest thing on screen, so it decides the text layout. The mouse hints
	// don't fit on a phone, and don't apply there either, so they are dropped. If the text is still
	// too wide, in a very narrow window, it shrinks the rest of the way.

	help_full := [?]string {
		"drag with one finger to pan (or hold the left mouse button)",
		"pinch with two fingers to zoom and rotate (or use the mouse wheel)",
		"tap to drop a marker",
	}

	help_short := [?]string {
		"drag with one finger to pan",
		"pinch with two fingers to zoom and rotate",
		"tap to drop a marker",
	}

	widest_line :: proc(lines: []string, font_size: f32) -> f32 {
		widest: f32

		for l in lines {
			widest = max(widest, k2.measure_text(l, font_size).x)
		}

		return widest
	}

	text_width := ui_size.x - TEXT_MARGIN*2
	font_size := f32(20)
	help := help_full[:]
	mouse_hints := true

	if widest_line(help, font_size) > text_width {
		help = help_short[:]
		mouse_hints = false
	}

	if widest := widest_line(help, font_size); widest > text_width {
		font_size *= text_width/widest
	}

	text_pos := Vec2 { TEXT_MARGIN, TEXT_MARGIN }

	// Draws one line of stats and returns where the next one goes.
	draw_stat :: proc(text: string, pos: Vec2, font_size: f32) -> Vec2 {
		k2.draw_text(text, pos, font_size, k2.WHITE)
		return pos + { 0, font_size }
	}

	text_pos = draw_stat(fmt.tprintf("touches: %v", len(touches)), text_pos, font_size)
	text_pos = draw_stat(fmt.tprintf("zoom: x%.2f", camera.zoom), text_pos, font_size)
	rotation_stat := fmt.tprintf("rotation: %.0f deg", math.to_degrees(camera.rotation))
	text_pos = draw_stat(rotation_stat, text_pos, font_size)
	text_pos = draw_stat(fmt.tprintf("markers: %v", len(markers)), text_pos, font_size)

	mouse_emu_color := mouse_emulates_touch ? k2.GREEN : k2.WHITE
	mouse_emu_text := fmt.tprintf("mouse emulates touch: %v", mouse_emulates_touch)

	if mouse_hints {
		mouse_emu_text = fmt.tprintf("mouse emulates touch: %v (M to toggle)", mouse_emulates_touch)
	}

	k2.draw_text(mouse_emu_text, text_pos, font_size, mouse_emu_color)

	text_pos = { TEXT_MARGIN, ui_size.y - TEXT_MARGIN - font_size }

	#reverse for line in help {
		k2.draw_text(line, text_pos, font_size, k2.YELLOW)
		text_pos.y -= font_size
	}

	// Same y as the first line of stats text above, so the two line up along the top.
	BUTTON_HEIGHT :: 24
	BUTTON_PADDING :: 25 // in display-independent pixels

	button_bar := k2.Rect {
		TEXT_MARGIN,
		TEXT_MARGIN,
		ui_size.x - TEXT_MARGIN*2,
		BUTTON_HEIGHT,
	}
	button_width := k2.ui_button_width("Source Code", BUTTON_HEIGHT) + BUTTON_PADDING
	button_rect := k2.rect_cut_right(&button_bar, button_width, 0)

	if k2.ui_button(button_rect, "Source Code") {
		k2.open_url("https://github.com/karl-zylinski/karl2d/blob/master/examples/touch/touch.odin")
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
