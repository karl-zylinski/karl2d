// Generates the Karl2D logo using `make_karl2d_logo` and draws it in the middle of the window.
// No image files are involved: the logo is pixel art defined inside Karl2D.
package karl2d_logo_example

import k2 "../.."

logo: k2.Texture

init :: proc() {
	k2.init(1280, 720, "Karl2D Logo")

	// 960 pixels across makes every cell of the pixel art 32 pixels wide, and leaves room either
	// side of the logo in the window.
	logo_image := k2.make_karl2d_logo(960)
	logo = k2.load_texture_from_image(logo_image)

	// The texture holds its own copy of the pixels.
	k2.destroy_image(logo_image)
}

step :: proc() -> bool {
	if !k2.update() {
		return false
	}

	k2.clear({33, 11, 11, 255})

	logo_rect := k2.get_texture_rect(logo)

	k2.draw_texture_fit(
		logo,
		logo_rect,
		{
			k2.get_screen_size().x/2 - logo_rect.w/2,
			k2.get_screen_size().y/2 - logo_rect.h/2,
			logo_rect.w,
			logo_rect.h,
		},
	)

	k2.present()
	return true
}

shutdown :: proc() {
	k2.shutdown()
}

main :: proc() {
	init()
	for step() {}
	shutdown()
}
