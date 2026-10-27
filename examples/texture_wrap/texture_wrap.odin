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

	k2.clear(k2.DARK_GRAY)

	draw_panel(0, "Repeat", { wrap_u = .Repeat, wrap_v = .Repeat })
	draw_panel(1, "Mirrored_Repeat, Clamp", { wrap_u = .Mirrored_Repeat, wrap_v = .Clamp })
	draw_panel(2, "Border", { wrap_u = .Border, wrap_v = .Border, border_color = .White })

	k2.present()
	free_all(context.temp_allocator)
	return true
}

draw_panel :: proc(idx: int, label: string, sampler: k2.Sampler) {
	x := f32(PAD + idx*(PANEL_SIZE + PAD))
	w := f32(tex.width)
	h := f32(tex.height)
	k2.draw_texture_fit(tex, {-w, -h, w*3, h*3}, {x, PAD, PANEL_SIZE, PANEL_SIZE}, sampler = sampler)
	k2.draw_text(label, {x, PAD*2 + PANEL_SIZE}, 20, k2.WHITE)
}

shutdown :: proc() {
	k2.destroy_texture(tex)
	k2.shutdown()
}
