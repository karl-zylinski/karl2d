// Checks that Y down and Y up draw the same picture.
//
// Everything these tests draw is positioned in screen space: X from the left edge and Y from the
// top edge. The `screen_*` helpers translate that into whatever the camera expects, and the results
// are measured back in the same screen space. So the expected values below hold either way, and
// running this package twice is what proves the two agree. Once as is, and once with
// -define:KARL2D_TEST_Y_UP=true. Both runs also need -define:KARL2D_RENDER_BACKEND=nil,
// -define:KARL2D_AUDIO_BACKEND=nil and -define:ODIN_TEST_THREADS=1.
//
// The define belongs to this package. It picks which axis these checks are written against. See
// `cross_space_test.odin` for the ones that use both axes at once, which need only one run.
//
// Drawing goes into a fixed-size render texture so the numbers do not depend on the size the window
// manager hands out. The nil render backend means no GPU is involved. A window is still opened, so
// this only runs where one can be created.
package karl2d_coordinate_system_test

import k2 "../.."
import "base:runtime"
import "core:sync"
import "core:testing"

// Which space this run checks. Everything below is written in screen space, so the same expected
// values hold either way and running the package twice is what proves the two agree.
TEST_Y_UP :: #config(KARL2D_TEST_Y_UP, false)

when TEST_Y_UP {
	TEST_FLIP_Y :: true
} else {
	TEST_FLIP_Y :: false
}

// The camera that points Y the way this run checks. Zoom 1 and no target, so it only changes which
// way Y points. Tests that need their own camera must set `flip_y` on it too.
TEST_CAMERA :: k2.Camera { zoom = 1, flip_y = TEST_FLIP_Y }

// The render texture everything is drawn into. Fixed so results are reproducible.
SURFACE_W :: 800
SURFACE_H :: 600

// Positions are compared to a twentieth of a pixel. Glyph rasterisation is deterministic, so this
// only has to absorb float error from the round trip through the projection matrix.
EPSILON :: 0.05

//----------------------------------------------//
// SCREEN SPACE: THE COORDINATE-SYSTEM-FREE VIEW //
//----------------------------------------------//

// Translate a Y measured from the top of the surface into the active coordinate system.
screen_y :: proc(y_from_top: f32) -> f32 {
	when TEST_Y_UP {
		return SURFACE_H - y_from_top
	} else {
		return y_from_top
	}
}

// A point measured from the top-left of the surface.
screen_pos :: proc(x, y_from_top: f32) -> k2.Vec2 {
	return { x, screen_y(y_from_top) }
}

// A rectangle whose top-left corner on screen is at (x, y_from_top).
//
// A Rect grows downwards from its y in Y down and upwards in Y up, so which edge `y` names is what
// changes here.
screen_rect :: proc(x, y_from_top, w, h: f32) -> k2.Rect {
	when TEST_Y_UP {
		return { x, screen_y(y_from_top + h), w, h }
	} else {
		return { x, y_from_top, w, h }
	}
}

// The position to hand to a procedure that grows a box of height `h` out of a position, such as
// `draw_texture` or `draw_text`, so that the box's top-left lands at (x, y_from_top) on screen.
screen_box_pos :: proc(x, y_from_top, h: f32) -> k2.Vec2 {
	r := screen_rect(x, y_from_top, 0, h)
	return { r.x, r.y }
}

// Rotations follow the coordinate system: positive is clockwise on screen in Y down and
// counter-clockwise in Y up. So a rotation that looks the same on screen has to be negated in Y up.
screen_rotation :: proc(radians: f32) -> f32 {
	when TEST_Y_UP {
		return -radians
	} else {
		return radians
	}
}

//---------//
// HARNESS //
//---------//

// Where a draw ended up, in screen space: pixels from the left and top edges of the surface.
Bounds :: struct {
	vertex_count: int,
	left, right: f32,
	top, bottom: f32,

	// The scissor rectangle as the render backend received it, which is always in native top-down
	// surface coordinates whichever way Karl2D's Y axis points.
	scissor: Maybe(k2.Rect),
}

state: ^k2.State
setup_once: sync.Once

// Karl2D keeps its state in globals, so only one test may drive it at a time.
draw_mutex: sync.Mutex

captured_vertices: [dynamic]k2.Vec2
captured_scissor: Maybe(k2.Rect)

the_texture: k2.Texture
uv_texture: k2.Texture
the_static_font: k2.Font

