// Checks that use both coordinate spaces in one program.
//
// None of these were possible while the coordinate system was a build flag: there was only ever one
// of them in a binary. They are the cases the camera-based design exists to make work, so they are
// also the ones most worth pinning down. Unlike the rest of the package these do not depend on
// TEST_Y_AXIS -- they name the spaces they want.
package karl2d_coordinate_system_test

import k2 "../.."
import "core:sync"
import "core:testing"

SCREEN_CAMERA :: k2.Camera { zoom = 1, y_axis = .Down }
WORLD_CAMERA :: k2.Camera { zoom = 1, y_axis = .Up }

// Draw with an explicit camera and report where it landed, in pixels from the top of the surface.
draw_with_camera :: proc(camera: Maybe(k2.Camera), draw: proc()) -> Bounds {
	setup()

	sync.mutex_lock(&draw_mutex)
	defer sync.mutex_unlock(&draw_mutex)

	clear(&captured_vertices)
	captured_scissor = nil

	k2.set_camera(camera)
	draw()
	k2.draw_current_batch()

	view_projection := state.proj_matrix * state.view_matrix

	res := Bounds {
		vertex_count = len(captured_vertices),
		left = max(f32), right = min(f32),
		top = max(f32), bottom = min(f32),
		scissor = captured_scissor,
	}

	for v in captured_vertices {
		ndc := view_projection * k2.Vec4 { v.x, v.y, 0, 1 }
		x := (ndc.x + 1) * 0.5 * SURFACE_W
		y_from_top := (1 - ndc.y) * 0.5 * SURFACE_H

		res.left = min(res.left, x)
		res.right = max(res.right, x)
		res.top = min(res.top, y_from_top)
		res.bottom = max(res.bottom, y_from_top)
	}

	k2.set_camera(nil)
	return res
}

// The same rect drawn under each camera is mirrored about the middle of the surface, and nothing
// else about it changes. This is the whole feature in one assertion.
@(test)
the_two_spaces_mirror_each_other :: proc(t: ^testing.T) {
	r :: k2.Rect { 100, 100, 40, 20 }

	screen := draw_with_camera(SCREEN_CAMERA, proc() { k2.draw_rect(r, k2.WHITE) })
	world := draw_with_camera(WORLD_CAMERA, proc() { k2.draw_rect(r, k2.WHITE) })

	expect_bounds(t, screen, 6, 100, 100, 140, 120)

	// Y up: the rect's y is its bottom edge, measured up from the bottom of the surface.
	expect_bounds(t, world, 6, 100, SURFACE_H - 120, 140, SURFACE_H - 100)
}

// No camera means Y down, so it must agree with an explicit Y down camera exactly. This is what
// makes the default safe: code written without ever hearing about coordinate spaces gets the one
// every other 2D library uses.
@(test)
no_camera_is_the_screen_space :: proc(t: ^testing.T) {
	none := draw_with_camera(nil, proc() { k2.draw_rect({ 10, 20, 30, 40 }, k2.WHITE) })
	screen := draw_with_camera(SCREEN_CAMERA, proc() { k2.draw_rect({ 10, 20, 30, 40 }, k2.WHITE) })

	expect_bounds(t, none, 6, 10, 20, 40, 60)
	expect_bounds(t, screen, 6, 10, 20, 40, 60)
}

// Switching from a world camera back to screen space mid-frame lands where it would have without
// the world camera. This is the box2d example's HUD and space_cat's status bar: the case the whole
// design is for.
// The measurement compares raw emitted vertices rather than going through a projection: a single
// frame that switches cameras has no one view-projection to measure both halves with, which is the
// whole point of the case.
@(test)
switching_back_to_screen_space_mid_frame :: proc(t: ^testing.T) {
	setup()

	capture :: proc(draw: proc()) -> [dynamic]k2.Vec2 {
		sync.mutex_lock(&draw_mutex)
		defer sync.mutex_unlock(&draw_mutex)

		clear(&captured_vertices)
		k2.set_camera(nil)
		draw()
		k2.draw_current_batch()
		k2.set_camera(nil)

		out := make([dynamic]k2.Vec2, 0, len(captured_vertices), context.temp_allocator)
		append(&out, ..captured_vertices[:])
		return out
	}

	// The HUD on its own, with no world camera anywhere near it.
	alone := capture(proc() {
		k2.draw_rect({ 20, 20, 100, 30 }, k2.WHITE)
	})

	// The same HUD, drawn after a world camera has been used and cleared.
	after_world := capture(proc() {
		k2.set_camera(WORLD_CAMERA)
		k2.draw_rect({ 500, 500, 10, 10 }, k2.WHITE)
		k2.set_camera(nil)
		k2.draw_rect({ 20, 20, 100, 30 }, k2.WHITE)
	})

	if !testing.expectf(t, len(alone) == 6 && len(after_world) == 12,
		"expected 6 and 12 vertices, got %v and %v", len(alone), len(after_world)) {
		return
	}

	// The HUD's vertices are the last six, and they must be exactly what they were on their own.
	hud := after_world[6:]

	for v, i in alone {
		testing.expectf(t, v == hud[i],
			"HUD vertex %v moved after a world camera: %v became %v", i, v, hud[i],
		)
	}
}

