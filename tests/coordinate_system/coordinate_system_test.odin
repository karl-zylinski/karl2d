// Checks that a Y down camera and a Y up camera draw the same picture on screen. Run with
// -define:KARL2D_RENDER_BACKEND=nil -define:KARL2D_AUDIO_BACKEND=nil -define:ODIN_TEST_THREADS=1.
package karl2d_coordinate_system_test

import k2 "../.."
import "base:runtime"
import "core:testing"

SURFACE_W :: 800
SURFACE_H :: 600
EPSILON :: 0.05
FLIPS :: [2]bool { false, true }

Vertex :: struct {
	pos: k2.Vec2,
	uv: k2.Vec2,
}

Bounds :: struct {
	vertex_count: int,
	left, right: f32,
	top, bottom: f32,
	top_v, bottom_v: f32,
	scissor: Maybe(k2.Rect),
}

state: ^k2.State
flip_y: bool
captured_vertices: [dynamic]Vertex
captured_scissor: Maybe(k2.Rect)
the_texture: k2.Texture
uv_texture: k2.Texture
the_static_font: k2.Font
text_to_draw: string
font_to_draw: k2.Font

screen_y :: proc(y_from_top: f32) -> f32 {
	if flip_y {
		return SURFACE_H - y_from_top
	}

	return y_from_top
}

screen_pos :: proc(x, y_from_top: f32) -> k2.Vec2 {
	return { x, screen_y(y_from_top) }
}

screen_rect :: proc(x, y_from_top, w, h: f32) -> k2.Rect {
	if flip_y {
		return { x, screen_y(y_from_top + h), w, h }
	}

	return { x, y_from_top, w, h }
}

screen_box_pos :: proc(x, y_from_top, h: f32) -> k2.Vec2 {
	r := screen_rect(x, y_from_top, 0, h)
	return { r.x, r.y }
}

screen_rotation :: proc(radians: f32) -> f32 {
	if flip_y {
		return -radians
	}

	return radians
}

capture_draw :: proc(
	s: ^k2.Render_Backend_State,
	vertex_buffer: []u8,
	draw_calls: []k2.Draw_Call,
) {
	pos_offset := state.current_shader.default_input_offsets[.Position]
	uv_offset := state.current_shader.default_input_offsets[.UV]

	if pos_offset < 0 || uv_offset < 0 {
		return
	}

	for dc in draw_calls {
		captured_scissor = dc.scissor

		if dc.vertex_size == 0 {
			continue
		}

		for i in 0..<dc.vertex_count {
			base := dc.vertex_offset + i*dc.vertex_size

			append(&captured_vertices, Vertex {
				pos = (^k2.Vec2)(&vertex_buffer[base + pos_offset])^,
				uv = (^k2.Vec2)(&vertex_buffer[base + uv_offset])^,
			})
		}
	}
}

setup :: proc() {
	if state != nil {
		return
	}

	stable := runtime.heap_allocator()
	context.allocator = stable

	captured_vertices = make([dynamic]Vertex, 0, 1024, stable)
	state = k2.init(1280, 720, "karl2d coordinate system tests", allocator = stable)
	state.rb.draw = capture_draw
	k2.set_internal_state(state)

	k2.set_render_texture(k2.create_render_texture(SURFACE_W, SURFACE_H))
	the_texture = k2.create_texture(64, 32, .RGBA_8_Norm)
	uv_texture = k2.create_texture(TEX_W, TEX_H, .RGBA_8_Norm)
	the_static_font = k2.load_static_font_from_bytes(k2.DEFAULT_FONT_DATA, 20)
}