// Stand-in for the render backend's `draw`, so the tests see exactly the geometry and scissor
// rectangle a real backend would have received rather than poking at internals.
capture_draw :: proc( draw_calls: []k2.Draw_Call) {
	pos_offset := state.current_batch.current_shader.default_input_offsets[.Position]

	if pos_offset < 0 {
		return
	}

	for dc in draw_calls {
		captured_scissor = dc.scissor

		if dc.vertex_size == 0 {
			continue
		}

		for i in 0..<dc.vertex_count {
			v := (^k2.Vec2)(&state.current_batch.vertex_buffer_cpu[dc.vertex_offset + i*dc.vertex_size + pos_offset])^
			append(&captured_vertices, v)
		}
	}
}

setup :: proc() {
	sync.once_do(&setup_once, proc() {
		// The test runner hands each test its own tracking allocator and tears it down when that
		// test finishes. Karl2D is initialised once and used by every test, so its state has to
		// come from somewhere that outlives whichever test happened to run first. Allocating from
		// the heap directly also keeps these one-time allocations out of the per-test leak report.
		stable := runtime.heap_allocator()

		// Also as the context allocator: FontStash allocates its atlas from `context.allocator`
		// rather than from the allocator passed to `k2.init`, so passing the allocator alone is
		// not enough to keep the font state alive between tests.
		context.allocator = stable

		captured_vertices = make([dynamic]k2.Vec2, 0, 1024, stable)

		state = k2.init(1280, 720, "karl2d coordinate system tests", allocator = stable)

		// `set_internal_state` makes the library pick up the swapped-in `draw`.
		state.render_backend.draw = capture_draw
		k2.set_internal_state(state)

		rt := k2.create_render_texture(SURFACE_W, SURFACE_H)
		k2.set_render_texture(rt)

		the_texture = k2.create_texture(64, 32, .RGBA_8_Norm)
		uv_texture = k2.create_texture(TEX_W, TEX_H, .RGBA_8_Norm)
		flipped_texture = k2.create_texture(RT_W, RT_H, .RGBA_8_Norm)
		the_static_font = k2.load_static_font_from_bytes(k2.DEFAULT_FONT_DATA, 20)
	})
}

// Run `draw`, then report where it landed in screen space.
//
// The vertices are pushed through the same view-projection matrix the GPU would use and then mapped
// back into pixels from the top-left of the surface. Going via the projection is the point: it is
// what makes the answer independent of which coordinate system produced the vertices.
draw_and_measure :: proc(draw: proc()) -> Bounds {
	setup()

	sync.mutex_lock(&draw_mutex)
	defer sync.mutex_unlock(&draw_mutex)

	clear(&captured_vertices)
	captured_scissor = nil

	// The Y axis is a camera property, so it has to be active before anything is drawn. A test that
	// sets its own camera overwrites this, and must carry `flip_y` on that camera itself.
	k2.set_camera(TEST_CAMERA)

	draw()
	k2.update_render_clear_batch()

	view_projection := state.screen_proj_matrix * k2.camera_view_matrix(TEST_CAMERA)

	res := Bounds {
		vertex_count = len(captured_vertices),
		left = max(f32),
		right = min(f32),
		top = max(f32),
		bottom = min(f32),
		scissor = captured_scissor,
	}

	for v in captured_vertices {
		ndc := view_projection * k2.Vec4 { v.x, v.y, 0, 1 }

		// NDC is -1..1 with Y up. Convert to pixels from the top-left of the surface.
		x := (ndc.x + 1) * 0.5 * SURFACE_W
		y_from_top := (1 - ndc.y) * 0.5 * SURFACE_H

		res.left = min(res.left, x)
		res.right = max(res.right, x)
		res.top = min(res.top, y_from_top)
		res.bottom = max(res.bottom, y_from_top)
	}

	return res
}

expect_bounds :: proc(
	t: ^testing.T,
	got: Bounds,
	vertex_count: int,
	left, top, right, bottom: f32,
	loc := #caller_location,
) {
	testing.expectf(t, got.vertex_count == vertex_count,
		"expected %v vertices, got %v", vertex_count, got.vertex_count, loc = loc,
	)

	if got.vertex_count == 0 {
		return
	}

	ok :=
		abs(got.left - left) <= EPSILON &&
		abs(got.right - right) <= EPSILON &&
		abs(got.top - top) <= EPSILON &&
		abs(got.bottom - bottom) <= EPSILON

	testing.expectf(t, ok,
		"expected screen bounds l=%.2f t=%.2f r=%.2f b=%.2f, got l=%.2f t=%.2f r=%.2f b=%.2f",
		left, top, right, bottom, got.left, got.top, got.right, got.bottom, loc = loc,
	)
}