// Texture space does not follow the camera: the same source rect selects the same pixels in both
// spaces. Checked here in one binary rather than by comparing two runs.
@(test)
texture_space_is_the_same_under_both_cameras :: proc(t: ^testing.T) {
	frame :: k2.Rect { 0, 0, TEX_W, f32(TEX_H)/3 }

	screen_top_v, screen_bottom_v, screen_ok := top_and_bottom_v_with_camera(SCREEN_CAMERA, proc() {
		k2.draw_texture_fit(uv_texture, frame, { 50, 60, 64, 32 })
	})

	world_top_v, world_bottom_v, world_ok := top_and_bottom_v_with_camera(WORLD_CAMERA, proc() {
		k2.draw_texture_fit(uv_texture, frame, { 50, 60, 64, 32 })
	})

	if !testing.expect(t, screen_ok && world_ok, "nothing was drawn") {
		return
	}

	// Frame 0 is the top third of the image, and it is the top third on screen in both spaces.
	expect_v(t, screen_top_v, 0, "screen: top of frame 0")
	expect_v(t, world_top_v, 0, "world: top of frame 0")
	expect_v(t, screen_bottom_v, f32(TEX_H)/3/TEX_H, "screen: bottom of frame 0")
	expect_v(t, world_bottom_v, f32(TEX_H)/3/TEX_H, "world: bottom of frame 0")
}

// Scissor rectangles are screen-space under every camera, so the backend sees the same rectangle
// either way. Under the old build flag this needed converting; now there is nothing to convert.
@(test)
scissor_is_screen_space_under_both_cameras :: proc(t: ^testing.T) {
	check :: proc(t: ^testing.T, camera: k2.Camera, label: string) {
		got := draw_with_camera(camera, proc() {
			k2.set_scissor_rect(k2.Rect { 100, 50, 200, 120 })
			k2.draw_rect({ 100, 100, 40, 20 }, k2.WHITE)
			k2.set_scissor_rect(nil)
		})

		scissor, ok := got.scissor.?

		if !testing.expectf(t, ok, "%v: no scissor reached the backend", label) {
			return
		}

		testing.expectf(t,
			abs(scissor.x - 100) <= EPSILON && abs(scissor.y - 50) <= EPSILON &&
			abs(scissor.w - 200) <= EPSILON && abs(scissor.h - 120) <= EPSILON,
			"%v: expected (100, 50, 200, 120), got (%.2f, %.2f, %.2f, %.2f)",
			label, scissor.x, scissor.y, scissor.w, scissor.h,
		)
	}

	check(t, SCREEN_CAMERA, "screen")
	check(t, WORLD_CAMERA, "world")
}

// The mouse is screen-space always. `screen_to_camera` is what moves it into a camera's space, and
// it has to round-trip under both.
@(test)
mouse_position_converts_per_camera :: proc(t: ^testing.T) {
	setup()

	mouse := k2.Vec2 { 300, 200 }

	// Under a screen camera the conversion is the identity.
	screen_world := k2.screen_to_camera(mouse, SCREEN_CAMERA)
	testing.expectf(t,
		abs(screen_world.x - 300) <= EPSILON && abs(screen_world.y - 200) <= EPSILON,
		"screen camera should not move the mouse, got (%.2f, %.2f)",
		screen_world.x, screen_world.y,
	)

	// Under a world camera it is measured up from the bottom of the surface instead.
	world := k2.screen_to_camera(mouse, WORLD_CAMERA)
	testing.expectf(t,
		abs(world.x - 300) <= EPSILON && abs(world.y - (SURFACE_H - 200)) <= EPSILON,
		"world camera should flip the mouse to (300, %.2f), got (%.2f, %.2f)",
		f32(SURFACE_H) - 200, world.x, world.y,
	)

	// And back again.
	back := k2.camera_to_screen(world, WORLD_CAMERA)
	testing.expectf(t,
		abs(back.x - mouse.x) <= EPSILON && abs(back.y - mouse.y) <= EPSILON,
		"round trip gave (%.2f, %.2f)", back.x, back.y,
	)
}

// A screen rectangle under a Y down camera with no target or zoom is itself.
@(test)
screen_to_camera_rect_is_identity_under_a_plain_screen_camera :: proc(t: ^testing.T) {
	setup()

	got := k2.screen_to_camera_rect({ 100, 100, 40, 20 }, SCREEN_CAMERA)
	expect_rect(t, got, { 100, 100, 40, 20 }, "plain screen camera")
}

