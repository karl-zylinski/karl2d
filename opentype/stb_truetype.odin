// This is based on stb_truetype.h by Sean Barrett. See the LICENSE file in this folder.
package karl2d_stb_truetype

import "base:intrinsics"
import "base:runtime"
import "core:math"
import "core:slice"

Font_Info :: struct {
	// Maps runes to glyph indices. `find_glyph_index` uses this.
	character_map: []u8,

	// The advance width for the `num_advance` first glyphs. Also stores left side bearing, but that
	// is not used.
	horizontal_metrics: []u8,

	// How many unique advances there are in `horizontal_metrics`. For glyphs that have index larger
	// than `num_advances`, they use the width of the last `horizontal_metrics`.
	num_advances: int,

	// Distance from font baseline to the top of the text line. This is often the distance to the
	// top of some large letter like I. Measured in font units.
	ascent: int,

	// Distance from the font baseline to the bottom of the text line. Often the distance to the
	// bottom of some letter like g or q. Measured in font units. Usually negative.
	descent: int,

	// Extra space to add between lines of text. The distance from one baseline to the next is
	// `ascent - descent + line_gap`.
	line_gap: int,

	// The table of kerning pairs. This is binary searched to find the kerning info for two
	// glyphs. Used when `gpos_lookup` contains no info for this pair.
	kerning_pairs: []u8,

	// A modern way to do kerning that uses a series of lookup rules in order to figure out the
	// kerning advance. See `get_glyph_gpos_advance` for the logic.
	gpos_lookups: []u8,

	// Says if the glyph outline data is stored is True Type or Compact Font Format.
	outline_format: Outline_Format,

	// Only used when `outline_format` is `True_Type`
	tt: TrueType_Info,

	// Only used when `outline_format` is `Compact_Font_Format`
	cff: CFF_Info,
}

Outline_Format :: enum {
	TrueType,
	Compact_Font_Format,
}

TrueType_Info :: struct {
	// Gives you the location in `glyph_outlines` where a glyph's outlines (contours) live.
	glyph_locations: []u8,

	// Says if the entries in `glyph_locations` are 16 or 32 bit.
	glyph_location_format: Glyph_Location_Format,
	
	// Contains the outlines for each glyph. For each glyph there is a header that says how many
	// outlines it has, referred to as `number_of_contours`. The header also contains a bounding
	// box, which `get_glyph_box` returns.
	//
	// if `number_of_contours` is negative, then it is a composite glyph. It's then built from
	// the outlines of several other glyphs. See `get_glyph_shape`.
	glyph_outlines: []u8,
}

Glyph_Location_Format :: enum {
	// u16 number that is halved. So you'd have to multiply it by 2.
	Short,

	// u32 number
	Long,
}

Init_Error :: enum {
	None,
	Font_Index_Out_Of_Range,
	Invalid_Font_Data,
}

Glyph_Box :: struct {
	x0: int,
	y0: int,
	x1: int,
	y1: int,
}

