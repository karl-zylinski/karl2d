// Checks that the Y down and Y up coordinate systems draw the same picture.
//
// Everything this program draws is positioned in "screen space": X from the left edge and Y from the
// TOP edge, regardless of the coordinate system in use. `screen_rect` and `screen_pos` translate
// that into whatever the library currently expects. If the coordinate systems are implemented
// correctly then the resulting geometry, in normalized device coordinates, is identical in both.
//
// So the test is: build this two ways and diff the output. Both must agree.
//
//     odin run tools/coord_test -define:KARL2D_RENDER_BACKEND=nil
//     odin run tools/coord_test -define:KARL2D_RENDER_BACKEND=nil -define:KARL2D_Y_UP=true
//
// `tools/test_coord_systems` does exactly that and diffs for you.
package karl2d_coord_test

import k2 "../.."
import "core:fmt"
import "core:strings"

// Fixed-size render texture, so that the output does not depend on the size the window manager
// happened to give us.
SURFACE_W :: 800
SURFACE_H :: 600

// Translate a Y measured from the top of the surface into the active coordinate system.
screen_y :: proc(y_from_top: f32) -> f32 {
	when k2.Y_UP {
		return SURFACE_H - y_from_top
	} else {
		return y_from_top
	}
}

// A point measured from the top-left of the surface.
screen_pos :: proc(x, y_from_top: f32) -> k2.Vec2 {
	return { x, screen_y(y_from_top) }
}

