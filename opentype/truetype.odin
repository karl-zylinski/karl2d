#+private package
package karl2d_opentype

import "core:math"

True_Type_Format :: struct {
	// Gives you the location in `glyph_outlines` where a glyph's outlines (contours) live.
	glyph_locations: []u8,

	// Says if the entries in `glyph_locations` are 16 or 32 bit.
	glyph_location_format: True_Type_Glyph_Location_Format,

	// Contains the outlines for each glyph. For each glyph there is a header that says how many
	// outlines it has, referred to as `number_of_contours`. The header also contains a bounding
	// box, which `get_glyph_box` returns.
	//
	// if `number_of_contours` is negative, then it is a composite glyph. It's then built from
	// the outlines of several other glyphs. See `tt_get_glyph_shape`.
	glyph_outlines: []u8,
}

True_Type_Glyph_Location_Format :: enum {
	// u16 number that is halved. So you'd have to multiply it by 2.
	Short,

	// u32 number
	Long,
}

TT_MAX_COMPOSITE_DEPTH :: 16

tt_load :: proc(data: []u8, fontstart: int) -> (True_Type_Format, bool) {
	glyph_outlines := find_table(data, fontstart, "glyf")
	glyph_locations := find_table(data, fontstart, "loca")
	font_header := find_table(data, fontstart, "head")

	if len(glyph_outlines) == 0 || len(glyph_locations) == 0 || len(font_header) < 54 {
		return {}, false
	}

	glyph_location_format: True_Type_Glyph_Location_Format

	switch read_u16(font_header, 50) {
	case 0:
		glyph_location_format = .Short
	case 1:
		glyph_location_format = .Long
	case:
		return {}, false
	}

	return {
		glyph_locations = glyph_locations,
		glyph_location_format = glyph_location_format,
		glyph_outlines = glyph_outlines,
	}, true
}

tt_get_glyph_outline :: proc(tt: True_Type_Format, glyph: int) -> []u8 {
	start, end: int

	switch tt.glyph_location_format {
	case .Short:
		if glyph < 0 || glyph >= len(tt.glyph_locations) / 2 - 1 {
			return nil
		}

		start = read_u16(tt.glyph_locations, glyph * 2) * 2
		end = read_u16(tt.glyph_locations, glyph * 2 + 2) * 2
	case .Long:
		if glyph < 0 || glyph >= len(tt.glyph_locations) / 4 - 1 {
			return nil
		}

		start = read_u32(tt.glyph_locations, glyph * 4)
		end = read_u32(tt.glyph_locations, glyph * 4 + 4)
	}

	if end <= start || end > len(tt.glyph_outlines) {
		return nil
	}

	return tt.glyph_outlines[start:end]
}

tt_close_shape :: proc(
	vertices: []Vertex,
	num_vertices: int,
	was_off: bool,
	start_off: bool,
	sx: int,
	sy: int,
	scx: int,
	scy: int,
	cx: int,
	cy: int,
) -> int {
	num_vertices := num_vertices

	if start_off {
		if was_off {
			vertices[num_vertices] = make_vertex(.Curve, (cx+scx)>>1, (cy+scy)>>1, cx, cy)
			num_vertices += 1
		}

		vertices[num_vertices] = make_vertex(.Curve, sx, sy, scx, scy)
		num_vertices += 1
	} else {
		if was_off {
			vertices[num_vertices] = make_vertex(.Curve, sx, sy, cx, cy)
		} else {
			vertices[num_vertices] = make_vertex(.Line, sx, sy, 0, 0)
		}

		num_vertices += 1
	}

	return num_vertices
}

