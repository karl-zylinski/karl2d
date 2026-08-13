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
			screen_rotation(0.5),
		)
	})

	// Half extents 32x16 rotated by 0.5 rad: 32*|cos|+16*|sin| wide, 32*|sin|+16*|cos| tall.
	expect_bounds(t, got, 6, 200 - 35.75, 150 - 29.38, 200 + 35.75, 150 + 29.38)
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
		round_tripped.x, round_tripped.y, p.x, p.y,
	)
}