//-------//
// TESTS //
//-------//

@(test)
draw_rect_covers_its_screen_rectangle :: proc(t: ^testing.T) {
	got := draw_and_measure(proc() {
		k2.draw_rect(screen_rect(100, 100, 40, 20), k2.WHITE)
	})

	expect_bounds(t, got, 6, 100, 100, 140, 120)
}

@(test)
draw_rect_rotates_the_same_way_on_screen :: proc(t: ^testing.T) {
	got := draw_and_measure(proc() {
		// `origin` shifts the rect as well as setting the pivot, so with origin = half the size the
		// rect ends up centred on (r.x, r.y) and spins around it. That makes the pivot point, not
		// the rect's corner, the thing to describe in screen space.
		pivot := screen_pos(120, 110)
		r := k2.Rect { pivot.x, pivot.y, 40, 20 }
		k2.draw_rect(r, k2.WHITE, { r.w/2, r.h/2 }, screen_rotation(0.5))
	})

	expect_bounds(t, got, 6, 97.64, 91.65, 142.36, 128.37)
}

@(test)
draw_rect_outline_covers_its_screen_rectangle :: proc(t: ^testing.T) {
	got := draw_and_measure(proc() {
		k2.draw_rect_outline(screen_rect(100, 100, 40, 20), 2, k2.WHITE)
	})

	expect_bounds(t, got, 24, 100, 100, 140, 120)
}

@(test)
draw_circle_is_centred_on_its_screen_position :: proc(t: ^testing.T) {
	got := draw_and_measure(proc() {
		k2.draw_circle(screen_pos(200, 150), 30, k2.WHITE, 8)
	})

	expect_bounds(t, got, 24, 170, 120, 230, 180)
}

@(test)
draw_line_spans_its_screen_endpoints :: proc(t: ^testing.T) {
	got := draw_and_measure(proc() {
		k2.draw_line(screen_pos(10, 20), screen_pos(120, 90), 3, k2.WHITE)
	})

	expect_bounds(t, got, 6, 9.20, 18.72, 120.80, 91.26)
}

@(test)
draw_texture_grows_out_of_its_position_like_a_rect :: proc(t: ^testing.T) {
	got := draw_and_measure(proc() {
		k2.draw_texture(the_texture, screen_box_pos(50, 60, 32))
	})

	expect_bounds(t, got, 6, 50, 60, 114, 92)
}

@(test)
draw_texture_fit_source_rect_stays_top_down :: proc(t: ^testing.T) {
	got := draw_and_measure(proc() {
		// The source sub-rect is always measured top-down from the texture's top-left corner, in
		// both coordinate systems, because texture space is image space.
		k2.draw_texture_fit(the_texture, { 8, 4, 32, 16 }, screen_rect(50, 60, 64, 32))
	})

	expect_bounds(t, got, 6, 50, 60, 114, 92)
}

@(test)
draw_text_anchors_the_block_like_a_rect :: proc(t: ^testing.T) {
	got := draw_and_measure(proc() {
		draw_text_at_screen_top("Ag", 20, k2.FONT_DEFAULT)
	})

	expect_bounds(t, got, 12, 99, 102, 121, 120.99)
}

@(test)
draw_text_stacks_lines_downwards_on_screen :: proc(t: ^testing.T) {
	got := draw_and_measure(proc() {
		draw_text_at_screen_top("Ag\nBh", 20, k2.FONT_DEFAULT)
	})

	expect_bounds(t, got, 24, 99, 102, 121, 137.01)
}

@(test)
draw_text_static_anchors_the_block_like_a_rect :: proc(t: ^testing.T) {
	got := draw_and_measure(proc() {
		draw_text_at_screen_top("Ag", 20, the_static_font)
	})

	expect_bounds(t, got, 12, 100, 102.84, 119.80, 119.82)
}

@(test)
draw_text_static_stacks_lines_downwards_on_screen :: proc(t: ^testing.T) {
	got := draw_and_measure(proc() {
		draw_text_at_screen_top("Ag\nBh", 20, the_static_font)
	})

	expect_bounds(t, got, 24, 100, 102.84, 119.84, 135.84)
}

