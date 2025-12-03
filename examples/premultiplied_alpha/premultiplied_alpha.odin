package karl2d_example_premultiplied_alpha

import k2 "../.."
import "core:log"

main :: proc() {
	context.logger = log.create_console_logger()

	k2.init(1080, 1080, "Karl2D Premultiplied Alpha")
	k2.set_window_position(300, 100)

	// Load a texture and premultiply the alpha while loading it.
	tex := k2.load_texture_from_file("plop.png", options = { .Premultiply_Alpha })
	
	// Set the rendering to use premultiplied alpha when blending.
	k2.set_blend_mode(.Premultiplied_Alpha)

	for !k2.shutdown_wanted() {
		k2.process_events()
		k2.clear(k2.BLUE)

		src := k2.get_texture_rect(tex)
		dst := k2.Rect { 20, 100, src.w*20, src.h*20}
		k2.draw_texture_ex(tex, src, dst, {}, 0)

		k2.present()
		free_all(context.temp_allocator)
	}

	k2.destroy_texture(tex)
	k2.shutdown()
}