init_font :: proc(info: ^Font_Info, font_data: []u8, font_index: int) -> Init_Error {
	num_fonts := get_number_of_fonts(font_data)

	if num_fonts == 0 {
		return .Invalid_Font_Data
	}

	if font_index < 0 || font_index >= num_fonts {
		return .Font_Index_Out_Of_Range
	}

	data := font_data
	fontstart := 0

	if is_font_collection(font_data) {
		fontstart = read_u32(data, 12+font_index*4)
	}

	find_table :: proc(data: []u8, fontstart: int, table_tag: string) -> []u8 {
		num_tables := read_u16(data, fontstart+4)
		tabledir := fontstart + 12

		if tabledir + 16*num_tables > len(data) {
			return nil
		}

		for i in 0..<num_tables {
			loc := tabledir + 16*i

			if tag(data, loc, table_tag) {
				offset := read_u32(data, loc+8)
				length := read_u32(data, loc+12)

				if offset + length > len(data) {
					return nil
				}

				return data[offset:offset + length]
			}
		}

		return nil
	}

	info^ = {}
	character_map := find_table(data, fontstart, "cmap")
	font_header := find_table(data, fontstart, "head")
	horizontal_header := find_table(data, fontstart, "hhea")
	kerning := find_table(data, fontstart, "kern")
	glyph_positioning := find_table(data, fontstart, "GPOS")
	info.tt.glyph_locations = find_table(data, fontstart, "loca")
	info.tt.glyph_outlines = find_table(data, fontstart, "glyf")
	info.horizontal_metrics = find_table(data, fontstart, "hmtx")

	if len(character_map) == 0 ||
	   len(font_header) == 0 ||
	   len(horizontal_header) == 0 ||
	   len(info.horizontal_metrics) == 0 {
		return .Invalid_Font_Data
	}

	if len(info.tt.glyph_outlines) != 0 {
		if len(info.tt.glyph_locations) == 0 {
			return .Invalid_Font_Data
		}

		switch read_u16(font_header, 50) {
		case 0:
			info.tt.glyph_location_format = .Short
		case 1:
			info.tt.glyph_location_format = .Long
		case:
			return .Invalid_Font_Data
		}
	} else {
		if cff, cff_ok := cff_init(find_table(data, fontstart, "CFF ")); cff_ok {
			info.cff = cff
			info.outline_format = .Compact_Font_Format
		} else {
			return .Invalid_Font_Data
		}
	}

	if len(glyph_positioning) != 0 &&
	   read_u16(glyph_positioning, 0) == 1 &&
	   read_u16(glyph_positioning, 2) <= 1 {
		info.gpos_lookups = glyph_positioning[read_u16(glyph_positioning, 8):]
	}

	if len(kerning) != 0 && read_u16(kerning, 2) >= 1 && read_u16(kerning, 8) == 1 {
		info.kerning_pairs = kerning
	}

	num_tables := read_u16(character_map, 2)
	symbol_map: []u8

	for i in 0..<num_tables {
		encoding_record := 4 + 8 * i
		platform := read_u16(character_map, encoding_record)
		encoding := read_u16(character_map, encoding_record+2)
		subtable := character_map[read_u32(character_map, encoding_record+4):]

		if platform == PLATFORM_ID_UNICODE ||
		   (platform == PLATFORM_ID_MICROSOFT &&
		    (encoding == MS_EID_UNICODE_BMP || encoding == MS_EID_UNICODE_FULL)) {
			info.character_map = subtable
		} else if platform == PLATFORM_ID_MICROSOFT && encoding == MS_EID_SYMBOL {
			symbol_map = subtable
		}
	}

	if len(info.character_map) == 0 {
		info.character_map = symbol_map
	}

	if len(info.character_map) == 0 {
		return .Invalid_Font_Data
	}

	switch read_u16(info.character_map, 0) {
	case 0, 4, 6, 12, 13:
	case:
		return .Invalid_Font_Data
	}

	info.ascent = read_i16(horizontal_header, 4)
	info.descent = read_i16(horizontal_header, 6)
	info.line_gap = read_i16(horizontal_header, 8)
	info.num_advances = read_u16(horizontal_header, 34)
	return .None
}

scale_for_pixel_height :: proc(info: ^Font_Info, height: f32) -> f32 {
	return height / f32(info.ascent - info.descent)
}

find_glyph_index :: proc(info: ^Font_Info, unicode_codepoint: rune) -> int {
	codepoint := int(unicode_codepoint)
	cmap := info.character_map
	format := read_u16(cmap, 0)

	switch format {
	case 0:
		bytes := read_u16(cmap, 2)

		if codepoint < bytes-6 {
			return int(cmap[6 + codepoint])
		}

	case 6:
		first := read_u16(cmap, 6)
		count := read_u16(cmap, 8)

		if codepoint >= first && codepoint < first+count {
			return read_u16(cmap, 10 + (codepoint - first)*2)
		}

	case 4:
		segcount := read_u16(cmap, 6) >> 1
		search_range := read_u16(cmap, 8) >> 1
		entry_selector := read_u16(cmap, 10)
		range_shift := read_u16(cmap, 12) >> 1
		end_count := 14
		search := end_count

		if codepoint > 0xffff {
			return 0
		}

		if codepoint >= read_u16(cmap, search + range_shift*2) {
			search += range_shift*2
		}

		search -= 2

		for entry_selector != 0 {
			search_range >>= 1
			end := read_u16(cmap, search + search_range*2)

			if codepoint > end {
				search += search_range*2
			}

			entry_selector -= 1
		}

		search += 2

		item := int(u16((search - end_count) >> 1))
		start := read_u16(cmap, 14 + segcount*2 + 2 + 2*item)
		last := read_u16(cmap, end_count + 2*item)

		if codepoint < start || codepoint > last {
			return 0
		}

		offset := read_u16(cmap, 14 + segcount*6 + 2 + 2*item)
		id_delta := read_i16(cmap, 14 + segcount*4 + 2 + 2*item)

		if offset == 0 {
			return int(u16(codepoint + id_delta))
		}

		index := read_u16(cmap, offset + (codepoint-start)*2 + 14 + segcount*6 + 2 + 2*item)

		if index == 0 {
			return 0
		}

		return int(u16(index + id_delta))

	case 12, 13:
		low := 0
		high := read_u32(cmap, 12)

		for low < high {
			mid := low + ((high-low) >> 1)
			start_char := read_u32(cmap, 16+mid*12)
			end_char := read_u32(cmap, 16+mid*12+4)

			if codepoint < start_char {
				high = mid
			} else if codepoint > end_char {
				low = mid+1
			} else {
				start_glyph := read_u32(cmap, 16+mid*12+8)

				if format == 12 {
					return start_glyph + codepoint-start_char
				}

				return start_glyph
			}
		}
	}

	return 0
}