@(test)
draw_text_is_placed_the_same_under_a_zoomed_camera :: proc(t: ^testing.T) {
	// The camera is cleared after the measurement, not inside the draw. Clearing it here would put
	// the projection back to screen space before `draw_and_measure` reads it, and the world-space
	// vertices would then be measured through the wrong one.
	got := draw_and_measure(proc() {
		k2.set_camera(k2.Camera { zoom = 2, flip_y = TEST_FLIP_Y })
		draw_text_at_screen_top("Ag", 20, k2.FONT_DEFAULT)
	})

	k2.set_camera(nil)

	// The two spaces land in different places here, and that is correct rather than a bug: zoom
	// scales about the world origin while the space flip is about the surface, so a camera with no
	// target or offset puts a Y up point somewhere a Y down point is not. What this pins down is
	// the dynamic font path under a zoomed camera -- FontStash rasterises at `font_size * zoom` and
	// the quads are divided back down, so a mistake there shows up as text that drifts or changes
	// size, in either space.
	when TEST_Y_UP {
		expect_bounds(t, got, 12, 199.00, -394.00, 241.00, -359.00)
	} else {
		expect_bounds(t, got, 12, 199.00, 206.00, 241.00, 241.00)
	}
}

@(test)
scissor_rect_reaches_the_backend_in_native_coordinates :: proc(t: ^testing.T) {
	// The scissor rect is screen-space under every camera, so it is given as one: no `screen_rect`.
	got := draw_and_measure(proc() {
		k2.set_scissor_rect(k2.Rect { 100, 50, 200, 120 })
		k2.draw_rect(screen_rect(100, 100, 40, 20), k2.WHITE)
		k2.set_scissor_rect(nil)
	})

	expect_bounds(t, got, 6, 100, 100, 140, 120)

	scissor, has_scissor := got.scissor.?

	if !testing.expect(t, has_scissor, "no scissor rectangle reached the render backend") {
		return
	}

	// Top-down, whichever way Karl2D's Y axis points: this is what D3D11 and OpenGL want.
	testing.expectf(t,
		abs(scissor.x - 100) <= EPSILON &&
		abs(scissor.y - 50) <= EPSILON &&
		abs(scissor.w - 200) <= EPSILON &&
		abs(scissor.h - 120) <= EPSILON,
		"expected native scissor (100, 50, 200, 120), got (%.2f, %.2f, %.2f, %.2f)",
		scissor.x, scissor.y, scissor.w, scissor.h,
	)
}

//----------------------------------------//
// PROPERTIES THAT HOLD IN BOTH SYSTEMS   //
//----------------------------------------//

// Text covers exactly the rectangle `measure_text` reports, so text lines up with rectangles drawn
// at the same position. This is what `ui_button` relies on.
@(test)
text_stays_within_its_measured_rectangle :: proc(t: ^testing.T) {
	check :: proc(t: ^testing.T, text: string, font: k2.Font, label: string) {
		setup()

		size := f32(20)
		measured := k2.measure_text(text, size, font)
		pos := screen_box_pos(100, 100, measured.y)

		got := draw_and_measure_text(text, size, font, pos)

		// The measured box in screen space: its top is at 100 by construction.
		box_top := f32(100)
		box_bottom := box_top + measured.y

		// Glyph ink sits inside the line box, give or take a descender that pokes out by about a
		// pixel. What matters is that the number is the same in both coordinate systems.
		testing.expectf(t, got.top >= box_top - 1.5 && got.bottom <= box_bottom + 1.5,
			"%v: ink [%.2f, %.2f] escapes measured box [%.2f, %.2f]",
			label, got.top, got.bottom, box_top, box_bottom,
		)
	}

	check(t, "Ag", k2.FONT_DEFAULT, "dynamic")
	check(t, "Ag\nBh", k2.FONT_DEFAULT, "dynamic multiline")
	check(t, "Ag", the_static_font, "static")
	check(t, "Ag\nBh", the_static_font, "static multiline")
}

