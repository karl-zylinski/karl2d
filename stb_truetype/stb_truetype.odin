// This is based on stb_truetype.h by Sean Barrett. See the LICENSE file in this folder.
package karl2d_stb_truetype

import "base:intrinsics"
import "base:runtime"
import "core:math"
import "core:slice"

Font_Info :: struct {
	data: [^]u8,
	num_glyphs: int,
	loca: int,
	glyf: int,
	hmtx: int,
	kern: int,
	gpos_lookup_list: int,
	index_map: int,
	index_to_loc_format: int,
	num_long_hor_metrics: int,
	ascent: int,
	descent: int,
	line_gap: int,
	cff: Buf,
	charstrings: Buf,
	gsubrs: Buf,
	subrs: Buf,
	fontdicts: Buf,
	fdselect: Buf,
}

Init_Error :: enum {
	None,
	Font_Index_Out_Of_Range,
	Invalid_Font_Data,
}

Bitmap_Format :: enum {
	Alpha,
	RGBA_White,
	RGBA_Premultiplied,
}

Glyph_Box :: struct {
	x0: int,
	y0: int,
	x1: int,
	y1: int,
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
	if len(data) < 4 {
		return 0
	}

	font := raw_data(data)

	if tag(font, "1\x00\x00\x00") ||
	   tag(font, "typ1") ||
	   tag(font, "OTTO") ||
	   tag(font, "\x00\x01\x00\x00") ||
	   tag(font, "true") {
		return 1
	}

	if is_font_collection(data) {
		return int(i32(read_u32(font[8:])))
	}

	return 0
}

init_font :: proc(info: ^Font_Info, font_data: []u8, font_index: int) -> Init_Error {
	num_fonts := get_number_of_fonts(font_data)

	if num_fonts == 0 {
		return .Invalid_Font_Data
	}

	if font_index < 0 || font_index >= num_fonts {
		return .Font_Index_Out_Of_Range
	}

	data := raw_data(font_data)
	fontstart := 0

	if is_font_collection(font_data) {
		fontstart = read_u32(data[12+font_index*4:])
	}

	info^ = {
		data = data,
	}

	cmap := find_table(data, fontstart, "cmap")
	head := find_table(data, fontstart, "head")
	hhea := find_table(data, fontstart, "hhea")
	kern := find_table(data, fontstart, "kern")
	gpos := find_table(data, fontstart, "GPOS")
	info.loca = find_table(data, fontstart, "loca")
	info.glyf = find_table(data, fontstart, "glyf")
	info.hmtx = find_table(data, fontstart, "hmtx")

	if cmap == 0 || head == 0 || hhea == 0 || info.hmtx == 0 {
		return .Invalid_Font_Data
	}

	if info.glyf != 0 {
		info.index_to_loc_format = read_u16(data[head + 50:])

		if info.loca == 0 || info.index_to_loc_format >= 2 {
			return .Invalid_Font_Data
		}
	} else {
		cff := find_table(data, fontstart, "CFF ")

		if cff == 0 {
			return .Invalid_Font_Data
		}

		info.cff = {
			data = data[cff:],
			size = 512*1024*1024,
		}

		b := info.cff
		buf_skip(&b, 2)
		buf_seek(&b, int(buf_get8(&b)))
		cff_get_index(&b)
		topdict := cff_index_get(cff_get_index(&b), 0)
		cff_get_index(&b)
		info.gsubrs = cff_get_index(&b)

		charstrings, _ := dict_get_ints(topdict, 17)
		cstype, cstype_count := dict_get_ints(topdict, 0x100 | 6)
		fdarray, _ := dict_get_ints(topdict, 0x100 | 36)
		fdselect, _ := dict_get_ints(topdict, 0x100 | 37)
		info.subrs = get_subrs(b, topdict)

		if (cstype_count > 0 && cstype[0] != 2) || charstrings[0] == 0 {
			return .Invalid_Font_Data
		}

		if fdarray[0] != 0 {
			if fdselect[0] == 0 {
				return .Invalid_Font_Data
			}

			buf_seek(&b, int(fdarray[0]))
			info.fontdicts = cff_get_index(&b)
			info.fdselect = buf_range(b, int(fdselect[0]), b.size-int(fdselect[0]))
		}

		buf_seek(&b, int(charstrings[0]))
		info.charstrings = cff_get_index(&b)
	}

	if gpos != 0 {
		if read_u16(data[gpos:]) == 1 && read_u16(data[gpos+2:]) == 0 {
			info.gpos_lookup_list = gpos + read_u16(data[gpos+8:])
		}
	} else if kern != 0 && read_u16(data[kern+2:]) >= 1 && read_u16(data[kern+8:]) == 1 {
		info.kern = kern
	}

	maxp := find_table(data, fontstart, "maxp")
	info.num_glyphs = 0xffff

	if maxp != 0 {
		info.num_glyphs = read_u16(data[maxp+4:])
	}

	num_tables := read_u16(data[cmap + 2:])

	for i in 0..<num_tables {
		encoding_record := cmap + 4 + 8 * i
		platform := read_u16(data[encoding_record:])
		encoding := read_u16(data[encoding_record+2:])

		if platform == PLATFORM_ID_UNICODE ||
		   (platform == PLATFORM_ID_MICROSOFT &&
		    (encoding == MS_EID_UNICODE_BMP || encoding == MS_EID_UNICODE_FULL)) {
			info.index_map = cmap + read_u32(data[encoding_record+4:])
		}
	}

	if info.index_map == 0 {
		return .Invalid_Font_Data
	}

	switch read_u16(data[info.index_map:]) {
	case 0, 4, 6, 12, 13:
	case:
		return .Invalid_Font_Data
	}

	info.ascent = read_i16(data[hhea + 4:])
	info.descent = read_i16(data[hhea + 6:])
	info.line_gap = read_i16(data[hhea + 8:])
	info.num_long_hor_metrics = read_u16(data[hhea + 34:])
	return .None
}