tt_get_glyph_shape :: proc(
	tt: True_Type_Format,
	glyph_index: int,
	all_vertices: ^[dynamic]Vertex,
	composite_depth: int,
) {
	if composite_depth > TT_MAX_COMPOSITE_DEPTH {
		return
	}

	outline := tt_get_glyph_outline(tt, glyph_index)

	if len(outline) == 0 {
		return
	}

	number_of_contours := read_i16(outline, 0)

	if number_of_contours > 0 {
		flags: u8 = 0
		flagcount: u8 = 0
		j := 0
		was_off := false
		start_off := false
		x, y, cx, cy, sx, sy, scx, scy: int
		end_pts_of_contours := skip_bytes(outline, 10)
		ins := read_u16(outline, 10 + number_of_contours * 2)
		points := skip_bytes(outline, 10 + number_of_contours * 2 + 2 + ins)

		n := 1 + read_u16(end_pts_of_contours, number_of_contours*2-2)

		m := n + 2*number_of_contours
		first_vertex := len(all_vertices)
		resize(all_vertices, first_vertex + m + 1)
		vertices := all_vertices[first_vertex:]

		next_move := 0
		off := m - n

		for i in 0..<n {
			if flagcount == 0 {
				flags = u8(read_u8(points, 0))
				points = skip_bytes(points, 1)

				if flags & 8 != 0 {
					flagcount = u8(read_u8(points, 0))
					points = skip_bytes(points, 1)
				}
			} else {
				flagcount -= 1
			}

			vertices[off+i].type = Vertex_Type(flags)
		}

		x = 0

		for i in 0..<n {
			flags = u8(vertices[off+i].type)

			if flags & 2 != 0 {
				dx := read_u8(points, 0)
				points = skip_bytes(points, 1)
				x += (flags & 16) != 0 ? dx : -dx
			} else if flags & 16 == 0 {
				x += read_i16(points, 0)
				points = skip_bytes(points, 2)
			}

			vertices[off+i].x = i16(x)
		}

		y = 0

		for i in 0..<n {
			flags = u8(vertices[off+i].type)

			if flags & 4 != 0 {
				dy := read_u8(points, 0)
				points = skip_bytes(points, 1)
				y += (flags & 32) != 0 ? dy : -dy
			} else if flags & 32 == 0 {
				y += read_i16(points, 0)
				points = skip_bytes(points, 2)
			}

			vertices[off+i].y = i16(y)
		}

		num_vertices := 0

		for i := 0; i < n; i += 1 {
			flags = u8(vertices[off+i].type)
			x = int(vertices[off+i].x)
			y = int(vertices[off+i].y)

			if next_move == i {
				if j >= number_of_contours {
					resize(all_vertices, first_vertex)
					return
				}

				if i != 0 {
					num_vertices = tt_close_shape(
						vertices,
						num_vertices,
						was_off,
						start_off,
						sx,
						sy,
						scx,
						scy,
						cx,
						cy,
					)
				}

				start_off = flags & 1 == 0 && i < read_u16(end_pts_of_contours, j*2)

				if start_off {
					scx = x
					scy = y

					if u8(vertices[off+i+1].type) & 1 == 0 {
						sx = (x + int(vertices[off+i+1].x)) >> 1
						sy = (y + int(vertices[off+i+1].y)) >> 1
					} else {
						sx = int(vertices[off+i+1].x)
						sy = int(vertices[off+i+1].y)
						i += 1
					}
				} else {
					sx = x
					sy = y
				}

				vertices[num_vertices] = make_vertex(.Move, sx, sy, 0, 0)
				num_vertices += 1
				was_off = false
				next_move = 1 + read_u16(end_pts_of_contours, j*2)
				j += 1
			} else if flags & 1 == 0 {
				if was_off {
					vertices[num_vertices] = make_vertex(.Curve, (cx+x)>>1, (cy+y)>>1, cx, cy)
					num_vertices += 1
				}

				cx = x
				cy = y
				was_off = true
			} else {
				if was_off {
					vertices[num_vertices] = make_vertex(.Curve, x, y, cx, cy)
				} else {
					vertices[num_vertices] = make_vertex(.Line, x, y, 0, 0)
				}

				num_vertices += 1
				was_off = false
			}
		}

		num_vertices = tt_close_shape(
			vertices,
			num_vertices,
			was_off,
			start_off,
			sx,
			sy,
			scx,
			scy,
			cx,
			cy,
		)

		resize(all_vertices, first_vertex + num_vertices)
	} else if number_of_contours < 0 {
		more := true
		comp := skip_bytes(outline, 10)

		for more {
			mtx := [6]f32{1, 0, 0, 1, 0, 0}

			flags := read_u16(comp, 0)
			comp = skip_bytes(comp, 2)
			gidx := read_u16(comp, 0)
			comp = skip_bytes(comp, 2)

			if flags & 2 != 0 {
				if flags & 1 != 0 {
					mtx[4] = f32(read_i16(comp, 0))
					comp = skip_bytes(comp, 2)
					mtx[5] = f32(read_i16(comp, 0))
					comp = skip_bytes(comp, 2)
				} else {
					mtx[4] = f32(i8(read_u8(comp, 0)))
					comp = skip_bytes(comp, 1)
					mtx[5] = f32(i8(read_u8(comp, 0)))
					comp = skip_bytes(comp, 1)
				}
			} else {
				comp = skip_bytes(comp, flags & 1 != 0 ? 4 : 2)
			}

			if flags & (1<<3) != 0 {
				mtx[0] = f32(read_i16(comp, 0))/16384.0
				mtx[3] = mtx[0]
				comp = skip_bytes(comp, 2)
				mtx[1] = 0
				mtx[2] = 0
			} else if flags & (1<<6) != 0 {
				mtx[0] = f32(read_i16(comp, 0))/16384.0
				comp = skip_bytes(comp, 2)
				mtx[1] = 0
				mtx[2] = 0
				mtx[3] = f32(read_i16(comp, 0))/16384.0
				comp = skip_bytes(comp, 2)
			} else if flags & (1<<7) != 0 {
				mtx[0] = f32(read_i16(comp, 0))/16384.0
				comp = skip_bytes(comp, 2)
				mtx[1] = f32(read_i16(comp, 0))/16384.0
				comp = skip_bytes(comp, 2)
				mtx[2] = f32(read_i16(comp, 0))/16384.0
				comp = skip_bytes(comp, 2)
				mtx[3] = f32(read_i16(comp, 0))/16384.0
				comp = skip_bytes(comp, 2)
			}

			if flags & (1<<11) != 0 && flags & (1<<12) == 0 {
				mtx[4] *= math.sqrt(mtx[0]*mtx[0] + mtx[1]*mtx[1])
				mtx[5] *= math.sqrt(mtx[2]*mtx[2] + mtx[3]*mtx[3])
			}

			first_comp_vertex := len(all_vertices)
			tt_get_glyph_shape(tt, gidx, all_vertices, composite_depth + 1)

			for &v in all_vertices[first_comp_vertex:] {
				x := f32(v.x)
				y := f32(v.y)
				v.x = i16(i32(mtx[0]*x + mtx[2]*y + mtx[4]))
				v.y = i16(i32(mtx[1]*x + mtx[3]*y + mtx[5]))
				x = f32(v.cx)
				y = f32(v.cy)
				v.cx = i16(i32(mtx[0]*x + mtx[2]*y + mtx[4]))
				v.cy = i16(i32(mtx[1]*x + mtx[3]*y + mtx[5]))
			}

			more = flags & (1<<5) != 0
		}
	}
}
