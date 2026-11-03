package karl2d_mipmaps_example

import k2 "../.."
import "core:math"
import "core:math/noise"

main :: proc() {
	init()
	for step() {}
	shutdown()
}

tex_without_mipmaps: k2.Texture
tex_with_mipmaps: k2.Texture

init :: proc() {
	k2.init(1000, 750, "Karl2D Mipmaps Example", options = { window_mode = .Windowed_Resizable })

	PATTERN_SIZE :: 512
	NOISE_FREQUENCY :: 0.25
	NOISE_SEED :: 1

	pixels := make([]k2.Color, PATTERN_SIZE * PATTERN_SIZE)
	defer delete(pixels)

	for y in 0..<PATTERN_SIZE {
		for x in 0..<PATTERN_SIZE {
			coord := noise.Vec2 { f64(x) * NOISE_FREQUENCY, f64(y) * NOISE_FREQUENCY }
			is_white := noise.noise_2d(NOISE_SEED, coord) > 0
			pixels[y * PATTERN_SIZE + x] = is_white ? k2.WHITE : k2.BLACK
		}
	}

	pattern := k2.Image {
		pixels = pixels,
		width = PATTERN_SIZE,
		height = PATTERN_SIZE,
	}

	tex_without_mipmaps = k2.load_texture_from_image(pattern)
	tex_with_mipmaps = k2.load_texture_from_image(pattern, { generate_mipmaps = true })
}

step :: proc() -> bool {
	if !k2.update() {
		return false
	}

	k2.clear(k2.BLACK)

	screen_rect := k2.rect_from_pos_size({}, k2.get_screen_size())
	bottom_bar := k2.rect_cut_bottom(&screen_rect, 30, 0)
	top_half := k2.rect_cut_top(&screen_rect, screen_rect.h / 2, 0)
	bottom_half := screen_rect
	top_left := k2.rect_cut_left(&top_half, top_half.w / 2, 0)
	top_right := top_half
	bottom_left := k2.rect_cut_left(&bottom_half, bottom_half.w / 2, 0)
	bottom_right := bottom_half

	MIN_SCALE :: f32(0.05)
	wave := f32(math.sin(k2.get_time() * 0.75))
	scale := math.lerp(MIN_SCALE, 1, wave * 0.5 + 0.5)

	draw_pattern(top_left, tex_without_mipmaps, .Point, scale, "Point filter, without mipmaps")
	draw_pattern(top_right, tex_with_mipmaps, .Point, scale, "Point filter, with mipmaps")
	draw_pattern(bottom_left, tex_without_mipmaps, .Linear, scale, "Linear filter, without mipmaps")
	draw_pattern(bottom_right, tex_with_mipmaps, .Linear, scale, "Linear filter, with mipmaps")

	k2.draw_rect(bottom_bar, k2.DARK_GRAY)
	bottom_bar = k2.rect_shrink(bottom_bar, 4, 4)
	k2.draw_text("The same noise image with different filters and mipmapping settings.", k2.rect_top_left(bottom_bar), bottom_bar.h, k2.WHITE)
	source_code_rect := k2.rect_cut_right(&bottom_bar, k2.ui_button_width("Source Code", bottom_bar.h) + 50, 0)

	if k2.ui_button(source_code_rect, "Source Code") {
		k2.open_url("https://github.com/karl-zylinski/karl2d/blob/master/examples/mipmaps/mipmaps.odin")
	}

	k2.present()

	free_all(context.temp_allocator)
	return true
}

draw_pattern :: proc(
	rect: k2.Rect,
	texture: k2.Texture,
	filter: k2.Texture_Filter,
	scale: f32,
	label: string,
) {
	LABEL_HEIGHT :: 30
	PADDING :: 20

	area := rect
	label_rect := k2.rect_cut_top(&area, LABEL_HEIGHT, 0)
	area = k2.rect_shrink(area, PADDING, PADDING)

	tex_rect := k2.get_texture_rect(texture)
	fit_scale := min(area.w / tex_rect.w, area.h / tex_rect.h) * scale
	size := k2.Vec2 { tex_rect.w * fit_scale, tex_rect.h * fit_scale }
	center := k2.rect_middle(area)

	k2.set_texture_filter(texture, filter)
	k2.draw_texture_fit(texture, tex_rect, { center.x - size.x / 2, center.y - size.y / 2, size.x, size.y })
	k2.draw_text(label, { label_rect.x + 10, label_rect.y + 5 }, 20, k2.WHITE)
}

shutdown :: proc() {
	k2.destroy_texture(tex_with_mipmaps)
	k2.destroy_texture(tex_without_mipmaps)
	k2.shutdown()
}