scale_for_pixel_height :: proc(info: ^Font_Info, height: f32) -> f32 {
	return height / f32(info.ascent - info.descent)
}

find_glyph_index :: proc(info: ^Font_Info, unicode_codepoint: rune) -> int {
	codepoint := int(unicode_codepoint)
	data := info.data
	index_map := info.index_map
	format := read_u16(data[index_map:])

	switch format {
	case 0:
		bytes := read_u16(data[index_map + 2:])

		if codepoint < bytes-6 {
			return int(data[index_map + 6 + codepoint])
		}

	case 6:
		first := read_u16(data[index_map + 6:])
		count := read_u16(data[index_map + 8:])

		if codepoint >= first && codepoint < first+count {
			return read_u16(data[index_map + 10 + (codepoint - first)*2:])
		}

	case 4:
		segcount := read_u16(data[index_map+6:]) >> 1
		search_range := read_u16(data[index_map+8:]) >> 1
		entry_selector := read_u16(data[index_map+10:])
		range_shift := read_u16(data[index_map+12:]) >> 1
		end_count := index_map + 14
		search := end_count

		if codepoint > 0xffff {
			return 0
		}

		if codepoint >= read_u16(data[search + range_shift*2:]) {
			search += range_shift*2
		}

		search -= 2

		for entry_selector != 0 {
			search_range >>= 1
			end := read_u16(data[search + search_range*2:])

			if codepoint > end {
				search += search_range*2
			}

			entry_selector -= 1
		}

		search += 2

		item := int(u16((search - end_count) >> 1))
		start := read_u16(data[index_map + 14 + segcount*2 + 2 + 2*item:])
		last := read_u16(data[end_count + 2*item:])

		if codepoint < start || codepoint > last {
			return 0
		}

		offset := read_u16(data[index_map + 14 + segcount*6 + 2 + 2*item:])

		if offset == 0 {
			id_delta := read_i16(data[index_map + 14 + segcount*4 + 2 + 2*item:])
			return int(u16(codepoint + id_delta))
		}

		return read_u16(
			data[offset + (codepoint-start)*2 + index_map + 14 + segcount*6 + 2 + 2*item:],
		)

	case 12, 13:
		low := 0
		high := read_u32(data[index_map+12:])

		for low < high {
			mid := low + ((high-low) >> 1)
			start_char := read_u32(data[index_map+16+mid*12:])
			end_char := read_u32(data[index_map+16+mid*12+4:])

			if codepoint < start_char {
				high = mid
			} else if codepoint > end_char {
				low = mid+1
			} else {
				start_glyph := read_u32(data[index_map+16+mid*12+8:])

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
	i := min(glyph, info.num_long_hor_metrics - 1)
	return read_i16(info.data[info.hmtx + 4*i:])
}

get_glyph_kern_advance :: proc(info: ^Font_Info, glyph1: int, glyph2: int) -> int {
	if info.gpos_lookup_list != 0 {
		return get_glyph_gpos_advance(info, glyph1, glyph2)
	}

	if info.kern == 0 {
		return 0
	}

	data := info.data[info.kern:]
	l := 0
	r := read_u16(data[10:]) - 1
	needle := glyph1 << 16 | glyph2

	for l <= r {
		m := (l + r) >> 1
		straw := read_u32(data[18+(m*6):])

		if needle < straw {
			r = m - 1
		} else if needle > straw {
			l = m + 1
		} else {
			return read_i16(data[22+(m*6):])
		}
	}

	return 0
}

get_glyph_box :: proc(info: ^Font_Info, glyph: int) -> Glyph_Box {
	if info.cff.size != 0 {
		c: Charstring_Context

		if !run_charstring(info, glyph, &c) {
			return {}
		}

		return {c.min_x, c.min_y, c.max_x, c.max_y}
	}

	g := get_glyf_offset(info, glyph)

	if g < 0 {
		return {}
	}

	return {
		x0 = read_i16(info.data[g + 2:]),
		y0 = read_i16(info.data[g + 4:]),
		x1 = read_i16(info.data[g + 6:]),
		y1 = read_i16(info.data[g + 8:]),
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
	format: Bitmap_Format,
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

Buf :: struct {
	data: [^]u8,
	cursor: int,
	size: int,
}

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
MS_EID_UNICODE_BMP :: 1
MS_EID_UNICODE_FULL :: 10

buf_get8 :: proc(b: ^Buf) -> u8 {
	if b.cursor >= b.size {
		return 0
	}

	r := b.data[b.cursor]
	b.cursor += 1
	return r
}

buf_peek8 :: proc(b: ^Buf) -> u8 {
	if b.cursor >= b.size {
		return 0
	}

	return b.data[b.cursor]
}

buf_seek :: proc(b: ^Buf, o: int) {
	assert(!(o > b.size || o < 0))
	b.cursor = (o > b.size || o < 0) ? b.size : o
}

buf_skip :: proc(b: ^Buf, o: int) {
	buf_seek(b, b.cursor + o)
}

buf_get :: proc(b: ^Buf, n: int) -> u32 {
	v: u32 = 0
	assert(n >= 1 && n <= 4)

	for _ in 0..<n {
		v = (v << 8) | u32(buf_get8(b))
	}

	return v
}

buf_range :: proc(b: Buf, o: int, s: int) -> Buf {
	if o < 0 || s < 0 || o > b.size || s > b.size - o {
		return {}
	}

	return {
		data = b.data[o:],
		size = s,
	}
}

cff_get_index :: proc(b: ^Buf) -> Buf {
	start := b.cursor
	count := int(buf_get(b, 2))

	if count != 0 {
		offsize := int(buf_get8(b))
		assert(offsize >= 1 && offsize <= 4)
		buf_skip(b, offsize * count)
		buf_skip(b, int(buf_get(b, offsize)) - 1)
	}

	return buf_range(b^, start, b.cursor - start)
}

cff_int :: proc(b: ^Buf) -> u32 {
	b0 := int(buf_get8(b))

	if b0 >= 32 && b0 <= 246 {
		return u32(b0 - 139)
	} else if b0 >= 247 && b0 <= 250 {
		return u32((b0 - 247)*256 + int(buf_get8(b)) + 108)
	} else if b0 >= 251 && b0 <= 254 {
		return u32(-(b0 - 251)*256 - int(buf_get8(b)) - 108)
	} else if b0 == 28 {
		return buf_get(b, 2)
	} else if b0 == 29 {
		return buf_get(b, 4)
	}

	assert(false)
	return 0
}

dict_get_ints :: proc(dict: Buf, key: int) -> (values: [2]u32, count: int) {
	b := dict
	b.cursor = 0

	for b.cursor < b.size {
		start := b.cursor

		for buf_peek8(&b) >= 28 {
			if buf_peek8(&b) == 30 {
				buf_skip(&b, 1)

				for b.cursor < b.size {
					v := buf_get8(&b)

					if (v & 0xF) == 0xF || (v >> 4) == 0xF {
						break
					}
				}
			} else {
				cff_int(&b)
			}
		}

		end := b.cursor
		op := int(buf_get8(&b))

		if op == 12 {
			op = int(buf_get8(&b)) | 0x100
		}

		if op == key {
			operands := buf_range(b, start, end-start)

			for count < len(values) && operands.cursor < operands.size {
				values[count] = cff_int(&operands)
				count += 1
			}

			return values, count
		}
	}

	return values, count
}

cff_index_get :: proc(b: Buf, i: int) -> Buf {
	b := b
	buf_seek(&b, 0)
	count := int(buf_get(&b, 2))
	offsize := int(buf_get8(&b))
	assert(i >= 0 && i < count)
	assert(offsize >= 1 && offsize <= 4)
	buf_skip(&b, i*offsize)
	start := int(buf_get(&b, offsize))
	end := int(buf_get(&b, offsize))
	return buf_range(b, 2+(count+1)*offsize+start, end - start)
}

read_u16 :: #force_inline proc(p: [^]u8) -> int {
	return int(intrinsics.unaligned_load((^u16be)(p)))
}

read_i16 :: #force_inline proc(p: [^]u8) -> int {
	return int(intrinsics.unaligned_load((^i16be)(p)))
}

read_u32 :: #force_inline proc(p: [^]u8) -> int {
	return int(intrinsics.unaligned_load((^u32be)(p)))
}

tag :: proc(p: [^]u8, str: string) -> bool {
	return p[0] == str[0] && p[1] == str[1] && p[2] == str[2] && p[3] == str[3]
}

is_font_collection :: proc(data: []u8) -> bool {
	if len(data) < 12 || !tag(raw_data(data), "ttcf") {
		return false
	}

	version := read_u32(raw_data(data)[4:])
	return version == 0x00010000 || version == 0x00020000
}

find_table :: proc(data: [^]u8, fontstart: int, table_tag: string) -> int {
	num_tables := read_u16(data[fontstart+4:])
	tabledir := fontstart + 12

	for i in 0..<num_tables {
		loc := tabledir + 16*i

		if tag(data[loc:], table_tag) {
			return read_u32(data[loc+8:])
		}
	}

	return 0
}

get_subrs :: proc(cff: Buf, fontdict: Buf) -> Buf {
	cff := cff
	private_dict, _ := dict_get_ints(fontdict, 18)
	private_size := int(private_dict[0])
	private_offset := int(private_dict[1])

	if private_size == 0 || private_offset == 0 {
		return {}
	}

	subrs_offset, _ := dict_get_ints(buf_range(cff, private_offset, private_size), 19)

	if subrs_offset[0] == 0 {
		return {}
	}

	buf_seek(&cff, private_offset + int(subrs_offset[0]))
	return cff_get_index(&cff)
}

set_vertex :: #force_inline proc(
	v: ^Vertex,
	type: Vertex_Type,
	x: int,
	y: int,
	cx: int,
	cy: int,
) {
	v.type = type
	v.x = i16(x)
	v.y = i16(y)
	v.cx = i16(cx)
	v.cy = i16(cy)
}

get_glyf_offset :: proc(info: ^Font_Info, glyph_index: int) -> int {
	g1, g2: int

	if glyph_index >= info.num_glyphs {
		return -1
	}

	if info.index_to_loc_format == 0 {
		g1 = info.glyf + read_u16(info.data[info.loca + glyph_index * 2:]) * 2
		g2 = info.glyf + read_u16(info.data[info.loca + glyph_index * 2 + 2:]) * 2
	} else {
		g1 = info.glyf + read_u32(info.data[info.loca + glyph_index * 4:])
		g2 = info.glyf + read_u32(info.data[info.loca + glyph_index * 4 + 4:])
	}

	return g1==g2 ? -1 : g1
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
			set_vertex(&vertices[num_vertices], .Curve, (cx+scx)>>1, (cy+scy)>>1, cx, cy)
			num_vertices += 1
		}

		set_vertex(&vertices[num_vertices], .Curve, sx, sy, scx, scy)
		num_vertices += 1
	} else {
		if was_off {
			set_vertex(&vertices[num_vertices], .Curve, sx, sy, cx, cy)
		} else {
			set_vertex(&vertices[num_vertices], .Line, sx, sy, 0, 0)
		}

		num_vertices += 1
	}

	return num_vertices
}

