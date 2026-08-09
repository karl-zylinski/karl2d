package karl2d_minimal_example

import k2 "../.."
import "core:mem"
import "core:math"
import "core:fmt"

_ :: fmt
_ :: mem

main :: proc() {
	init()
	for step() {}
	shutdown()
}

render_texture: k2.Render_Texture

init :: proc() {
	k2.init(1000, 750, "Karl2D Render Texture Example", options = { window_mode = .Windowed_Resizable })
	render_texture = k2.create_render_texture(75, 48)
}

rot: f32
rot2: f32

step :: proc() -> bool {
	if !k2.update() {
		return false
	}

	k2.set_render_texture(render_texture)
	k2.clear(k2.ORANGE)

	rot += k2.get_frame_time() * 10
	rot2 -= k2.get_frame_time() * 2

	if rot > 2*math.PI {
		rot -= 2*math.PI
	}

	k2.draw_rect({12, 12, 12, 12}, k2.BLACK, {6, 6}, rot)
	k2.draw_text("Hellöpe!", {f32(math.sin(k2.get_time() * 10))*5 + 7, 20}, 20, k2.BLACK)
	
	k2.set_render_texture(nil)

	k2.clear(k2.BLACK)

	rt_rect := k2.get_texture_rect(render_texture.texture)

	k2.draw_texture_fit(render_texture.texture, rt_rect, {0, 0, rt_rect.w * 5, rt_rect.h * 5})
	k2.draw_texture(render_texture.texture, {400, 20})
	k2.draw_texture_fit(
		render_texture.texture,
		rt_rect,
		{512, 512, rt_rect.w * 5, rt_rect.h * 5},
		origin = {rt_rect.w * 2.5, rt_rect.h * 2.5}, // half the dst rect size
		rotation = rot2,
	)

	//
	// BOTTOM BAR
	//

	k2.set_camera(nil)
	screen_rect := k2.rect_from_pos_size({}, k2.get_screen_size())
	bottom_bar := k2.rect_cut_bottom(&screen_rect, 30, 0)
	k2.draw_rect(bottom_bar, k2.DARK_GRAY)
	bottom_bar = k2.rect_shrink(bottom_bar, 4, 4)
	k2.draw_text("Drawn once into a render texture. The render texture is drawn 3 times.", k2.rect_top_left(bottom_bar), bottom_bar.h, k2.WHITE)
	source_code_rect := k2.rect_cut_right(&bottom_bar, k2.ui_button_width("Source Code", bottom_bar.h) + 50, 0)

	if k2.ui_button(source_code_rect, "Source Code") {
		k2.open_url("https://github.com/karl-zylinski/karl2d/blob/master/examples/render_texture/render_texture.odin")
	}

	k2.present()

	free_all(context.temp_allocator)
	return true
}

shutdown :: proc() {
	k2.destroy_render_texture(render_texture)
	k2.shutdown()
}