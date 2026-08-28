// Drawing a render texture back onto the screen.
//
// OpenGL and WebGL store render textures bottom-up, so `texture_needs_vertical_flip` returns true
// for them and `draw_texture_fit` compensates. D3D11 and the nil backend never do, so the whole
// compensation path is invisible to a headless test on Windows -- which is where the coordinate
// system tests ran. These tests force the flag on so the path is exercised in both coordinate
// systems.
//
// The flag is what a real GL build reports, and it is right in both coordinate systems: whichever
// way Karl2D's Y points, its projection sends the visual top of the surface to NDC +1, and GL
// stores NDC +1 in the last row of memory. So the memory is upside down compared to an image file
// either way.
package karl2d_coordinate_system_test

import k2 "../.."
import "core:testing"

RT_W :: 64
RT_H :: 96

flipped_texture: k2.Texture

// Stands in for a GL render texture: the same handle a real backend would flag.
pretend_texture_needs_vertical_flip :: proc(handle: k2.Texture_Handle) -> bool {
	return handle == flipped_texture.handle
}

// As `top_and_bottom_v`, but with the flip flag forced on for `flipped_texture`.
top_and_bottom_v_flipped :: proc(draw: proc()) -> (top_v, bottom_v: f32, ok: bool) {
	setup()

	real_flip := state.render_backend.texture_needs_vertical_flip
	state.render_backend.texture_needs_vertical_flip = pretend_texture_needs_vertical_flip
	k2.set_internal_state(state)

	defer {
		state.render_backend.texture_needs_vertical_flip = real_flip
		k2.set_internal_state(state)
	}

	return top_and_bottom_v(draw)
}

// A whole render texture drawn back must come out the right way up. Since its memory is upside
// down, the top of the screen has to sample v = 1.
@(test)
whole_render_texture_is_upright :: proc(t: ^testing.T) {
	top_v, bottom_v, ok := top_and_bottom_v_flipped(proc() {
		k2.draw_texture(flipped_texture, screen_box_pos(50, 60, RT_H))
	})

	if !testing.expect(t, ok, "nothing was drawn") {
		return
	}

	expect_v(t, top_v, 1, "top of screen samples the last row of memory")
	expect_v(t, bottom_v, 0, "bottom of screen samples the first row of memory")
}

// A sub-rect of a render texture is still measured top-down from the visual top, like any other
// texture. Taking the top third must show the top third, in both coordinate systems.
@(test)
render_texture_source_rect_is_still_top_down :: proc(t: ^testing.T) {
	third :: f32(RT_H)/3

	// Top third of what was drawn into the render texture. It lives in the last third of memory.
	top_v, bottom_v, ok := top_and_bottom_v_flipped(proc() {
		k2.draw_texture_fit(flipped_texture, { 0, 0, RT_W, f32(RT_H)/3 }, screen_rect(50, 60, 64, 32))
	})

	if !testing.expect(t, ok, "nothing was drawn") {
		return
	}

	expect_v(t, top_v, 1, "top third: top")
	expect_v(t, bottom_v, 2*third/RT_H, "top third: bottom")

	// Bottom third of what was drawn. It lives in the first third of memory.
	top_v, bottom_v, ok = top_and_bottom_v_flipped(proc() {
		k2.draw_texture_fit(
			flipped_texture,
			{ 0, 2*f32(RT_H)/3, RT_W, f32(RT_H)/3 },
			screen_rect(50, 60, 64, 32),
		)
	})

	if !testing.expect(t, ok, "nothing was drawn") {
		return
	}

	expect_v(t, top_v, third/RT_H, "bottom third: top")
	expect_v(t, bottom_v, 0, "bottom third: bottom")
}