draw_and_measure :: proc(draw: proc()) -> Bounds {
	setup()

	clear(&captured_vertices)
	captured_scissor = nil

	k2.set_camera(k2.Camera { zoom = 1, flip_y = flip_y })
	draw()
	k2.draw_current_batch()
	view_projection := state.proj_matrix * state.view_matrix
	k2.set_camera(nil)

	res := Bounds {
		vertex_count = len(captured_vertices),
		left = max(f32),
		right = min(f32),
		top = max(f32),
		bottom = min(f32),
		scissor = captured_scissor,
	}

	for v in captured_vertices {
		ndc := view_projection * k2.Vec4 { v.pos.x, v.pos.y, 0, 1 }
		x := (ndc.x + 1) * 0.5 * SURFACE_W
		y := (1 - ndc.y) * 0.5 * SURFACE_H

		res.left = min(res.left, x)
		res.right = max(res.right, x)

		if y < res.top {
			res.top = y
			res.top_v = v.uv.y
		}

		if y > res.bottom {
			res.bottom = y
			res.bottom_v = v.uv.y
		}
	}

	return res
}

draw_text_at_screen_top :: proc(text: string, font: k2.Font) {
	height := k2.measure_text(text, 20, font).y
	k2.draw_text(text, screen_box_pos(100, 100, height), 20, k2.WHITE, font)
}

draw_and_measure_text :: proc(text: string, font: k2.Font) -> Bounds {
	text_to_draw = text
	font_to_draw = font

	return draw_and_measure(proc() {
		draw_text_at_screen_top(text_to_draw, font_to_draw)
	})
}

expect_bounds :: proc(
	t: ^testing.T,
	got: Bounds,
	vertex_count: int,
	left, top, right, bottom: f32,
	loc := #caller_location,
) {
	ok :=
		got.vertex_count == vertex_count &&
		abs(got.left - left) <= EPSILON &&
		abs(got.right - right) <= EPSILON &&
		abs(got.top - top) <= EPSILON &&
		abs(got.bottom - bottom) <= EPSILON

	testing.expectf(t, ok,
		"flip_y=%v: expected %v vertices in l=%.2f t=%.2f r=%.2f b=%.2f, got %v in l=%.2f t=%.2f r=%.2f b=%.2f",
		flip_y, vertex_count, left, top, right, bottom,
		got.vertex_count, got.left, got.top, got.right, got.bottom, loc = loc,
	)
}

expect_vec :: proc(t: ^testing.T, got, expected: k2.Vec2, loc := #caller_location) {
	testing.expectf(t, abs(got.x - expected.x) <= EPSILON && abs(got.y - expected.y) <= EPSILON,
		"flip_y=%v: expected %v, got %v", flip_y, expected, got, loc = loc,
	)
}

expect_text :: proc(
	t: ^testing.T,
	text: string,
	font: k2.Font,
	vertex_count: int,
	left, top, right, bottom: f32,
	loc := #caller_location,
) {
	got := draw_and_measure_text(text, font)
	expect_bounds(t, got, vertex_count, left, top, right, bottom, loc)

	box_bottom := 100 + k2.measure_text(text, 20, font).y

	testing.expectf(t, got.top >= 100 - 1.5 && got.bottom <= box_bottom + 1.5,
		"flip_y=%v: ink [%.2f, %.2f] escapes measured box [100, %.2f]",
		flip_y, got.top, got.bottom, box_bottom, loc = loc,
	)
}

@(test)
draw_rect_covers_its_screen_rectangle :: proc(t: ^testing.T) {
	for flip in FLIPS {
		flip_y = flip

		got := draw_and_measure(proc() {
			k2.draw_rect(screen_rect(100, 100, 40, 20), k2.WHITE)
		})

		expect_bounds(t, got, 6, 100, 100, 140, 120)
	}
}

@(test)
draw_rect_rotates_the_same_way_on_screen :: proc(t: ^testing.T) {
	for flip in FLIPS {
		flip_y = flip

		got := draw_and_measure(proc() {
			pivot := screen_pos(120, 110)
			k2.draw_rect({ pivot.x, pivot.y, 40, 20 }, k2.WHITE, { 20, 10 }, screen_rotation(0.5))
		})

		expect_bounds(t, got, 6, 97.64, 91.65, 142.36, 128.37)
	}
}

