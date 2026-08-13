// Cases the original coordinate system tests left out: rotation applied to text and textures, and
// cameras that do more than zoom.
//
// Same rule as the rest of the package: everything is positioned in screen space, so the expected
// values hold in both coordinate systems and running the package twice is the check.
package karl2d_coordinate_system_test

import k2 "../.."
import "core:testing"

// A rotated texture sweeps the same screen area either way. `screen_rotation` negates in Y up,
// which is the whole of the difference: the rotation direction, not the geometry.
@(test)
rotated_texture_covers_the_same_screen_area :: proc(t: ^testing.T) {
	got := draw_and_measure(proc() {
		pivot := screen_pos(200, 150)
		k2.draw_texture_fit(
			the_texture,
			{ 0, 0, 64, 32 },
			{ pivot.x, pivot.y, 64, 32 },
			{ 32, 16 },
			screen_rotation(0.5))
	})

	// Half extents 32x16 rotated by 0.5 rad: 32*|cos|+16*|sin| wide, 32*|sin|+16*|cos| tall.
	expect_bounds(t, got, 6, 200 - 35.75, 150 - 29.38, 200 + 35.75, 150 + 29.38)
}

// Rotating text pivots the whole block around `position`, not each glyph around itself, and it
// sweeps the same screen area in both coordinate systems.
@(test)
rotated_text_sweeps_the_same_screen_area :: proc(t: ^testing.T) {
	// Unrotated first, so the rotated bounds can be compared against something measured rather
	// than a constant that would have to be recomputed if the font changed.
	flat := draw_and_measure(proc() {
		draw_text_at_screen_top("Ag", 20, k2.FONT_DEFAULT)
	})

	rotated := draw_and_measure(proc() {
		height := k2.measure_text("Ag", 20, k2.FONT_DEFAULT).y
		k2.draw_text(
			"Ag",
			screen_box_pos(100, 100, height),
			20,
			k2.WHITE,
			k2.FONT_DEFAULT,
			rotation = screen_rotation(0.3))
	})

	if !testing.expect(t, rotated.vertex_count == flat.vertex_count, "glyph count changed") {
		return
	}

	// A rotation about a point inside the block makes it cover more, never less, and it stays in
	// the same neighbourhood. The exact numbers are pinned by both builds having to agree.
	testing.expectf(t, rotated.bottom - rotated.top > flat.bottom - flat.top,
		"rotated text is not taller than flat text: %.2f vs %.2f",
		rotated.bottom - rotated.top, flat.bottom - flat.top)

	// NOT the same bounds in both systems, and deliberately recorded as such. With origin = {} the
	// pivot is `position`, which is the block's top-left corner on screen in Y down and its
	// bottom-left corner in Y up. Rotating the same block about two different corners puts it in
	// two different places: the gap is (I - R(0.3)) * (0, -20), i.e. (5.91, 0.89).
	//
	// This matches draw_rect, whose pivot is likewise the Rect's (x, y) anchor -- see
	// `rotated_rect_pivots_around_the_anchor_corner`. It is the documentation that is wrong, not
	// this: the `origin` parameter is described as being relative to "the top-left corner"
	// unconditionally.
	when TEST_Y_UP {
		expect_bounds(t, rotated, flat.vertex_count, 99.93, 102.51, 124.49, 127.16)
	} else {
		expect_bounds(t, rotated, flat.vertex_count, 94.02, 101.62, 118.58, 126.27)
	}
}

// The same pivot-corner difference, on the procedure text inherits it from. A rect rotated with
// origin = {} spins about its (x, y), which is a different corner on screen in each system.
@(test)
rotated_rect_pivots_around_the_anchor_corner :: proc(t: ^testing.T) {
	got := draw_and_measure(proc() {
		k2.draw_rect(screen_rect(100, 100, 40, 20), k2.WHITE, {}, screen_rotation(0.3))
	})

	// Y down pivots about the screen top-left of the rect, Y up about its screen bottom-left, so
	// the swept area differs by (I - R(0.3)) * (0, -20) = (5.91, 0.89), the same as the text case.
	when TEST_Y_UP {
		expect_bounds(t, got, 6, 100.00, 100.89, 144.12, 131.82)
	} else {
		expect_bounds(t, got, 6, 94.09, 100.00, 138.21, 130.93)
	}
}

// A camera offset is a screen-space shift, so the same offset has to move things the same way on
// screen in both coordinate systems.
@(test)
camera_offset_shifts_the_same_way_on_screen :: proc(t: ^testing.T) {
	// The camera is left set for the measurement and cleared afterwards: `draw_and_measure` reads
	// the view matrix after running this, so clearing it here would measure through an identity
	// view and see nothing the camera did.
	got := draw_and_measure(proc() {
		// Target the rect's own screen position and offset to a fixed screen point, which should
		// put the rect there regardless of where it lives in world space.
		k2.set_camera(k2.Camera {
			target = screen_pos(100, 100),
			offset = screen_pos(300, 200),
			zoom = 1,
			y_axis = TEST_Y_AXIS,
		})

		k2.draw_rect(screen_rect(100, 100, 40, 20), k2.WHITE)
	})

	k2.set_camera(nil)

	// The rect's top-left was at screen (100, 100) and the camera puts that point at (300, 200).
	expect_bounds(t, got, 6, 300, 200, 340, 220)
}

// screen_to_camera and camera_to_screen have to invert each other whichever way Y points.
@(test)
screen_to_camera_round_trips :: proc(t: ^testing.T) {
	setup()

	cam := k2.Camera {
		target = screen_pos(100, 100),
		offset = screen_pos(300, 200),
		zoom = 2,
		rotation = screen_rotation(0.4),
		y_axis = TEST_Y_AXIS,
	}

	p := screen_pos(123, 45)
	round_tripped := k2.camera_to_screen(k2.screen_to_camera(p, cam), cam)

	testing.expectf(t,
		abs(round_tripped.x - p.x) <= EPSILON && abs(round_tripped.y - p.y) <= EPSILON,
		"round trip gave (%.3f, %.3f), expected (%.3f, %.3f)",
		round_tripped.x, round_tripped.y, p.x, p.y)
}

// A scissor rectangle reaches the backend untouched: it is screen-space in both coordinate spaces,
// which is what D3D11 and OpenGL want, so there is nothing left to convert.
@(test)
scissor_uses_the_render_target_height :: proc(t: ^testing.T) {
	got := draw_and_measure(proc() {
		k2.set_scissor_rect(k2.Rect { 10, 20, 100, 50 })
		k2.draw_rect(screen_rect(10, 20, 100, 50), k2.WHITE)
		k2.set_scissor_rect(nil)
	})

	scissor, has_scissor := got.scissor.?

	if !testing.expect(t, has_scissor, "no scissor rectangle reached the render backend") {
		return
	}

	testing.expectf(t,
		abs(scissor.x - 10) <= EPSILON && abs(scissor.y - 20) <= EPSILON &&
		abs(scissor.w - 100) <= EPSILON && abs(scissor.h - 50) <= EPSILON,
		"expected native scissor (10, 20, 100, 50), got (%.2f, %.2f, %.2f, %.2f)",
		scissor.x, scissor.y, scissor.w, scissor.h)
}
