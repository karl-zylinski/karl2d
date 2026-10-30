// Checks drawing a texture that the backend stores bottom-up, as OpenGL and WebGL do with render
// textures.
package karl2d_coordinate_system_test

import k2 "../.."
import "core:testing"

pretend_texture_needs_vertical_flip :: proc(s: ^k2.Render_Backend_State, handle: k2.Render_Backend_Texture) -> bool {
	return true
}

draw_and_measure_flipped_texture :: proc(draw: proc()) -> Bounds {
	setup()

	real_flip := state.rb.texture_needs_vertical_flip
	state.rb.texture_needs_vertical_flip = pretend_texture_needs_vertical_flip
	k2.set_internal_state(state)

	res := draw_and_measure(draw)

	state.rb.texture_needs_vertical_flip = real_flip
	k2.set_internal_state(state)
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
