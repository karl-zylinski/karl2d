// Checks what the existing texture test only claims: that a `source` rectangle selects the same
// pixels of the image in both coordinate systems.
//
// `draw_texture_fit_source_rect_stays_top_down` measures vertex positions only, so it passes
// whatever the UVs say. These tests capture the UVs as well and check which row of the image ends
// up at the top of the screen.
package karl2d_coordinate_system_test

import k2 "../.."
import "core:sync"
import "core:testing"

TEX_W :: 64
TEX_H :: 96

// A vertex as the render backend received it: where it is on screen and what it samples.
UV_Vertex :: struct {
	y_from_top: f32,
	v: f32,
}

captured_uvs: [dynamic]UV_Vertex

capture_uv_draw :: proc(vertex_buffer: []u8, draw_calls: []k2.Draw_Call) {
	pos_offset := state.current_shader.default_input_offsets[.Position]
	uv_offset := state.current_shader.default_input_offsets[.UV]

	if pos_offset < 0 || uv_offset < 0 {
		return
	}

	view_projection := state.proj_matrix * state.view_matrix

	for dc in draw_calls {
		if dc.vertex_size == 0 {
			continue
		}

		for i in 0..<dc.vertex_count {
			base := dc.vertex_offset + i*dc.vertex_size
			p := (^k2.Vec2)(&vertex_buffer[base + pos_offset])^
			uv := (^k2.Vec2)(&vertex_buffer[base + uv_offset])^

			ndc := view_projection * k2.Vec4 { p.x, p.y, 0, 1 }

			append(&captured_uvs, UV_Vertex {
				y_from_top = (1 - ndc.y) * 0.5 * SURFACE_H,
				v = uv.y,
			},
		)
		}
	}
}

// The v coordinate sampled at the top of the drawn quad and at the bottom, in screen terms, using
// the camera for the space this run is checking.
top_and_bottom_v :: proc(draw: proc()) -> (top_v, bottom_v: f32, ok: bool) {
	return top_and_bottom_v_with_camera(TEST_CAMERA, draw)
}

// As `top_and_bottom_v`, but with an explicit camera, so one run can compare the two spaces.
top_and_bottom_v_with_camera :: proc(
	camera: Maybe(k2.Camera),
	draw: proc(),
) -> (top_v, bottom_v: f32, ok: bool) {
	setup()

	sync.mutex_lock(&draw_mutex)
	defer sync.mutex_unlock(&draw_mutex)

	real_draw := state.render_backend.draw
	state.render_backend.draw = capture_uv_draw
	k2.set_internal_state(state)

	defer {
		state.render_backend.draw = real_draw
		k2.set_internal_state(state)
		k2.set_camera(nil)
	}

	clear(&captured_uvs)
	k2.set_camera(camera)
	draw()
	k2.draw_current_batch()

	if len(captured_uvs) == 0 {
		return 0, 0, false
	}

	highest := captured_uvs[0]
	lowest := captured_uvs[0]

	for c in captured_uvs[1:] {
		if c.y_from_top < highest.y_from_top { highest = c }
		if c.y_from_top > lowest.y_from_top  { lowest = c }
	}

	return highest.v, lowest.v, true
}

expect_v :: proc(t: ^testing.T, got, expected: f32, what: string, loc := #caller_location) {
	testing.expectf(t, abs(got - expected) <= 0.0001,
		"%v: expected v = %.4f, got %.4f", what, expected, got, loc = loc,
	)
}

// A whole texture must come out the right way up: the first row of the image at the top of screen.
@(test)
whole_texture_is_not_mirrored :: proc(t: ^testing.T) {
	top_v, bottom_v, ok := top_and_bottom_v(proc() {
		k2.draw_texture(uv_texture, screen_box_pos(50, 60, TEX_H))
	})

	if !testing.expect(t, ok, "nothing was drawn") {
		return
	}

	expect_v(t, top_v, 0, "top of screen samples the top of the image")
	expect_v(t, bottom_v, 1, "bottom of screen samples the bottom of the image")
}

// The middle frame of a three-row atlas. This is the case that separates "source.y counted from the
// top" from "source.y counted from the bottom": for the middle frame of three, the two answers are
// the same, so the frame either side is what pins it down.
@(test)
atlas_frame_selects_the_same_rows_in_both_systems :: proc(t: ^testing.T) {
	frame_h :: f32(TEX_H)/3

	// Frame 0 is the top third of the image.
	top_v, bottom_v, ok := top_and_bottom_v(proc() {
		k2.draw_texture_fit(uv_texture, { 0, 0, TEX_W, f32(TEX_H)/3 }, screen_rect(50, 60, 64, 32))
	})

	if !testing.expect(t, ok, "nothing was drawn") {
		return
	}

	expect_v(t, top_v, 0, "frame 0 top")
	expect_v(t, bottom_v, frame_h/TEX_H, "frame 0 bottom")

	// Frame 2 is the bottom third. Counting source.y from the bottom would give frame 0 here.
	top_v, bottom_v, ok = top_and_bottom_v(proc() {
		k2.draw_texture_fit(
			uv_texture,
			{ 0, 2*f32(TEX_H)/3, TEX_W, f32(TEX_H)/3 },
			screen_rect(50, 60, 64, 32),
		)
	})

	if !testing.expect(t, ok, "nothing was drawn") {
		return
	}

	expect_v(t, top_v, 2*frame_h/TEX_H, "frame 2 top")
	expect_v(t, bottom_v, 1, "frame 2 bottom")
}

// A negative source height flips the image vertically, in both coordinate systems.
@(test)
negative_source_height_flips_the_texture :: proc(t: ^testing.T) {
	top_v, bottom_v, ok := top_and_bottom_v(proc() {
		k2.draw_texture_fit(
			uv_texture,
			{ 0, f32(TEX_H)/3, TEX_W, -f32(TEX_H)/3 },
			screen_rect(50, 60, 64, 32),
		)
	})

	if !testing.expect(t, ok, "nothing was drawn") {
		return
	}

	// A negative height keeps `source.y` as the edge it started from and takes the height off in
	// the other direction, so this is frame 1, drawn upside down.
	expect_v(t, top_v, 2*f32(TEX_H)/3/TEX_H, "flipped frame top")
	expect_v(t, bottom_v, f32(TEX_H)/3/TEX_H, "flipped frame bottom")
}
