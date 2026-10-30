package karl2d_texture_wrap_example

import k2 "../.."

main :: proc() {
	init()
	for step() {}
	shutdown()
}

PANEL_SIZE :: 300
PAD :: 20

tex: k2.Texture

init :: proc() {
	k2.init(PANEL_SIZE*3 + PAD*4, PANEL_SIZE + PAD*2 + 40, "Karl2D Texture Wrap Example")
	tex = k2.load_texture_from_bytes(#load("../basics/sixten.jpg"))
}

step :: proc() -> bool {
	if !k2.update() {
		return false
	}

	k2.set_camera({
		zoom = k2.get_window_scale(),
	})

	k2.clear(k2.DARK_GRAY)

	sz := k2.get_texture_size(tex)
	src := k2.Rect { -sz.x, -sz.y, sz.x*3, sz.y*3 }
	label_y := f32(PAD*2 + PANEL_SIZE)

	x0 := f32(PAD)
	k2.set_texture_wrap(tex, .Repeat)
	k2.draw_texture_fit(tex, src, {x0, PAD, PANEL_SIZE, PANEL_SIZE})
	k2.draw_text("Repeat", {x0, label_y}, 20, k2.WHITE)

	x1 := f32(PAD*2 + PANEL_SIZE)
	k2.set_texture_sampler(tex, { wrap_x = .Mirrored_Repeat, wrap_y = .Clamp })
	k2.draw_texture_fit(tex, src, {x1, PAD, PANEL_SIZE, PANEL_SIZE})
	k2.draw_text("Mirrored_Repeat, Clamp", {x1, label_y}, 20, k2.WHITE)

	x2 := f32(PAD*3 + PANEL_SIZE*2)
	k2.set_texture_sampler(tex, { wrap_x = .Border, wrap_y = .Border, wrap_border_color = .White })
	k2.draw_texture_fit(tex, src, {x2, PAD, PANEL_SIZE, PANEL_SIZE})
	k2.draw_text("Border", {x2, label_y}, 20, k2.WHITE)

	k2.present()
	free_all(context.temp_allocator)
	return true
}

shutdown :: proc() {
	k2.destroy_texture(tex)
	k2.shutdown()
}