get_glyph_advance :: proc(info: ^Font_Info, glyph: int) -> int {
	i := min(glyph, info.num_advances - 1)
	return read_i16(info.horizontal_metrics, 4*i)
}

get_glyph_kern_advance :: proc(info: ^Font_Info, glyph1: int, glyph2: int) -> int {
	gpos_advance, gpos_advance_found := get_glyph_gpos_advance(info, glyph1, glyph2)

	if gpos_advance_found {
		return gpos_advance
	}

	if len(info.kerning_pairs) == 0 {
		return 0
	}

	data := info.kerning_pairs
	l := 0
	r := read_u16(data, 10) - 1
	needle := glyph1 << 16 | glyph2

	for l <= r {
		m := (l + r) >> 1
		straw := read_u32(data, 18+(m*6))

		if needle < straw {
			r = m - 1
		} else if needle > straw {
			l = m + 1
		} else {
			return read_i16(data, 22+(m*6))
		}
	}

	return 0
}

get_glyph_box :: proc(info: ^Font_Info, glyph: int) -> Glyph_Box {
	if info.outline_format == .Compact_Font_Format {
		box, ok := cff_run_charstring(&info.cff, glyph, nil)

		if !ok {
			return {}
		}

		return box
	}

	outline := get_glyph_outline(info, glyph)

	if len(outline) == 0 {
		return {}
	}

	return {
		x0 = read_i16(outline, 2),
		y0 = read_i16(outline, 4),
		x1 = read_i16(outline, 6),
		y1 = read_i16(outline, 8),
	}
}

get_glyph_bitmap_rect :: proc(info: ^Font_Info, glyph: int, scale: f32) -> Bitmap_Rect {
	box := get_glyph_box(info, glyph)
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

get_number_of_fonts :: proc(data: []u8) -> int {
	if is_font_start(data, 0) {
		return 1
	}

	if is_font_collection(data) {
		num_fonts := read_u32(data, 8)

		if 12 + num_fonts * 4 > len(data) {
			return 0
		}

		for i in 0..<num_fonts {
			if !is_font_start(data, read_u32(data, 12 + i*4)) {
				return 0
			}
		}

		return num_fonts
	}

	return 0
}


init_rasterizer :: proc(r: ^Rasterizer, allocator: runtime.Allocator) {
	r^ = {
		vertices = make([dynamic]Vertex, allocator),
		accumulation = make([dynamic]f32, allocator),
	}
}

destroy_rasterizer :: proc(r: ^Rasterizer) {
	delete(r.vertices)
	delete(r.accumulation)
	r^ = {}
}

rasterize_glyph :: proc(
	r: ^Rasterizer,
	info: ^Font_Info,
	glyph: int,
	scale: f32,
	rect: Bitmap_Rect,
	output: []u8,
	stride: int,
	format: Rasterizer_Pixel_Format,
) #no_bounds_check {
	width := rect.width
	height := rect.height

	if width <= 0 || height <= 0 {
		return
	}

	bytes_per_pixel := format == .Alpha ? 1 : 4
	assert(stride >= width * bytes_per_pixel)
	assert(len(output) >= (height - 1) * stride + width * bytes_per_pixel)

	clear(&r.vertices)
	get_glyph_shape(info, glyph, &r.vertices)

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
				rasterizer_line_to(r, start_x, start_y)
			}

			contour_open = true
			start_x = x
			start_y = y
			r.x = x
			r.y = y

		case .Line:
			rasterizer_line_to(r, x, y)

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
		rasterizer_line_to(r, start_x, start_y)
	}

	for row in 0..<height {
		accumulation := r.accumulation[row * accumulation_stride:][:accumulation_stride]
		output_row := output[row * stride:]
		sum: f32 = 0

		switch format {
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

//
// PUBLIC API END
//

Vertex_Type :: enum u8 {
	Move = 1,
	Line,
	Curve,
	Cubic,
}

Vertex :: struct {
	x: i16,
	y: i16,
	cx: i16,
	cy: i16,
	cx1: i16,
	cy1: i16,
	type: Vertex_Type,
}

PLATFORM_ID_UNICODE :: 0
PLATFORM_ID_MICROSOFT :: 3
MS_EID_SYMBOL :: 0
MS_EID_UNICODE_BMP :: 1
MS_EID_UNICODE_FULL :: 10

read_u16 :: #force_inline proc(data: []u8, offset: int) -> int {
	return int(intrinsics.unaligned_load((^u16be)(raw_data(data[offset:offset + 2]))))
}

read_i16 :: #force_inline proc(data: []u8, offset: int) -> int {
	return int(intrinsics.unaligned_load((^i16be)(raw_data(data[offset:offset + 2]))))
}