// Text reads downwards on screen: within one block the first line is drawn above the second,
// whichever way Y points. Each glyph is one 6-vertex quad, so the first quad is the first line.
@(test)
first_line_of_text_is_above_the_second :: proc(t: ^testing.T) {
	check :: proc(t: ^testing.T, font: k2.Font, label: string) {
		setup()

		sync.mutex_lock(&draw_mutex)
		defer sync.mutex_unlock(&draw_mutex)

		clear(&captured_vertices)
		draw_text_at_screen_top("A\nB", 20, font)
		k2.update_render_clear_batch()

		if !testing.expectf(t, len(captured_vertices) == 12,
			"%v: expected two glyph quads, got %v vertices", label, len(captured_vertices)) {
			return
		}

		first := screen_top_of(captured_vertices[:6])
		second := screen_top_of(captured_vertices[6:])

		testing.expectf(t, first < second,
			"%v: first line at %.2f is not above second line at %.2f", label, first, second,
		)
	}

	check(t, k2.FONT_DEFAULT, "dynamic")
	check(t, the_static_font, "static")
}

// The rect_* helpers are screen-space layout helpers: they take a screen-space Rect, where y is the
// top edge, and they do not consult the active camera. So they are given a plain screen rect here
// rather than one built by `screen_rect`, and the answers are the same in both runs because the
// helpers no longer branch on the coordinate system at all.
//
// This is the trade the camera-based design makes: they cannot follow the active space, because
// they are pure functions of a Rect with no camera in sight. Handing one a Y up rect gives the
// vertically mirrored corner, which is why `examples/space_cat` grew `sprite_foot_origin` instead
// of using `rect_bottom_middle` for its world sprites.
@(test)
rect_helpers_are_named_for_the_screen :: proc(t: ^testing.T) {
	setup()

	r := k2.Rect { 100, 100, 40, 20 }

	testing.expect_value(t, k2.rect_top_left(r).y, 100)
	testing.expect_value(t, k2.rect_top_middle(r).y, 100)
	testing.expect_value(t, k2.rect_top_right(r).y, 100)
	testing.expect_value(t, k2.rect_bottom_left(r).y, 120)
	testing.expect_value(t, k2.rect_bottom_middle(r).y, 120)
	testing.expect_value(t, k2.rect_bottom_right(r).y, 120)
	testing.expect_value(t, k2.rect_middle(r).y, 110)

	testing.expect_value(t, k2.rect_top_left(r).x, 100)
	testing.expect_value(t, k2.rect_top_right(r).x, 140)
}

@(test)
rect_cut_top_cuts_the_top_of_the_screen :: proc(t: ^testing.T) {
	setup()

	r := k2.Rect { 100, 100, 40, 20 }
	cut := k2.rect_cut_top(&r, 5, 1)

	// 1px margin, then a 5px tall strip, leaving the rest below it.
	testing.expect_value(t, k2.rect_top_left(cut).y, 101)
	testing.expect_value(t, cut.h, 5)
	testing.expect_value(t, k2.rect_top_left(r).y, 106)
}

@(test)
rect_cut_bottom_cuts_the_bottom_of_the_screen :: proc(t: ^testing.T) {
	setup()

	r := k2.Rect { 100, 100, 40, 20 }
	cut := k2.rect_cut_bottom(&r, 5, 1)

	testing.expect_value(t, k2.rect_top_left(cut).y, 114)
	testing.expect_value(t, cut.h, 5)
	testing.expect_value(t, k2.rect_bottom_left(r).y, 114)
}

//---------//
// HELPERS //
//---------//

// Draw text whose block starts 100 pixels down from the top of the surface, whichever way Y points.
draw_text_at_screen_top :: proc(text: string, size: f32, font: k2.Font) {
	height := k2.measure_text(text, size, font).y
	k2.draw_text(text, screen_box_pos(100, 100, height), size, k2.WHITE, font)
}

// `draw_and_measure` takes a parameterless proc, so text cases that need arguments go through here.
draw_and_measure_text :: proc(text: string, size: f32, font: k2.Font, pos: k2.Vec2) -> Bounds {
	pending_text = text
	pending_size = size
	pending_font = font
	pending_pos = pos

	return draw_and_measure(proc() {
		k2.draw_text(pending_text, pending_pos, pending_size, k2.WHITE, pending_font)
	})
}

pending_text: string
pending_size: f32
pending_font: k2.Font
pending_pos: k2.Vec2

// A world-space Y as a distance from the top of the surface, so the number means the same thing in
// both coordinate systems.
from_top :: proc(v: k2.Vec2) -> f32 {
	when TEST_Y_UP {
		return SURFACE_H - v.y
	} else {
		return v.y
	}
}

// How far the topmost of these vertices is from the top of the surface.
screen_top_of :: proc(vertices: []k2.Vec2) -> f32 {
	extreme := max(f32)

	for v in vertices {
		extreme = min(extreme, from_top(v))
	}

	return extreme
}
