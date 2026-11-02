// Checks drawing a texture that the backend stores bottom-up, as OpenGL and WebGL do with render
// textures.
package karl2d_coordinate_system_test

import k2 "../.."
import hm "core:container/handle_map"
import "core:testing"

draw_and_measure_flipped_texture :: proc(draw: proc()) -> Bounds {
	setup()

	uv_texture_object := hm.get(&state.textures, uv_texture)
	real_flip := uv_texture_object.flip_y
	uv_texture_object.flip_y = true

	res := draw_and_measure(draw)

	uv_texture_object.flip_y = real_flip
	return res
}

@(test)
whole_flipped_texture_is_upright :: proc(t: ^testing.T) {
	for flip in FLIPS {
		flip_y = flip

		got := draw_and_measure_flipped_texture(proc() {
			k2.draw_texture(uv_texture, screen_box_pos(50, 60, TEX_H))
		})

		expect_v(t, got, 1, 0)
	}
}

@(test)
flipped_texture_source_rect_is_still_top_down :: proc(t: ^testing.T) {
	for flip in FLIPS {
		flip_y = flip

		top := draw_and_measure_flipped_texture(proc() {
			k2.draw_texture_fit(uv_texture, { 0, 0, TEX_W, TEX_H/3 }, screen_rect(50, 60, 64, 32))
		})

		bottom := draw_and_measure_flipped_texture(proc() {
			k2.draw_texture_fit(uv_texture, { 0, 2*TEX_H/3, TEX_W, TEX_H/3 }, screen_rect(50, 60, 64, 32))
		})

		expect_v(t, top, 1, 2.0/3)
		expect_v(t, bottom, 1.0/3, 0)
	}
}