read_u32 :: #force_inline proc(data: []u8, offset: int) -> int {
	return int(intrinsics.unaligned_load((^u32be)(raw_data(data[offset:offset + 4]))))
}

tag :: proc(data: []u8, offset: int, str: string) -> bool {
	return string(data[offset:offset + 4]) == str
}

is_font_start :: proc(data: []u8, offset: int) -> bool {
	if offset + 12 > len(data) {
		return false
	}

	return tag(data, offset, "1\x00\x00\x00") ||
	       tag(data, offset, "typ1") ||
	       tag(data, offset, "OTTO") ||
	       tag(data, offset, "\x00\x01\x00\x00") ||
	       tag(data, offset, "true")
}

is_font_collection :: proc(data: []u8) -> bool {
	if len(data) < 12 || !tag(data, 0, "ttcf") {
		return false
	}

	version := read_u32(data, 4)
	return version == 0x00010000 || version == 0x00020000
}

make_vertex :: #force_inline proc(
	type: Vertex_Type,
	x: int,
	y: int,
	cx: int,
	cy: int,
	cx1: int = 0,
	cy1: int = 0,
) -> Vertex {
	return {
		x = i16(x),
		y = i16(y),
		cx = i16(cx),
		cy = i16(cy),
		cx1 = i16(cx1),
		cy1 = i16(cy1),
		type = type,
	}
}

get_glyph_outline :: proc(info: ^Font_Info, glyph: int) -> []u8 {
	start, end: int

	switch info.tt.glyph_location_format {
	case .Short:
		if glyph < 0 || glyph >= len(info.tt.glyph_locations) / 2 - 1 {
			return nil
		}

		start = read_u16(info.tt.glyph_locations, glyph * 2) * 2
		end = read_u16(info.tt.glyph_locations, glyph * 2 + 2) * 2
	case .Long:
		if glyph < 0 || glyph >= len(info.tt.glyph_locations) / 4 - 1 {
			return nil
		}

		start = read_u32(info.tt.glyph_locations, glyph * 4)
		end = read_u32(info.tt.glyph_locations, glyph * 4 + 4)
	}

	if end <= start || end > len(info.tt.glyph_outlines) {
		return nil
	}

	return info.tt.glyph_outlines[start:end]
}

