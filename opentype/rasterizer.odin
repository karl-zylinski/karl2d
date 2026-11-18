package karl2d_opentype

import "base:runtime"
import "core:math"
import "core:slice"

Rasterizer_Pixel_Format :: enum {
	Alpha,
	RGBA_White,
	RGBA_Premultiplied,
}

Bitmap_Rect :: struct {
	x: int,
	y: int,
	width: int,
	height: int,
}

Rasterizer :: struct {
	vertices: [dynamic]Vertex,
	accumulation: [dynamic]f32,
	width: int,
	height: int,
	scale: f32,
	x_off: f32,
	y_off: f32,
	x: f32,
	y: f32,
}

// To draw glyphs, first make a rasterizer and then use `rasterize_glyph`.
make_rasterizer :: proc(allocator: runtime.Allocator) -> Rasterizer {
	return {
		vertices = make([dynamic]Vertex, allocator),
		accumulation = make([dynamic]f32, allocator),
	}
}

delete_rasterizer :: proc(r: ^Rasterizer) {
	delete(r.vertices)
	delete(r.accumulation)
	r^ = {}
}

// Fetch the `rect` that you need to feed into `rasterize_glyph`.
get_glyph_bitmap_rect :: proc(font: Font, glyph: Glyph_Index, scale: f32) -> Bitmap_Rect {
	box := get_glyph_box(font, glyph)
	x0 := int(math.floor(f32(box.x0) * scale))
	y0 := int(math.floor(f32(-box.y1) * scale))
	x1 := int(math.ceil(f32(box.x1) * scale))
	y1 := int(math.ceil(f32(-box.y0) * scale))

	return {
		x = x0,
		y = y0,
		width = x1 - x0,
		height = y1 - y0,
	}
}