// A rectangle whose top-left corner on screen is at (x, y_from_top) and which is `w` by `h` big.
//
// A Rect grows downwards from its y in Y down and upwards in Y up, so which edge `y` names is what
// changes here.
screen_rect :: proc(x, y_from_top, w, h: f32) -> k2.Rect {
	when k2.Y_UP {
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
// counter-clockwise in Y up. So a mode-neutral rotation has to be negated in Y up.
screen_rotation :: proc(radians: f32) -> f32 {
	when k2.Y_UP {
		return -radians
	} else {
		return radians
	}
}

// The captured arguments of the last rb.draw call.
captured_vertices: [dynamic]k2.Vec2
captured_scissor: Maybe(k2.Rect)
capture_state: ^k2.State

// Stand-in for the render backend's `draw`. Installed over the nil backend's so that the test sees
// exactly the geometry and scissor rectangle the backend would have received.
capture_draw :: proc(
	shd: k2.Shader,
	render_target: k2.Render_Target_Handle,
	bound_textures: []k2.Texture_Handle,
	scissor: Maybe(k2.Rect),
	blend_mode: k2.Blend_Mode,
	vertex_buffer: []u8,
) {
	captured_scissor = scissor

	pos_offset := shd.default_input_offsets[.Position]

	if pos_offset < 0 || shd.vertex_size == 0 {
		return
	}

	for i in 0..<len(vertex_buffer)/shd.vertex_size {
		v := (^k2.Vec2)(&vertex_buffer[i*shd.vertex_size + pos_offset])^
		append(&captured_vertices, v)
	}
}

// Draw something, then report where it ended up in normalized device coordinates. NDC is what the
// GPU actually rasterizes, so it is the same numbers in both coordinate systems if and only if the
// two draw the same picture.
report :: proc(label: string, draw: proc()) {
	clear(&captured_vertices)
	captured_scissor = nil

	draw()
	k2.draw_current_batch()

	view_projection := capture_state.proj_matrix * capture_state.view_matrix

	min_x, min_y := max(f32), max(f32)
	max_x, max_y := min(f32), min(f32)

	for v in captured_vertices {
		ndc := view_projection * k2.Vec4 { v.x, v.y, 0, 1 }
		min_x = min(min_x, ndc.x)
		max_x = max(max_x, ndc.x)
		min_y = min(min_y, ndc.y)
		max_y = max(max_y, ndc.y)
	}

	if len(captured_vertices) == 0 {
		fmt.printfln("%-24v verts=0", label)
		return
	}

	// NDC Y grows upwards, so the "top" of the shape on screen is max_y. Report it first so the
	// numbers read top-to-bottom the way the shape looks.
	fmt.printfln(
		"%-24v verts=%3v ndc_x=[%.4f %.4f] ndc_top=%.4f ndc_bottom=%.4f",
		label, len(captured_vertices), min_x, max_x, max_y, min_y,
	)

	if sciss, sciss_ok := captured_scissor.?; sciss_ok {
		// The backend always receives native top-down coordinates, so this should match in both.
		fmt.printfln("%-24v scissor=(%.1f %.1f %.1f %.1f)", "", sciss.x, sciss.y, sciss.w, sciss.h)
	}
}

// Globals so the `report` callbacks can reach them without closures.
the_texture: k2.Texture
the_static_font: k2.Font

// Draw text whose block starts 100 pixels down from the top of the surface, whichever way Y points.
draw_text_at_screen_top :: proc(text: string, size: f32, font: k2.Font) {
	height := k2.measure_text(text, size, font).y
	k2.draw_text(text, screen_box_pos(100, 100, height), size, k2.WHITE, font)
}

main :: proc() {
	st := k2.init(1280, 720, "coord_test")
	defer k2.shutdown()

	// Swap in our capturing `draw`. `set_internal_state` makes the library pick up the change.
	st.render_backend.draw = capture_draw
	k2.set_internal_state(st)
	capture_state = st

	rt := k2.create_render_texture(SURFACE_W, SURFACE_H)
	defer k2.destroy_render_texture(rt)
	k2.set_render_texture(rt)

	the_texture = k2.create_texture(64, 32, .RGBA_8_Norm)
	defer k2.destroy_texture(the_texture)

	the_static_font = k2.load_static_font_from_bytes(k2.DEFAULT_FONT_DATA, 20)
	defer k2.destroy_font(the_static_font)

	// To stderr: this line names the configuration, so it must not take part in the comparison.
	fmt.eprintfln("Y_UP=%v", k2.Y_UP)

	report("rect", proc() {
		k2.draw_rect(screen_rect(100, 100, 40, 20), k2.WHITE)
	})

	report("rect_rotated", proc() {
		// `origin` shifts the rect as well as setting the pivot, so with origin = half the size the
		// rect ends up centred on (r.x, r.y) and spins around it. That means the mode-neutral way to
		// describe this is by the pivot point, not by the rect's corner.
		pivot := screen_pos(120, 110)
		r := k2.Rect { pivot.x, pivot.y, 40, 20 }
		k2.draw_rect(r, k2.WHITE, { r.w/2, r.h/2 }, screen_rotation(0.5))
	})

	report("rect_outline", proc() {
		k2.draw_rect_outline(screen_rect(100, 100, 40, 20), 2, k2.WHITE)
	})

	report("circle", proc() {
		k2.draw_circle(screen_pos(200, 150), 30, k2.WHITE, 8)
	})

	report("line", proc() {
		k2.draw_line(screen_pos(10, 20), screen_pos(120, 90), 3, k2.WHITE)
	})

	report("texture", proc() {
		k2.draw_texture(the_texture, screen_box_pos(50, 60, 32))
	})

	report("texture_fit", proc() {
		// A source sub-rect, which is always measured top-down from the top-left of the texture.
		k2.draw_texture_fit(the_texture, { 8, 4, 32, 16 }, screen_rect(50, 60, 64, 32))
	})

	report("text_dynamic", proc() {
		draw_text_at_screen_top("Ag", 20, k2.FONT_DEFAULT)
	})

	report("text_dynamic_2lines", proc() {
		draw_text_at_screen_top("Ag\nBh", 20, k2.FONT_DEFAULT)
	})

	report("text_static", proc() {
		draw_text_at_screen_top("Ag", 20, the_static_font)
	})

	report("text_static_2lines", proc() {
		draw_text_at_screen_top("Ag\nBh", 20, the_static_font)
	})

	report("scissor", proc() {
		k2.set_scissor_rect(screen_rect(100, 50, 200, 120))
		k2.draw_rect(screen_rect(100, 100, 40, 20), k2.WHITE)
		k2.set_scissor_rect(nil)
	})

	report("text_under_camera_zoom", proc() {
		k2.set_camera(k2.Camera { zoom = 2 })
		draw_text_at_screen_top("Ag", 20, k2.FONT_DEFAULT)
		k2.set_camera(nil)
	})

	// Text must cover exactly the rectangle that `measure_text` reports, in both coordinate systems.
	// This is what makes text line up with rectangles, and what `ui_button` relies on.
	check_text_fills_measured_rect("Ag", 20, k2.FONT_DEFAULT, "dynamic")
	check_text_fills_measured_rect("Ag\nBh", 20, k2.FONT_DEFAULT, "dynamic multiline")
	check_text_fills_measured_rect("Ag", 20, the_static_font, "static")
	check_text_fills_measured_rect("Ag\nBh", 20, the_static_font, "static multiline")

	check_first_line_is_on_top(k2.FONT_DEFAULT, "dynamic")
	check_first_line_is_on_top(the_static_font, "static")

	check_rect_helpers()

	k2.set_render_texture(nil)
}

check_text_fills_measured_rect :: proc(text: string, size: f32, font: k2.Font, label: string) {
	measured := k2.measure_text(text, size, font)
	pos := screen_box_pos(100, 100, measured.y)

	clear(&captured_vertices)
	k2.draw_text(text, pos, size, k2.WHITE, font)
	k2.draw_current_batch()

	min_y, max_y := max(f32), min(f32)

	for v in captured_vertices {
		min_y = min(min_y, v.y)
		max_y = max(max_y, v.y)
	}

	box := k2.rect_from_pos_size(pos, measured)
	box_min := min(box.y, box.y + box.h)
	box_max := max(box.y, box.y + box.h)

	// How far the glyph ink sits from each edge of the measured box, in screen terms. These are not
	// zero (glyphs do not fill their line box, and descenders can overshoot it slightly), but they
	// must be the SAME in both coordinate systems: that is what "the text is anchored the same way"
	// means. The diff across builds is what checks it.
	when k2.Y_UP {
		gap_top := box_max - max_y
		gap_bottom := min_y - box_min
	} else {
		gap_top := min_y - box_min
		gap_bottom := box_max - max_y
	}

	fmt.printfln(
		"text_in_measured_rect (%-18v) gap_top=%+.2f gap_bottom=%+.2f height=%.2f",
		label, gap_top, gap_bottom, max_y - min_y,
	)
}

// Text reads downwards on screen: within one block, the first line must be drawn above the second,
// whichever way Y points. Each glyph is one 6-vertex quad, so the first quad is the first line's
// glyph and the last quad is the second line's.
check_first_line_is_on_top :: proc(font: k2.Font, label: string) {
	clear(&captured_vertices)
	draw_text_at_screen_top("A\nB", 20, font)
	k2.draw_current_batch()

	if len(captured_vertices) != 12 {
		fmt.printfln("check first_line_on_top (%v): FAIL  expected 2 glyph quads, got %v vertices",
			label, len(captured_vertices))
		return
	}

	first_line := screen_top_of(captured_vertices[:6])
	second_line := screen_top_of(captured_vertices[6:])

	ok := first_line < second_line

	fmt.printfln(
		"check first_line_on_top (%v): %v  line1_top=%.2f line2_top=%.2f",
		label, "OK" if ok else "FAIL", first_line, second_line,
	)
}

// How far the topmost of these vertices is from the top of the surface. Measuring from the top means
// the number is comparable across coordinate systems.
screen_top_of :: proc(vertices: []k2.Vec2) -> f32 {
	extreme := max(f32)

	for v in vertices {
		when k2.Y_UP {
			from_top := SURFACE_H - v.y
		} else {
			from_top := v.y
		}

		extreme = min(extreme, from_top)
	}

	return extreme
}

// The rect_* helpers are named for the screen, so they must report the same screen positions in both
// coordinate systems.
check_rect_helpers :: proc() {
	r := screen_rect(100, 100, 40, 20)

	from_top :: proc(v: k2.Vec2) -> f32 {
		when k2.Y_UP {
			return SURFACE_H - v.y
		} else {
			return v.y
		}
	}

	b := strings.builder_make()
	defer strings.builder_destroy(&b)

	fmt.sbprintf(&b, "top_left=%.1f ", from_top(k2.rect_top_left(r)))
	fmt.sbprintf(&b, "top_right=%.1f ", from_top(k2.rect_top_right(r)))
	fmt.sbprintf(&b, "bottom_left=%.1f ", from_top(k2.rect_bottom_left(r)))
	fmt.sbprintf(&b, "middle=%.1f ", from_top(k2.rect_middle(r)))

	cut := r
	top_cut := k2.rect_cut_top(&cut, 5, 1)
	fmt.sbprintf(&b, "cut_top=%.1f/%.1f ", from_top(k2.rect_top_left(top_cut)), top_cut.h)
	fmt.sbprintf(&b, "rest_top=%.1f ", from_top(k2.rect_top_left(cut)))

	cut2 := r
	bottom_cut := k2.rect_cut_bottom(&cut2, 5, 1)
	fmt.sbprintf(&b, "cut_bottom=%.1f/%.1f ", from_top(k2.rect_top_left(bottom_cut)), bottom_cut.h)
	fmt.sbprintf(&b, "rest_bottom=%.1f", from_top(k2.rect_bottom_left(cut2)))

	fmt.printfln("rect helpers: %v", strings.to_string(b))
}