get_glyph_shape :: proc(info: ^Font_Info, glyph_index: int, all_vertices: ^[dynamic]Vertex) {
	if info.cff.size != 0 {
		first_vertex := len(all_vertices)

		c := Charstring_Context {
			vertices = all_vertices,
		}

		if !run_charstring(info, glyph_index, &c) {
			resize(all_vertices, first_vertex)
		}

		return
	}

	data := info.data
	g := get_glyf_offset(info, glyph_index)

	if g < 0 {
		return
	}

	number_of_contours := read_i16(data[g:])

	if number_of_contours > 0 {
		flags: u8 = 0
		flagcount: u8 = 0
		j := 0
		was_off := false
		start_off := false
		x, y, cx, cy, sx, sy, scx, scy: int
		end_pts_of_contours := data[g + 10:]
		ins := read_u16(data[g + 10 + number_of_contours * 2:])
		points := data[g + 10 + number_of_contours * 2 + 2 + ins:]

		n := 1 + read_u16(end_pts_of_contours[number_of_contours*2-2:])

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
				x += read_i16(points)
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
				y += read_i16(points)
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

				start_off = flags & 1 == 0

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

				set_vertex(&vertices[num_vertices], .Move, sx, sy, 0, 0)
				num_vertices += 1
				was_off = false
				next_move = 1 + read_u16(end_pts_of_contours[j*2:])
				j += 1
			} else if flags & 1 == 0 {
				if was_off {
					set_vertex(&vertices[num_vertices], .Curve, (cx+x)>>1, (cy+y)>>1, cx, cy)
					num_vertices += 1
				}

				cx = x
				cy = y
				was_off = true
			} else {
				if was_off {
					set_vertex(&vertices[num_vertices], .Curve, x, y, cx, cy)
				} else {
					set_vertex(&vertices[num_vertices], .Line, x, y, 0, 0)
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
		comp := data[g + 10:]

		for more {
			mtx := [6]f32{1, 0, 0, 1, 0, 0}

			flags := read_u16(comp)
			comp = comp[2:]
			gidx := read_u16(comp)
			comp = comp[2:]

			if flags & 2 != 0 {
				if flags & 1 != 0 {
					mtx[4] = f32(read_i16(comp))
					comp = comp[2:]
					mtx[5] = f32(read_i16(comp))
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
				mtx[0] = f32(read_i16(comp))/16384.0
				mtx[3] = mtx[0]
				comp = comp[2:]
				mtx[1] = 0
				mtx[2] = 0
			} else if flags & (1<<6) != 0 {
				mtx[0] = f32(read_i16(comp))/16384.0
				comp = comp[2:]
				mtx[1] = 0
				mtx[2] = 0
				mtx[3] = f32(read_i16(comp))/16384.0
				comp = comp[2:]
			} else if flags & (1<<7) != 0 {
				mtx[0] = f32(read_i16(comp))/16384.0
				comp = comp[2:]
				mtx[1] = f32(read_i16(comp))/16384.0
				comp = comp[2:]
				mtx[2] = f32(read_i16(comp))/16384.0
				comp = comp[2:]
				mtx[3] = f32(read_i16(comp))/16384.0
				comp = comp[2:]
			}

			m := math.sqrt(mtx[0]*mtx[0] + mtx[1]*mtx[1])
			n := math.sqrt(mtx[2]*mtx[2] + mtx[3]*mtx[3])

			first_comp_vertex := len(all_vertices)
			get_glyph_shape(info, gidx, all_vertices)

			for &v in all_vertices[first_comp_vertex:] {
				x := f32(v.x)
				y := f32(v.y)
				v.x = i16(i32(m * (mtx[0]*x + mtx[2]*y + mtx[4])))
				v.y = i16(i32(n * (mtx[1]*x + mtx[3]*y + mtx[5])))
				x = f32(v.cx)
				y = f32(v.cy)
				v.cx = i16(i32(m * (mtx[0]*x + mtx[2]*y + mtx[4])))
				v.cy = i16(i32(n * (mtx[1]*x + mtx[3]*y + mtx[5])))
			}

			more = flags & (1<<5) != 0
		}
	}
}

Charstring_Context :: struct {
	started: bool,
	first_x: f32,
	first_y: f32,
	x: f32,
	y: f32,
	min_x: int,
	max_x: int,
	min_y: int,
	max_y: int,
	vertices: ^[dynamic]Vertex,
}

track_vertex :: proc(c: ^Charstring_Context, x: int, y: int) {
	if x > c.max_x || !c.started {
		c.max_x = x
	}

	if y > c.max_y || !c.started {
		c.max_y = y
	}

	if x < c.min_x || !c.started {
		c.min_x = x
	}

	if y < c.min_y || !c.started {
		c.min_y = y
	}

	c.started = true
}

csctx_v :: proc(
	c: ^Charstring_Context,
	type: Vertex_Type,
	x: int,
	y: int,
	cx: int,
	cy: int,
	cx1: int,
	cy1: int,
) {
	if c.vertices == nil {
		track_vertex(c, x, y)

		if type == .Cubic {
			track_vertex(c, cx, cy)
			track_vertex(c, cx1, cy1)
		}

		return
	}

	append(c.vertices, Vertex {
		x = i16(x),
		y = i16(y),
		cx = i16(cx),
		cy = i16(cy),
		cx1 = i16(cx1),
		cy1 = i16(cy1),
		type = type,
	})
}

csctx_close_shape :: proc(ctx: ^Charstring_Context) {
	if ctx.first_x != ctx.x || ctx.first_y != ctx.y {
		csctx_v(ctx, .Line, int(ctx.first_x), int(ctx.first_y), 0, 0, 0, 0)
	}
}

csctx_rmove_to :: proc(ctx: ^Charstring_Context, dx: f32, dy: f32) {
	csctx_close_shape(ctx)
	ctx.x += dx
	ctx.y += dy
	ctx.first_x = ctx.x
	ctx.first_y = ctx.y
	csctx_v(ctx, .Move, int(ctx.x), int(ctx.y), 0, 0, 0, 0)
}

csctx_rline_to :: proc(ctx: ^Charstring_Context, dx: f32, dy: f32) {
	ctx.x += dx
	ctx.y += dy
	csctx_v(ctx, .Line, int(ctx.x), int(ctx.y), 0, 0, 0, 0)
}

csctx_rccurve_to :: proc(
	ctx: ^Charstring_Context,
	dx1: f32,
	dy1: f32,
	dx2: f32,
	dy2: f32,
	dx3: f32,
	dy3: f32,
) {
	cx1 := ctx.x + dx1
	cy1 := ctx.y + dy1
	cx2 := cx1 + dx2
	cy2 := cy1 + dy2
	ctx.x = cx2 + dx3
	ctx.y = cy2 + dy3
	csctx_v(ctx, .Cubic, int(ctx.x), int(ctx.y), int(cx1), int(cy1), int(cx2), int(cy2))
}

run_charstring :: proc(info: ^Font_Info, glyph_index: int, c: ^Charstring_Context) -> bool {
	in_header := true
	maskbits := 0
	subr_stack_height := 0
	sp := 0
	has_subrs := false
	s: [48]f32 = ---
	subr_stack: [10]Buf = ---
	subrs := info.subrs
	f: f32

	b := cff_index_get(info.charstrings, glyph_index)

	for b.cursor < b.size {
		i := 0
		clear_stack := true
		b0 := int(buf_get8(&b))

		switch b0 {
		case 0x13, 0x14:
			if in_header {
				maskbits += (sp / 2)
			}

			in_header = false
			buf_skip(&b, (maskbits + 7) / 8)

		case 0x01, 0x03, 0x12, 0x17:
			maskbits += (sp / 2)

		case 0x15:
			in_header = false

			if sp < 2 {
				return false
			}

			csctx_rmove_to(c, s[sp-2], s[sp-1])

		case 0x04:
			in_header = false

			if sp < 1 {
				return false
			}

			csctx_rmove_to(c, 0, s[sp-1])

		case 0x16:
			in_header = false

			if sp < 1 {
				return false
			}

			csctx_rmove_to(c, s[sp-1], 0)

		case 0x05:
			if sp < 2 {
				return false
			}

			for ; i + 1 < sp; i += 2 {
				csctx_rline_to(c, s[i], s[i+1])
			}

		case 0x07, 0x06:
			if sp < 1 {
				return false
			}

			vertical := b0 == 0x07

			for {
				if !vertical {
					if i >= sp {
						break
					}

					csctx_rline_to(c, s[i], 0)
					i += 1
				}

				vertical = false

				if i >= sp {
					break
				}

				csctx_rline_to(c, 0, s[i])
				i += 1
			}

		case 0x1F, 0x1E:
			if sp < 4 {
				return false
			}

			horizontal := b0 == 0x1F

			for {
				if !horizontal {
					if i + 3 >= sp {
						break
					}

					csctx_rccurve_to(
						c,
						0,
						s[i],
						s[i+1],
						s[i+2],
						s[i+3],
						(sp - i == 5) ? s[i + 4] : 0.0,
					)

					i += 4
				}

				horizontal = false

				if i + 3 >= sp {
					break
				}

				csctx_rccurve_to(
					c,
					s[i],
					0,
					s[i+1],
					s[i+2],
					(sp - i == 5) ? s[i+4] : 0.0,
					s[i+3],
				)

				i += 4
			}

		case 0x08:
			if sp < 6 {
				return false
			}

			for ; i + 5 < sp; i += 6 {
				csctx_rccurve_to(c, s[i], s[i+1], s[i+2], s[i+3], s[i+4], s[i+5])
			}

		case 0x18:
			if sp < 8 {
				return false
			}

			for ; i + 5 < sp - 2; i += 6 {
				csctx_rccurve_to(c, s[i], s[i+1], s[i+2], s[i+3], s[i+4], s[i+5])
			}

			if i + 1 >= sp {
				return false
			}

			csctx_rline_to(c, s[i], s[i+1])

		case 0x19:
			if sp < 8 {
				return false
			}

			for ; i + 1 < sp - 6; i += 2 {
				csctx_rline_to(c, s[i], s[i+1])
			}

			if i + 5 >= sp {
				return false
			}

			csctx_rccurve_to(c, s[i], s[i+1], s[i+2], s[i+3], s[i+4], s[i+5])

		case 0x1A, 0x1B:
			if sp < 4 {
				return false
			}

			f = 0.0

			if sp & 1 != 0 {
				f = s[i]
				i += 1
			}

			for ; i + 3 < sp; i += 4 {
				if b0 == 0x1B {
					csctx_rccurve_to(c, s[i], f, s[i+1], s[i+2], s[i+3], 0.0)
				} else {
					csctx_rccurve_to(c, f, s[i], s[i+1], s[i+2], 0.0, s[i+3])
				}

				f = 0.0
			}

		case 0x0A:
			if !has_subrs {
				if info.fdselect.size != 0 {
					subrs = {}
					fdselect := info.fdselect
					fdselector := -1
					buf_seek(&fdselect, 0)
					fmt := buf_get8(&fdselect)

					if fmt == 0 {
						buf_skip(&fdselect, glyph_index)
						fdselector = int(buf_get8(&fdselect))
					} else if fmt == 3 {
						nranges := int(buf_get(&fdselect, 2))
						start := int(buf_get(&fdselect, 2))

						for _ in 0..<nranges {
							v := int(buf_get8(&fdselect))
							end := int(buf_get(&fdselect, 2))

							if glyph_index >= start && glyph_index < end {
								fdselector = v
								break
							}

							start = end
						}
					}

					if fdselector != -1 {
						fontdict := cff_index_get(info.fontdicts, fdselector)
						subrs = get_subrs(info.cff, fontdict)
					}
				}

				has_subrs = true
			}

			fallthrough

		case 0x1D:
			if sp < 1 || subr_stack_height >= 10 {
				return false
			}

			sp -= 1
			subr_index := b0 == 0x0A ? subrs : info.gsubrs
			buf_seek(&subr_index, 0)
			count := int(buf_get(&subr_index, 2))
			bias := 107

			if count >= 33900 {
				bias = 32768
			} else if count >= 1240 {
				bias = 1131
			}

			subr := int(s[sp]) + bias

			if subr < 0 || subr >= count {
				return false
			}

			subr_stack[subr_stack_height] = b
			subr_stack_height += 1
			b = cff_index_get(subr_index, subr)

			if b.size == 0 {
				return false
			}

			clear_stack = false

		case 0x0B:
			if subr_stack_height <= 0 {
				return false
			}

			subr_stack_height -= 1
			b = subr_stack[subr_stack_height]
			clear_stack = false

		case 0x0E:
			csctx_close_shape(c)
			return true

		case 0x0C:
			dx1, dx2, dx3, dx4, dx5, dx6, dy1, dy2, dy3, dy4, dy5, dy6: f32
			b1 := int(buf_get8(&b))

			switch b1 {
			case 0x22:
				if sp < 7 {
					return false
				}

				dx1 = s[0]
				dx2 = s[1]
				dy2 = s[2]
				dx3 = s[3]
				dx4 = s[4]
				dx5 = s[5]
				dx6 = s[6]
				csctx_rccurve_to(c, dx1, 0, dx2, dy2, dx3, 0)
				csctx_rccurve_to(c, dx4, 0, dx5, -dy2, dx6, 0)

			case 0x23:
				if sp < 13 {
					return false
				}

				dx1 = s[0]
				dy1 = s[1]
				dx2 = s[2]
				dy2 = s[3]
				dx3 = s[4]
				dy3 = s[5]
				dx4 = s[6]
				dy4 = s[7]
				dx5 = s[8]
				dy5 = s[9]
				dx6 = s[10]
				dy6 = s[11]
				csctx_rccurve_to(c, dx1, dy1, dx2, dy2, dx3, dy3)
				csctx_rccurve_to(c, dx4, dy4, dx5, dy5, dx6, dy6)

			case 0x24:
				if sp < 9 {
					return false
				}

				dx1 = s[0]
				dy1 = s[1]
				dx2 = s[2]
				dy2 = s[3]
				dx3 = s[4]
				dx4 = s[5]
				dx5 = s[6]
				dy5 = s[7]
				dx6 = s[8]
				csctx_rccurve_to(c, dx1, dy1, dx2, dy2, dx3, 0)
				csctx_rccurve_to(c, dx4, 0, dx5, dy5, dx6, -(dy1+dy2+dy5))

			case 0x25:
				if sp < 11 {
					return false
				}

				dx1 = s[0]
				dy1 = s[1]
				dx2 = s[2]
				dy2 = s[3]
				dx3 = s[4]
				dy3 = s[5]
				dx4 = s[6]
				dy4 = s[7]
				dx5 = s[8]
				dy5 = s[9]
				dx6 = s[10]
				dy6 = s[10]
				dx := dx1+dx2+dx3+dx4+dx5
				dy := dy1+dy2+dy3+dy4+dy5

				if abs(dx) > abs(dy) {
					dy6 = -dy
				} else {
					dx6 = -dx
				}

				csctx_rccurve_to(c, dx1, dy1, dx2, dy2, dx3, dy3)
				csctx_rccurve_to(c, dx4, dy4, dx5, dy5, dx6, dy6)

			case:
				return false
			}

		case:
			if b0 != 255 && b0 != 28 && b0 < 32 {
				return false
			}

			if b0 == 255 {
				f = f32(i32(buf_get(&b, 4))) / 0x10000
			} else {
				buf_skip(&b, -1)
				f = f32(i16(cff_int(&b)))
			}

			if sp >= 48 {
				return false
			}

			s[sp] = f
			sp += 1
			clear_stack = false
		}

		if clear_stack {
			sp = 0
		}
	}

	return false
}

get_coverage_index :: proc(coverage_table: [^]u8, glyph: int) -> int {
	switch read_u16(coverage_table) {
	case 1:
		glyph_array := coverage_table[4:]
		l := 0
		r := read_u16(coverage_table[2:]) - 1

		for l <= r {
			m := (l + r) >> 1
			straw := read_u16(glyph_array[2 * m:])

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
		r := read_u16(coverage_table[2:]) - 1

		for l <= r {
			m := (l + r) >> 1
			range_record := range_array[6 * m:]
			straw_start := read_u16(range_record)
			straw_end := read_u16(range_record[2:])

			if glyph < straw_start {
				r = m - 1
			} else if glyph > straw_end {
				l = m + 1
			} else {
				return read_u16(range_record[4:]) + glyph - straw_start
			}
		}
	}

	return -1
}

get_glyph_class :: proc(class_def_table: [^]u8, glyph: int) -> int {
	switch read_u16(class_def_table) {
	case 1:
		start_glyph_id := read_u16(class_def_table[2:])
		glyph_count := read_u16(class_def_table[4:])

		if glyph >= start_glyph_id && glyph < start_glyph_id + glyph_count {
			return read_u16(class_def_table[6 + 2 * (glyph - start_glyph_id):])
		}

	case 2:
		class_range_records := class_def_table[4:]
		l := 0
		r := read_u16(class_def_table[2:]) - 1

		for l <= r {
			m := (l + r) >> 1
			class_range_record := class_range_records[6 * m:]
			straw_start := read_u16(class_range_record)
			straw_end := read_u16(class_range_record[2:])

			if glyph < straw_start {
				r = m - 1
			} else if glyph > straw_end {
				l = m + 1
			} else {
				return read_u16(class_range_record[4:])
			}
		}

	case:
		return -1
	}

	return 0
}

get_glyph_gpos_advance :: proc(info: ^Font_Info, glyph1: int, glyph2: int) -> int {
	lookup_list := info.data[info.gpos_lookup_list:]
	lookup_count := read_u16(lookup_list)

	for i in 0..<lookup_count {
		lookup_table := lookup_list[read_u16(lookup_list[2 + 2 * i:]):]

		if read_u16(lookup_table) != 2 {
			continue
		}

		sub_table_count := read_u16(lookup_table[4:])

		for sti in 0..<sub_table_count {
			table := lookup_table[read_u16(lookup_table[6 + 2 * sti:]):]
			coverage_index := get_coverage_index(table[read_u16(table[2:]):], glyph1)

			if coverage_index == -1 {
				continue
			}

			if read_u16(table[4:]) != 4 || read_u16(table[6:]) != 0 {
				return 0
			}

			switch read_u16(table) {
			case 1:
				if coverage_index >= read_u16(table[8:]) {
					return 0
				}

				pair_value_table := table[read_u16(table[10 + 2 * coverage_index:]):]
				pair_value_array := pair_value_table[2:]
				l := 0
				r := read_u16(pair_value_table) - 1

				for l <= r {
					m := (l + r) >> 1
					pair_value := pair_value_array[4 * m:]
					straw := read_u16(pair_value)

					if glyph2 < straw {
						r = m - 1
					} else if glyph2 > straw {
						l = m + 1
					} else {
						return read_i16(pair_value[2:])
					}
				}

			case 2:
				glyph1_class := get_glyph_class(table[read_u16(table[8:]):], glyph1)
				glyph2_class := get_glyph_class(table[read_u16(table[10:]):], glyph2)
				class1_count := read_u16(table[12:])
				class2_count := read_u16(table[14:])

				if glyph1_class < 0 || glyph1_class >= class1_count {
					return 0
				}

				if glyph2_class < 0 || glyph2_class >= class2_count {
					return 0
				}

				return read_i16(table[16 + 2 * (glyph1_class * class2_count + glyph2_class):])

			case:
				return 0
			}
		}
	}

	return 0
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