@(test)
draw_rect_outline_covers_its_screen_rectangle :: proc(t: ^testing.T) {
	for flip in FLIPS {
		flip_y = flip

		got := draw_and_measure(proc() {
			k2.draw_rect_outline(screen_rect(100, 100, 40, 20), 2, k2.WHITE)
		})

		expect_bounds(t, got, 24, 100, 100, 140, 120)
	}
}

@(test)
draw_circle_is_centred_on_its_screen_position :: proc(t: ^testing.T) {
	for flip in FLIPS {
		flip_y = flip

		got := draw_and_measure(proc() {
			k2.draw_circle(screen_pos(200, 150), 30, k2.WHITE, 8)
		})

		expect_bounds(t, got, 24, 170, 120, 230, 180)
	}
}

@(test)
draw_line_spans_its_screen_endpoints :: proc(t: ^testing.T) {
	for flip in FLIPS {
		flip_y = flip

		got := draw_and_measure(proc() {
			k2.draw_line(screen_pos(10, 20), screen_pos(120, 90), 3, k2.WHITE)
		})

		expect_bounds(t, got, 6, 9.20, 18.72, 120.80, 91.26)
	}
}

@(test)
draw_texture_grows_out_of_its_position_like_a_rect :: proc(t: ^testing.T) {
	for flip in FLIPS {
		flip_y = flip

		got := draw_and_measure(proc() {
			k2.draw_texture(the_texture, screen_box_pos(50, 60, 32))
		})

		expect_bounds(t, got, 6, 50, 60, 114, 92)
	}
}

@(test)
draw_texture_fit_covers_its_screen_rectangle :: proc(t: ^testing.T) {
	for flip in FLIPS {
		flip_y = flip

		got := draw_and_measure(proc() {
			k2.draw_texture_fit(the_texture, { 8, 4, 32, 16 }, screen_rect(50, 60, 64, 32))
		})

		expect_bounds(t, got, 6, 50, 60, 114, 92)
	}
}

@(test)
rotated_texture_covers_the_same_screen_area :: proc(t: ^testing.T) {
	for flip in FLIPS {
		flip_y = flip

		got := draw_and_measure(proc() {
			pivot := screen_pos(200, 150)
			k2.draw_texture_fit(the_texture, { 0, 0, 64, 32 }, { pivot.x, pivot.y, 64, 32 }, { 32, 16 }, screen_rotation(0.5))
		})

		expect_bounds(t, got, 6, 164.25, 120.62, 235.75, 179.38)
	}
}

@(test)
draw_text_is_placed_like_a_rect :: proc(t: ^testing.T) {
	setup()

	for flip in FLIPS {
		flip_y = flip
		expect_text(t, "Ag", k2.FONT_DEFAULT, 12, 99, 102, 120.79, 120.99)
		expect_text(t, "Ag\nBh", k2.FONT_DEFAULT, 24, 99, 102, 120.85, 137.01)
		expect_text(t, "Ag", the_static_font, 12, 100, 102.84, 119.80, 119.82)
		expect_text(t, "Ag\nBh", the_static_font, 24, 100, 102.84, 119.84, 135.84)
	}
}

@(test)
first_line_of_text_is_above_the_second :: proc(t: ^testing.T) {
	setup()

	for flip in FLIPS {
		flip_y = flip

		for font in ([2]k2.Font { k2.FONT_DEFAULT, the_static_font }) {
			draw_and_measure_text("A\nB", font)

			if !testing.expectf(t, len(captured_vertices) == 12,
				"flip_y=%v: expected 12 vertices, got %v", flip_y, len(captured_vertices)) {
				continue
			}

			first := max(f32)
			second := max(f32)

			for v in captured_vertices[:6] {
				first = min(first, screen_y(v.pos.y))
			}

			for v in captured_vertices[6:] {
				second = min(second, screen_y(v.pos.y))
			}

			testing.expectf(t, first < second,
				"flip_y=%v: first line at %.2f is not above second line at %.2f", flip_y, first, second,
			)
		}
	}
}

