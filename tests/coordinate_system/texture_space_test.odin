// Checks that a texture source rectangle selects the same image rows under both cameras.
package karl2d_coordinate_system_test

import k2 "../.."
import "core:testing"

TEX_W :: 64
TEX_H :: 96

expect_v :: proc(t: ^testing.T, got: Bounds, top_v, bottom_v: f32, loc := #caller_location) {
	ok :=
		got.vertex_count == 6 &&
		abs(got.top_v - top_v) <= 0.0001 &&
		abs(got.bottom_v - bottom_v) <= 0.0001

	testing.expectf(t, ok,
		"flip_y=%v: expected 6 vertices with v %.4f..%.4f, got %v with v %.4f..%.4f",
		flip_y, top_v, bottom_v, got.vertex_count, got.top_v, got.bottom_v, loc = loc,
	)
}

@(test)
whole_texture_is_not_mirrored :: proc(t: ^testing.T) {
	for flip in FLIPS {
		flip_y = flip

		got := draw_and_measure(proc() {
			k2.draw_texture(uv_texture, screen_box_pos(50, 60, TEX_H))
		})

		expect_v(t, got, 0, 1)
	}
}

@(test)
atlas_frames_select_the_same_rows :: proc(t: ^testing.T) {
	for flip in FLIPS {
		flip_y = flip

		top := draw_and_measure(proc() {
			k2.draw_texture_fit(uv_texture, { 0, 0, TEX_W, TEX_H/3 }, screen_rect(50, 60, 64, 32))
		})

		bottom := draw_and_measure(proc() {
			k2.draw_texture_fit(uv_texture, { 0, 2*TEX_H/3, TEX_W, TEX_H/3 }, screen_rect(50, 60, 64, 32))
		})

		expect_v(t, top, 0, 1.0/3)
		expect_v(t, bottom, 2.0/3, 1)
	}
}

@(test)
negative_source_height_flips_the_texture :: proc(t: ^testing.T) {
	for flip in FLIPS {
		flip_y = flip

		got := draw_and_measure(proc() {
			k2.draw_texture_fit(uv_texture, { 0, TEX_H/3, TEX_W, -TEX_H/3 }, screen_rect(50, 60, 64, 32))
		})

		expect_v(t, got, 2.0/3, 1.0/3)
	}
}
