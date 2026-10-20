// Checks for no camera, switching cameras mid-frame and converting points between screen and camera.
package karl2d_coordinate_system_test

import k2 "../.."
import "core:slice"
import "core:testing"

@(test)
no_camera_is_the_screen_space :: proc(t: ^testing.T) {
	got := draw_and_measure(proc() {
		k2.set_camera(nil)
		k2.draw_rect({ 10, 20, 30, 40 }, k2.WHITE)
	})

	expect_bounds(t, got, 6, 10, 20, 40, 60)
}

@(test)
switching_back_to_screen_space_mid_frame :: proc(t: ^testing.T) {
	draw_and_measure(proc() {
		k2.set_camera(nil)
		k2.draw_rect({ 20, 20, 100, 30 }, k2.WHITE)
	})

	alone := slice.clone(captured_vertices[:], context.temp_allocator)

	draw_and_measure(proc() {
		k2.set_camera(k2.Camera { zoom = 1, flip_y = true })
		k2.draw_rect({ 500, 500, 10, 10 }, k2.WHITE)
		k2.set_camera(nil)
		k2.draw_rect({ 20, 20, 100, 30 }, k2.WHITE)
	})

	if !testing.expectf(t, len(alone) == 6 && len(captured_vertices) == 12,
		"expected 6 and 12 vertices, got %v and %v", len(alone), len(captured_vertices)) {
		return
	}

	testing.expectf(t, slice.equal(alone, captured_vertices[6:]),
		"vertices moved after a Y up camera: %v became %v", alone, captured_vertices[6:],
	)
}

@(test)
screen_to_camera_flips_and_round_trips :: proc(t: ^testing.T) {
	setup()

	flip_y = false
	expect_vec(t, k2.screen_to_camera({ 300, 200 }, k2.Camera { zoom = 1 }), { 300, 200 })
	expect_vec(t, k2.screen_to_camera({ 300, 200 }, k2.Camera { zoom = 1, flip_y = true }), { 300, SURFACE_H - 200 })

	for flip in FLIPS {
		flip_y = flip

		cameras := [2]k2.Camera {
			{
				target = screen_pos(100, 100),
				offset = screen_pos(300, 200),
				zoom = 2,
				rotation = screen_rotation(0.4),
				flip_y = flip,
			},
			{ flip_y = flip },
		}

		for cam in cameras {
			p := screen_pos(123, 45)
			expect_vec(t, k2.camera_to_screen(k2.screen_to_camera(p, cam), cam), p)
		}
	}
}