// Under a Y up camera the rectangle mirrors about the surface, and `y` changes which edge it names:
// the screen rect's bottom edge (120 from the top) becomes the camera rect's `y`, measured up from
// the bottom. That is the `- h` term that makes converting the corners one at a time go wrong.
@(test)
screen_to_camera_rect_mirrors_and_re_anchors :: proc(t: ^testing.T) {
	setup()

	got := k2.screen_to_camera_rect({ 100, 100, 40, 20 }, WORLD_CAMERA)
	expect_rect(t, got, { 100, SURFACE_H - 120, 40, 20 }, "world camera")
}

// Zoom and target have to be accounted for, which is what hand-rolled conversions tend to miss:
// dividing the size by the zoom is right, but ignoring the target shifts the whole rectangle.
@(test)
screen_to_camera_rect_accounts_for_zoom_and_target :: proc(t: ^testing.T) {
	setup()

	camera := k2.Camera { zoom = 2, target = { 10, 20 }, y_axis = .Down }

	// The camera halves everything and then puts screen (0, 0) at world (10, 20).
	got := k2.screen_to_camera_rect({ 100, 100, 40, 20 }, camera)
	expect_rect(t, got, { 60, 70, 20, 10 }, "zoom and target")
}

// A rotated camera cannot be described by an axis-aligned Rect, so the result is the bounds. It
// contains the rectangle and is bigger than it, and each corner still lands where the point
// conversion puts it.
@(test)
screen_to_camera_rect_bounds_a_rotated_camera :: proc(t: ^testing.T) {
	setup()

	camera := k2.Camera { zoom = 1, rotation = 0.3, y_axis = .Down }
	r := k2.Rect { 100, 100, 40, 20 }
	got := k2.screen_to_camera_rect(r, camera)

	testing.expectf(t, got.w > r.w && got.h > r.h,
		"rotated bounds should be bigger than the rectangle, got %.2f x %.2f", got.w, got.h,
	)

	// Every corner the point conversion produces is inside the reported bounds.
	corners := [4]k2.Vec2 {
		k2.screen_to_camera({ r.x,       r.y       }, camera),
		k2.screen_to_camera({ r.x + r.w, r.y       }, camera),
		k2.screen_to_camera({ r.x,       r.y + r.h }, camera),
		k2.screen_to_camera({ r.x + r.w, r.y + r.h }, camera),
	}

	for c, i in corners {
		inside :=
			c.x >= got.x - EPSILON && c.x <= got.x + got.w + EPSILON &&
			c.y >= got.y - EPSILON && c.y <= got.y + got.h + EPSILON

		testing.expectf(t, inside, "corner %v at (%.2f, %.2f) is outside the bounds", i, c.x, c.y)
	}
}

// The inverse under a Y up camera: a camera rect whose `y` is its bottom edge comes back as a
// screen rect whose `y` is its top edge, mirrored about the surface.
@(test)
camera_to_screen_rect_mirrors_and_re_anchors :: proc(t: ^testing.T) {
	setup()

	got := k2.camera_to_screen_rect({ 100, SURFACE_H - 120, 40, 20 }, WORLD_CAMERA)
	expect_rect(t, got, { 100, 100, 40, 20 }, "world camera")
}

// The two undo each other, under a camera doing everything at once. Only exact because there is no
// rotation: with one, both directions report bounds and the round trip grows.
@(test)
the_rect_conversions_round_trip :: proc(t: ^testing.T) {
	setup()

	for camera in ([?]k2.Camera {
		{ zoom = 1, y_axis = .Down },
		{ zoom = 1, y_axis = .Up },
		{ zoom = 2, target = { 10, 20 }, offset = { 30, 40 }, y_axis = .Down },
		{ zoom = 0.5, target = { -5, 15 }, offset = { 7, 3 }, y_axis = .Up },
	}) {
		r := k2.Rect { 100, 100, 40, 20 }
		round_tripped := k2.camera_to_screen_rect(k2.screen_to_camera_rect(r, camera), camera)
		expect_rect(t, round_tripped, r, "round trip")
	}
}

expect_rect :: proc(t: ^testing.T, got, expected: k2.Rect, what: string, loc := #caller_location) {
	ok :=
		abs(got.x - expected.x) <= EPSILON && abs(got.y - expected.y) <= EPSILON &&
		abs(got.w - expected.w) <= EPSILON && abs(got.h - expected.h) <= EPSILON

	testing.expectf(t, ok, "%v: expected (%.2f, %.2f, %.2f, %.2f), got (%.2f, %.2f, %.2f, %.2f)",
		what, expected.x, expected.y, expected.w, expected.h,
		got.x, got.y, got.w, got.h, loc = loc,
	)
}