@(test)
draw_text_under_a_zoomed_camera :: proc(t: ^testing.T) {
	for flip in FLIPS {
		flip_y = flip

		got := draw_and_measure(proc() {
			k2.set_camera(k2.Camera { zoom = 2, flip_y = flip_y })
			draw_text_at_screen_top("Ag", k2.FONT_DEFAULT)
		})

		if flip {
			expect_bounds(t, got, 12, 199, -394, 240.58, -359)
		} else {
			expect_bounds(t, got, 12, 199, 206, 240.58, 241)
		}
	}
}

@(test)
scissor_is_screen_space_under_both_cameras :: proc(t: ^testing.T) {
	for flip in FLIPS {
		flip_y = flip

		got := draw_and_measure(proc() {
			k2.set_scissor_rect(k2.Rect { 100, 50, 200, 120 })
			k2.draw_rect(screen_rect(100, 100, 40, 20), k2.WHITE)
			k2.set_scissor_rect(nil)
		})

		expect_bounds(t, got, 6, 100, 100, 140, 120)
		testing.expectf(t, got.scissor == k2.Rect { 100, 50, 200, 120 },
			"flip_y=%v: expected scissor (100, 50, 200, 120), got %v", flip_y, got.scissor,
		)
	}
}

@(test)
camera_offset_shifts_the_same_way_on_screen :: proc(t: ^testing.T) {
	for flip in FLIPS {
		flip_y = flip

		got := draw_and_measure(proc() {
			k2.set_camera(k2.Camera {
				target = screen_pos(100, 100),
				offset = screen_pos(300, 200),
				zoom = 1,
				flip_y = flip_y,
			})

			k2.draw_rect(screen_rect(100, 100, 40, 20), k2.WHITE)
		})

		expect_bounds(t, got, 6, 300, 200, 340, 220)
	}
}

@(test)
zero_zoom_camera_draws_like_zoom_one :: proc(t: ^testing.T) {
	for flip in FLIPS {
		flip_y = flip

		got := draw_and_measure(proc() {
			k2.set_camera(k2.Camera { flip_y = flip_y })
			k2.draw_rect(screen_rect(100, 100, 40, 20), k2.WHITE)
		})

		expect_bounds(t, got, 6, 100, 100, 140, 120)
	}
}

@(test)
rect_helpers_ignore_the_camera :: proc(t: ^testing.T) {
	r := k2.Rect { 100, 100, 40, 20 }

	testing.expect_value(t, k2.rect_top_left(r), k2.Vec2 { 100, 100 })
	testing.expect_value(t, k2.rect_top_middle(r), k2.Vec2 { 120, 100 })
	testing.expect_value(t, k2.rect_top_right(r), k2.Vec2 { 140, 100 })
	testing.expect_value(t, k2.rect_bottom_left(r), k2.Vec2 { 100, 120 })
	testing.expect_value(t, k2.rect_bottom_middle(r), k2.Vec2 { 120, 120 })
	testing.expect_value(t, k2.rect_bottom_right(r), k2.Vec2 { 140, 120 })
	testing.expect_value(t, k2.rect_middle(r), k2.Vec2 { 120, 110 })

	top := k2.rect_cut_top(&r, 5, 1)
	testing.expect_value(t, top, k2.Rect { 100, 101, 40, 5 })
	testing.expect_value(t, r.y, 106)

	r = { 100, 100, 40, 20 }
	bottom := k2.rect_cut_bottom(&r, 5, 1)
	testing.expect_value(t, bottom, k2.Rect { 100, 114, 40, 5 })
	testing.expect_value(t, r.y + r.h, 114)
}
