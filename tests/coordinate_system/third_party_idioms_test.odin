// What a third-party renderer written against Karl2D does and does not have to change for Y up.
//
// Unlike the rest of this package these tests do NOT translate into screen space first. They use
// the idioms a UI or layout library would write naturally, in the coordinate system it was written
// for, and record which of them survive the flip and which invert. That difference is the porting
// surface a Clay/microui/imgui-style renderer would face.
package karl2d_coordinate_system_test

import k2 "../.."
import "core:testing"

// SURVIVES: hit testing. A Rect always spans [y, y+h] in world units and the mouse is reported in
// the same units, so the usual point-in-rect test needs no change.
@(test)
point_in_rect_is_coordinate_system_agnostic :: proc(t: ^testing.T) {
	point_in_rect :: proc(p: k2.Vec2, r: k2.Rect) -> bool {
		return p.x >= r.x && p.x < r.x + r.w && p.y >= r.y && p.y < r.y + r.h
	}

	r := k2.Rect { 10, 100, 200, 40 }

	testing.expect(t, point_in_rect({ 15, 105 }, r), "a point just inside must be inside")
	testing.expect(t, !point_in_rect({ 15, 145 }, r), "a point past y+h must be outside")
	testing.expect(t, !point_in_rect({ 15, 95 }, r), "a point before y must be outside")
}

// SURVIVES: a symmetric inset, and text drawn at a rect's anchor. `examples/ui`'s button draws its
// label at `textr.y`, and the label lands inside the button in both systems because draw_text and
// draw_rect share an anchor.
@(test)
label_at_a_rects_anchor_lands_inside_the_rect :: proc(t: ^testing.T) {
	button := k2.Rect { 10, 100, 200, 40 }
	inset := k2.Rect { button.x + 5, button.y + 5, button.w - 10, button.h - 10 }

	label := draw_and_measure_text("Click Me", inset.h, k2.FONT_DEFAULT, { inset.x, inset.y })
	whole := draw_and_measure(proc() { k2.draw_rect(k2.Rect { 10, 100, 200, 40 }, k2.WHITE) })

	// The label's ink stays within the button's screen span, whichever way Y points.
	testing.expectf(t, label.top >= whole.top - 1 && label.bottom <= whole.bottom + 1,
		"label ink [%.2f, %.2f] escapes the button [%.2f, %.2f]",
		label.top, label.bottom, whole.top, whole.bottom,
	)
}

// BREAKS: stacking by adding to y. This is `examples/ui`'s list of random numbers, verbatim in
// spirit: `{15, 155 + idx*30}`. Adding to y walks down the screen in Y down and UP the screen in Y
// up, so the list reads in the opposite order. It compiles, it does not crash, nothing escapes its
// background rectangle -- the entries are simply in reverse.
//
// This is the whole of the third-party problem in one line. The library's own helpers are
// coordinate-system agnostic; hand-rolled vertical arithmetic is not, and a layout library is
// almost entirely hand-rolled vertical arithmetic.
@(test)
stacking_by_adding_to_y_inverts_the_order :: proc(t: ^testing.T) {
	first := draw_and_measure_text("0", 30, k2.FONT_DEFAULT, { 15, 155 + 0*30 })
	second := draw_and_measure_text("1", 30, k2.FONT_DEFAULT, { 15, 155 + 1*30 })

	when TEST_Y_UP {
		testing.expectf(t, first.top > second.top,
			"entry 0 (top %.2f) should be BELOW entry 1 (top %.2f) in Y up",
			first.top, second.top,
		)
	} else {
		testing.expectf(t, first.top < second.top,
			"entry 0 (top %.2f) should be above entry 1 (top %.2f) in Y down",
			first.top, second.top,
		)
	}
}

// SURVIVES: the same stack built with rect_cut_top and drawn under a screen camera.
//
// This is the answer for a third-party UI or layout renderer, and it is now a stronger one than it
// was under the build flag. `rect_cut_top` is screen-space and so is the camera here, so this code
// is not merely portable between two builds of Karl2D -- it is correct inside a program whose game
// world is Y up, without that program having to do anything. A renderer pushes its own screen
// camera and is done.
@(test)
stacking_with_rect_cut_top_keeps_the_order :: proc(t: ^testing.T) {
	area := k2.Rect { 15, 155, 200, 90 }

	row0 := k2.rect_cut_top(&area, 30, 0)
	row1 := k2.rect_cut_top(&area, 30, 0)

	pending_row_0 = { row0.x, row0.y }
	pending_row_1 = { row1.x, row1.y }

	first := draw_with_camera(SCREEN_CAMERA, proc() {
		k2.draw_text("0", pending_row_0, 30, k2.WHITE)
	})

	second := draw_with_camera(SCREEN_CAMERA, proc() {
		k2.draw_text("1", pending_row_1, 30, k2.WHITE)
	})

	testing.expectf(t, first.top < second.top,
		"row 0 (top %.2f) must be above row 1 (top %.2f)", first.top, second.top,
	)
}

pending_row_0: k2.Vec2
pending_row_1: k2.Vec2