// Draw a glyph into `output`. Specify the format of `output` using `output_format`.
rasterize_glyph :: proc(
	r: ^Rasterizer,
	font: Font,
	glyph: Glyph_Index,
	scale: f32,
	rect: Bitmap_Rect,
	output: []u8,
	output_stride: int,
	output_format: Rasterizer_Pixel_Format,
) #no_bounds_check {
	line_to :: proc(r: ^Rasterizer, to_x: f32, to_y: f32) #no_bounds_check {
		x0 := r.x * r.scale - r.x_off
		y0 := r.y * -r.scale - r.y_off
		x1 := to_x * r.scale - r.x_off
		y1 := to_y * -r.scale - r.y_off
		r.x = to_x
		r.y = to_y

		if y0 == y1 {
			return
		}

		direction: f32 = 1

		if y0 > y1 {
			x0, x1 = x1, x0
			y0, y1 = y1, y0
			direction = -1
		}

		width := f32(r.width)
		dxdy := (x1 - x0) / (y1 - y0)

		Part :: struct {
			x0: f32,
			y0: f32,
			x1: f32,
			y1: f32,
		}

		parts: [3]Part = ---
		num_parts := 0

		if x0 >= 0 && x1 >= 0 && x0 <= width && x1 <= width {
			parts[0] = {x0, y0, x1, y1}
			num_parts = 1
		} else {
			breaks: [4]f32 = ---
			breaks[0] = y0
			num_breaks := 1

			if dxdy != 0 {
				y_left := y0 + (0 - x0) / dxdy
				y_right := y0 + (width - x0) / dxdy
				y_first := min(y_left, y_right)
				y_second := max(y_left, y_right)

				if y_first > y0 && y_first < y1 {
					breaks[num_breaks] = y_first
					num_breaks += 1
				}

				if y_second > y0 && y_second < y1 {
					breaks[num_breaks] = y_second
					num_breaks += 1
				}
			}

			breaks[num_breaks] = y1
			num_breaks += 1

			for i in 0..<num_breaks - 1 {
				ya := breaks[i]
				yb := breaks[i + 1]
				xa := x0 + dxdy * (ya - y0)
				xb := x0 + dxdy * (yb - y0)
				x_middle := (xa + xb) / 2

				if ya == yb {
					continue
				}

				if x_middle < 0 {
					parts[num_parts] = {0, ya, 0, yb}
					num_parts += 1
				} else if x_middle <= width {
					parts[num_parts] = {clamp(xa, 0, width), ya, clamp(xb, 0, width), yb}
					num_parts += 1
				}
			}
		}

		accumulation_stride := r.width + 2

		for part in parts[:num_parts] {
			part_dxdy := (part.x1 - part.x0) / (part.y1 - part.y0)
			part_dydx: f32 = 0

			if part_dxdy != 0 {
				part_dydx = 1 / part_dxdy
			}

			first_row := max(int(part.y0), 0)
			end_row := int(part.y1)

			if f32(end_row) < part.y1 {
				end_row += 1
			}

			end_row = min(end_row, r.height)

			for row in first_row..<end_row {
				scanline := r.accumulation[row * accumulation_stride:]
				y_top := f32(row)
				y_bottom := y_top + 1
				sy0 := max(part.y0, y_top)
				sy1 := min(part.y1, y_bottom)
				x_top := part.x0 + part_dxdy * (sy0 - part.y0)
				x_bottom := part.x0 + part_dxdy * (sy1 - part.y0)

				if int(x_top) == int(x_bottom) {
					x := int(x_top)
					height := (sy1 - sy0) * direction
					area := ((f32(x) + 1 - x_top) + (f32(x) + 1 - x_bottom)) / 2 * height
					scanline[x] += area
					scanline[x + 1] += height - area
				} else {
					dy := part_dydx

					if x_top > x_bottom {
						sy0 = y_bottom - (sy0 - y_top)
						sy1 = y_bottom - (sy1 - y_top)
						sy0, sy1 = sy1, sy0
						x_top, x_bottom = x_bottom, x_top
						dy = -dy
					}

					x1 := int(x_top)
					x2 := int(x_bottom)
					y_crossing := sy0 + dy * (f32(x1 + 1) - x_top)
					y_final := sy0 + dy * (f32(x2) - x_top)

					if y_crossing > y_bottom {
						y_crossing = y_bottom
					}

					area := direction * (y_crossing-sy0)
					coverage := area * (f32(x1 + 1) - x_top) / 2
					scanline[x1] += coverage
					previous_coverage := coverage

					if y_final > y_bottom {
						y_final = y_bottom
						dy = (y_final - y_crossing ) / f32(x2 - (x1+1))
					}

					step := direction * dy

					for x in x1 + 1..<x2 {
						coverage = area + step/2
						scanline[x] += coverage - previous_coverage
						previous_coverage = coverage
						area += step
					}

					coverage = area + direction * (1 + (f32(x2) + 1 - x_bottom)) / 2 * (sy1-y_final)
					scanline[x2] += coverage - previous_coverage
					scanline[x2 + 1] += direction * (sy1-sy0) - coverage
				}
			}
		}
	}

	tesselate_curve :: proc(
		r: ^Rasterizer,
		x0: f32,
		y0: f32,
		x1: f32,
		y1: f32,
		x2: f32,
		y2: f32,
		flatness_squared: f32,
		n: int,
	) {
		if n > 16 {
			return
		}

		mx := (x0 + 2*x1 + x2)/4
		my := (y0 + 2*y1 + y2)/4
		dx := (x0+x2)/2 - mx
		dy := (y0+y2)/2 - my

		if dx*dx+dy*dy > flatness_squared {
			tesselate_curve(r, x0, y0, (x0+x1)/2, (y0+y1)/2, mx, my, flatness_squared, n+1)
			tesselate_curve(r, mx, my, (x1+x2)/2, (y1+y2)/2, x2, y2, flatness_squared, n+1)
		} else {
			line_to(r, x2, y2)
		}
	}

	tesselate_cubic :: proc(
		r: ^Rasterizer,
		x0: f32,
		y0: f32,
		x1: f32,
		y1: f32,
		x2: f32,
		y2: f32,
		x3: f32,
		y3: f32,
		flatness_squared: f32,
		n: int,
	) {
		if n > 16 {
			return
		}

		dx0 := x1-x0
		dy0 := y1-y0
		dx1 := x2-x1
		dy1 := y2-y1
		dx2 := x3-x2
		dy2 := y3-y2
		dx := x3-x0
		dy := y3-y0
		longlen := f32(
			math.sqrt(f64(dx0*dx0+dy0*dy0)) +
			math.sqrt(f64(dx1*dx1+dy1*dy1)) +
			math.sqrt(f64(dx2*dx2+dy2*dy2)),
		)
		shortlen := math.sqrt(dx*dx+dy*dy)

		if longlen*longlen-shortlen*shortlen > flatness_squared {
			x01 := (x0+x1)/2
			y01 := (y0+y1)/2
			x12 := (x1+x2)/2
			y12 := (y1+y2)/2
			x23 := (x2+x3)/2
			y23 := (y2+y3)/2
			xa := (x01+x12)/2
			ya := (y01+y12)/2
			xb := (x12+x23)/2
			yb := (y12+y23)/2
			mx := (xa+xb)/2
			my := (ya+yb)/2
			tesselate_cubic(r, x0, y0, x01, y01, xa, ya, mx, my, flatness_squared, n+1)
			tesselate_cubic(r, mx, my, xb, yb, x23, y23, x3, y3, flatness_squared, n+1)
		} else {
			line_to(r, x3, y3)
		}
	}

	width := rect.width
	height := rect.height

	if width <= 0 || height <= 0 {
		return
	}

	bytes_per_pixel := output_format == .Alpha ? 1 : 4
	assert(output_stride >= width * bytes_per_pixel)
	assert(len(output) >= (height - 1) * output_stride + width * bytes_per_pixel)

	clear(&r.vertices)

	switch f in font.format {
	case True_Type_Format:
		tt_get_glyph_shape(f, int(glyph), &r.vertices)
	case Compact_Font_Format:
		if _, ok := cff_run_charstring(f, int(glyph), &r.vertices); !ok {
			clear(&r.vertices)
		}
	}

	r.width = width
	r.height = height
	r.scale = scale
	r.x_off = f32(rect.x)
	r.y_off = f32(rect.y)
	accumulation_stride := width + 2

	if len(r.accumulation) < accumulation_stride * height {
		resize(&r.accumulation, accumulation_stride * height)
	}

	flatness := 0.35 / scale
	flatness_squared := flatness * flatness
	start_x: f32
	start_y: f32
	contour_open := false

	for v in r.vertices {
		x := f32(v.x)
		y := f32(v.y)

		switch v.type {
		case .Move:
			if contour_open {
				line_to(r, start_x, start_y)
			}

			contour_open = true
			start_x = x
			start_y = y
			r.x = x
			r.y = y

		case .Line:
			line_to(r, x, y)

		case .Curve:
			tesselate_curve(r, r.x, r.y, f32(v.cx), f32(v.cy), x, y, flatness_squared, 0)
			r.x = x
			r.y = y

		case .Cubic:
			tesselate_cubic(
				r,
				r.x,
				r.y,
				f32(v.cx),
				f32(v.cy),
				f32(v.cx1),
				f32(v.cy1),
				x,
				y,
				flatness_squared,
				0,
			)

			r.x = x
			r.y = y
		}
	}

	if contour_open {
		line_to(r, start_x, start_y)
	}

	for row in 0..<height {
		accumulation := r.accumulation[row * accumulation_stride:][:accumulation_stride]
		output_row := output[row * output_stride:]
		sum: f32 = 0

		switch output_format {
		case .Alpha:
			for x in 0..<width {
				sum += accumulation[x]
				output_row[x] = u8(min(i32(abs(sum)*255 + 0.5), 255))
			}

		case .RGBA_White:
			pixels := ([^][4]u8)(raw_data(output_row))

			for x in 0..<width {
				sum += accumulation[x]
				pixels[x] = {255, 255, 255, u8(min(i32(abs(sum)*255 + 0.5), 255))}
			}

		case .RGBA_Premultiplied:
			pixels := ([^][4]u8)(raw_data(output_row))

			for x in 0..<width {
				sum += accumulation[x]
				a := u8(min(i32(abs(sum)*255 + 0.5), 255))
				pixels[x] = {a, a, a, a}
			}
		}

		slice.zero(accumulation)
	}
}