close_shape :: proc(
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

get_glyph_shape :: proc(info: ^Font_Info, glyph_index: int, all_vertices: ^[dynamic]Vertex) {
	if info.outline_format == .Compact_Font_Format {
		first_vertex := len(all_vertices)

		if _, ok := cff_run_charstring(&info.cff, glyph_index, all_vertices); !ok {
			resize(all_vertices, first_vertex)
		}

		return
	}

	outline := get_glyph_outline(info, glyph_index)

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
		end_pts_of_contours := outline[10:]
		ins := read_u16(outline, 10 + number_of_contours * 2)
		points := outline[10 + number_of_contours * 2 + 2 + ins:]

		n := 1 + read_u16(end_pts_of_contours, number_of_contours*2-2)

		m := n + 2*number_of_contours
		first_vertex := len(all_vertices)
		resize(all_vertices, first_vertex + m + 1)
		vertices := all_vertices[first_vertex:]

		next_move := 0
		off := m - n

		for i in 0..<n {
			if flagcount == 0 {
				flags = points[0]
				points = points[1:]

				if flags & 8 != 0 {
					flagcount = points[0]
					points = points[1:]
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
				dx := int(points[0])
				points = points[1:]
				x += (flags & 16) != 0 ? dx : -dx
			} else if flags & 16 == 0 {
				x += read_i16(points, 0)
				points = points[2:]
			}

			vertices[off+i].x = i16(x)
		}

		y = 0

		for i in 0..<n {
			flags = u8(vertices[off+i].type)

			if flags & 4 != 0 {
				dy := int(points[0])
				points = points[1:]
				y += (flags & 32) != 0 ? dy : -dy
			} else if flags & 32 == 0 {
				y += read_i16(points, 0)
				points = points[2:]
			}

			vertices[off+i].y = i16(y)
		}

		num_vertices := 0

		for i := 0; i < n; i += 1 {
			flags = u8(vertices[off+i].type)
			x = int(vertices[off+i].x)
			y = int(vertices[off+i].y)

			if next_move == i {
				if i != 0 {
					num_vertices = close_shape(
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

		num_vertices = close_shape(
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
		comp := outline[10:]

		for more {
			mtx := [6]f32{1, 0, 0, 1, 0, 0}

			flags := read_u16(comp, 0)
			comp = comp[2:]
			gidx := read_u16(comp, 0)
			comp = comp[2:]

			if flags & 2 != 0 {
				if flags & 1 != 0 {
					mtx[4] = f32(read_i16(comp, 0))
					comp = comp[2:]
					mtx[5] = f32(read_i16(comp, 0))
					comp = comp[2:]
				} else {
					mtx[4] = f32(i8(comp[0]))
					comp = comp[1:]
					mtx[5] = f32(i8(comp[0]))
					comp = comp[1:]
				}
			} else {
				assert(false)
			}

			if flags & (1<<3) != 0 {
				mtx[0] = f32(read_i16(comp, 0))/16384.0
				mtx[3] = mtx[0]
				comp = comp[2:]
				mtx[1] = 0
				mtx[2] = 0
			} else if flags & (1<<6) != 0 {
				mtx[0] = f32(read_i16(comp, 0))/16384.0
				comp = comp[2:]
				mtx[1] = 0
				mtx[2] = 0
				mtx[3] = f32(read_i16(comp, 0))/16384.0
				comp = comp[2:]
			} else if flags & (1<<7) != 0 {
				mtx[0] = f32(read_i16(comp, 0))/16384.0
				comp = comp[2:]
				mtx[1] = f32(read_i16(comp, 0))/16384.0
				comp = comp[2:]
				mtx[2] = f32(read_i16(comp, 0))/16384.0
				comp = comp[2:]
				mtx[3] = f32(read_i16(comp, 0))/16384.0
				comp = comp[2:]
			}

			if flags & (1<<11) != 0 && flags & (1<<12) == 0 {
				mtx[4] *= math.sqrt(mtx[0]*mtx[0] + mtx[1]*mtx[1])
				mtx[5] *= math.sqrt(mtx[2]*mtx[2] + mtx[3]*mtx[3])
			}

			first_comp_vertex := len(all_vertices)
			get_glyph_shape(info, gidx, all_vertices)

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

get_coverage_index :: proc(coverage_table: []u8, glyph: int) -> int {
	switch read_u16(coverage_table, 0) {
	case 1:
		glyph_array := coverage_table[4:]
		l := 0
		r := read_u16(coverage_table, 2) - 1

		for l <= r {
			m := (l + r) >> 1
			straw := read_u16(glyph_array, 2 * m)

			if glyph < straw {
				r = m - 1
			} else if glyph > straw {
				l = m + 1
			} else {
				return m
			}
		}

	case 2:
		range_array := coverage_table[4:]
		l := 0
		r := read_u16(coverage_table, 2) - 1

		for l <= r {
			m := (l + r) >> 1
			range_record := range_array[6 * m:]
			straw_start := read_u16(range_record, 0)
			straw_end := read_u16(range_record, 2)

			if glyph < straw_start {
				r = m - 1
			} else if glyph > straw_end {
				l = m + 1
			} else {
				return read_u16(range_record, 4) + glyph - straw_start
			}
		}
	}

	return -1
}

get_glyph_class :: proc(class_def_table: []u8, glyph: int) -> int {
	switch read_u16(class_def_table, 0) {
	case 1:
		start_glyph_id := read_u16(class_def_table, 2)
		glyph_count := read_u16(class_def_table, 4)

		if glyph >= start_glyph_id && glyph < start_glyph_id + glyph_count {
			return read_u16(class_def_table, 6 + 2 * (glyph - start_glyph_id))
		}

	case 2:
		class_range_records := class_def_table[4:]
		l := 0
		r := read_u16(class_def_table, 2) - 1

		for l <= r {
			m := (l + r) >> 1
			class_range_record := class_range_records[6 * m:]
			straw_start := read_u16(class_range_record, 0)
			straw_end := read_u16(class_range_record, 2)

			if glyph < straw_start {
				r = m - 1
			} else if glyph > straw_end {
				l = m + 1
			} else {
				return read_u16(class_range_record, 4)
			}
		}

	case:
		return -1
	}

	return 0
}

get_glyph_gpos_advance :: proc(info: ^Font_Info, glyph1: int, glyph2: int) -> (int, bool) {
	lookup_list := info.gpos_lookups

	if len(lookup_list) == 0 {
		return 0, false
	}

	lookup_count := read_u16(lookup_list, 0)

	for i in 0..<lookup_count {
		lookup_table := lookup_list[read_u16(lookup_list, 2 + 2 * i):]

		lookup_type := read_u16(lookup_table, 0)

		if lookup_type != 2 && lookup_type != 9 {
			continue
		}

		sub_table_count := read_u16(lookup_table, 4)

		for sti in 0..<sub_table_count {
			table := lookup_table[read_u16(lookup_table, 6 + 2 * sti):]

			if lookup_type == 9 {
				if read_u16(table, 0) != 1 || read_u16(table, 2) != 2 {
					continue
				}

				table = table[read_u32(table, 4):]
			}

			coverage_index := get_coverage_index(table[read_u16(table, 2):], glyph1)

			if coverage_index == -1 {
				continue
			}

			value_size := 0

			switch read_u16(table, 4) {
			case 4:
				value_size = 2
			case 68:
				value_size = 4
			}

			if value_size == 0 || read_u16(table, 6) != 0 {
				return 0, false
			}

			switch read_u16(table, 0) {
			case 1:
				if coverage_index >= read_u16(table, 8) {
					return 0, false
				}

				pair_value_table := table[read_u16(table, 10 + 2 * coverage_index):]
				pair_value_array := pair_value_table[2:]
				l := 0
				r := read_u16(pair_value_table, 0) - 1

				for l <= r {
					m := (l + r) >> 1
					pair_value := pair_value_array[(2 + value_size) * m:]
					straw := read_u16(pair_value, 0)

					if glyph2 < straw {
						r = m - 1
					} else if glyph2 > straw {
						l = m + 1
					} else {
						return read_i16(pair_value, 2), true
					}
				}

			case 2:
				glyph1_class := get_glyph_class(table[read_u16(table, 8):], glyph1)
				glyph2_class := get_glyph_class(table[read_u16(table, 10):], glyph2)
				class1_count := read_u16(table, 12)
				class2_count := read_u16(table, 14)

				if glyph1_class < 0 || glyph1_class >= class1_count {
					return 0, false
				}

				if glyph2_class < 0 || glyph2_class >= class2_count {
					return 0, false
				}

				advance := read_i16(
					table,
					16 + value_size * (glyph1_class * class2_count + glyph2_class),
				)

				return advance, true

			case:
				return 0, false
			}
		}
	}

	return 0, false
}

rasterizer_line_to :: proc(r: ^Rasterizer, to_x: f32, to_y: f32) #no_bounds_check {
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
		rasterizer_line_to(r, x2, y2)
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
		rasterizer_line_to(r, x3, y3)
	}
}
