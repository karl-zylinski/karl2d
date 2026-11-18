// This file contains the types and procs to load fonts and get information from them. For glyph
// rasterization, see `rasterizer.odin`.
package karl2d_opentype

Font :: struct {
	// Maps runes to glyph indices. `find_glyph_index` uses this.
	character_map: []u8,

	// The advance width for the `num_advance` first glyphs. Also stores left side bearing, but that
	// is not used.
	horizontal_metrics: []u8,

	head: []u8,

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

	// Data for TTF and CFF fonts. We figure this out during `load_font`.
	format: Font_Format,
}

Glyph_Index :: distinct int

GLYPH_NONE :: Glyph_Index(0)

Font_Format :: union {
	True_Type_Format,
	Compact_Font_Format,
}

Load_Error :: enum {
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

// Load a font from a slice of bytes. The bytes should be the contents of a TTF, OTF or TTC file.
// Use `font_index` to specify which font to load within a TTC file. Leave it as zero for TTF and
// OTF.
//
// The passed `font_data` slice needs to stay alive for as long as the font is used.
//
// If the returned error is `.None`, then the returned Font can be used with the other procs in this
// library that require a `Font` object.
load_font :: proc(font_data: []u8, font_index: int = 0) -> (Font, Load_Error) {
	num_fonts := get_number_of_fonts(font_data)

	if num_fonts == 0 {
		return {}, .Invalid_Font_Data
	}

	if font_index < 0 || font_index >= num_fonts {
		return {}, .Font_Index_Out_Of_Range
	}

	data := font_data
	fontstart := 0

	if is_font_collection(font_data) {
		fontstart = read_u32(data, 12+font_index*4)
	}

	font: Font
	cmap_table := find_table(data, fontstart, "cmap")
	horizontal_header := find_table(data, fontstart, "hhea")
	font.horizontal_metrics = find_table(data, fontstart, "hmtx")
	font.head = find_table(data, fontstart, "head")

	if (
		len(cmap_table) < 4 ||
		len(horizontal_header) < 36 ||
		len(font.horizontal_metrics) == 0
	) {
		return {}, .Invalid_Font_Data
	}

	font.ascent = read_i16(horizontal_header, 4)
	font.descent = read_i16(horizontal_header, 6)
	font.line_gap = read_i16(horizontal_header, 8)
	font.num_advances = read_u16(horizontal_header, 34)

	if font.ascent - font.descent <= 0 {
		return {}, .Invalid_Font_Data
	}

	if tt, tt_ok := tt_load(data, fontstart); tt_ok {
		font.format = tt
	} else if cff, cff_ok := cff_load(data, fontstart); cff_ok {
		font.format = cff
	} else {
		return {}, .Invalid_Font_Data
	}

	assert(font.format != nil)
	num_subtables := read_u16(cmap_table, 2)
	symbol_subtable: []u8

	if 4 + 8*num_subtables > len(cmap_table) {
		return {}, .Invalid_Font_Data
	}

	for i in 0..<num_subtables {
		encoding_record := 4 + 8*i
		platform := read_u16(cmap_table, encoding_record)
		encoding := read_u16(cmap_table, encoding_record+2)
		subtable_offset := read_u32(cmap_table, encoding_record+4)

		if subtable_offset + 2 > len(cmap_table) {
			continue
		}

		subtable := cmap_table[subtable_offset:]

		switch read_u16(subtable, 0) {
		case 0, 4, 6, 12, 13:
		case:
			continue
		}

		switch platform {
		case PLATFORM_ID_UNICODE:
			font.character_map = subtable
		case PLATFORM_ID_MICROSOFT:
			switch encoding {
			case MS_EID_UNICODE_BMP, MS_EID_UNICODE_FULL:
				font.character_map = subtable
			case MS_EID_SYMBOL:
				symbol_subtable = subtable
			}
		}
	}

	if len(font.character_map) == 0 {
		font.character_map = symbol_subtable
	}

	if len(font.character_map) == 0 {
		return {}, .Invalid_Font_Data
	}

	gpos_table := find_table(data, fontstart, "GPOS")
	if (
		len(gpos_table) >= 10 &&
		read_u16(gpos_table, 0) == 1 &&
		read_u16(gpos_table, 2) <= 1 &&
		read_u16(gpos_table, 8) <= len(gpos_table)
	) {
		font.gpos_lookups = gpos_table[read_u16(gpos_table, 8):]
	}

	kern_table := find_table(data, fontstart, "kern")
	if len(kern_table) >= 10 && read_u16(kern_table, 2) >= 1 && read_u16(kern_table, 8) == 1 {
		font.kerning_pairs = kern_table
	}

	return font, .None
}

pixel_scale_from_font_size :: proc(font: Font, font_size: f32) -> f32 {
	return font_size / f32(font.ascent - font.descent)
}

point_pixel_scale_from_font_size :: proc(font: Font, pixels: f32) -> f32 {
	units_per_em := read_u16(font.head, 18)
	return pixels / f32(units_per_em)
}

// For a given rune (unicode codepoint), find the glyph index. The index can later be used with
// other procedures in this library.
find_glyph_index :: proc(font: Font, codepoint: rune) -> Glyph_Index {
	cp := int(codepoint)
	cmap := font.character_map
	format := read_u16(cmap, 0)

	switch format {
	case 0:
		bytes := read_u16(cmap, 2)

		if cp < bytes-6 {
			return Glyph_Index(read_u8(cmap, 6 + cp))
		}

	case 6:
		first := read_u16(cmap, 6)
		count := read_u16(cmap, 8)

		if cp >= first && cp < first+count {
			return Glyph_Index(read_u16(cmap, 10 + (cp - first)*2))
		}

	case 4:
		segcount := read_u16(cmap, 6) >> 1
		search_range := read_u16(cmap, 8) >> 1
		entry_selector := read_u16(cmap, 10)
		range_shift := read_u16(cmap, 12) >> 1
		end_count := 14
		search := end_count

		if cp > 0xffff {
			return GLYPH_NONE
		}

		if cp >= read_u16(cmap, search + range_shift*2) {
			search += range_shift*2
		}

		search -= 2

		for entry_selector != 0 {
			search_range >>= 1
			end := read_u16(cmap, search + search_range*2)

			if cp > end {
				search += search_range*2
			}

			entry_selector -= 1
		}

		search += 2

		item := int(u16((search - end_count) >> 1))
		start := read_u16(cmap, 14 + segcount*2 + 2 + 2*item)
		last := read_u16(cmap, end_count + 2*item)

		if cp < start || cp > last {
			return GLYPH_NONE
		}

		offset := read_u16(cmap, 14 + segcount*6 + 2 + 2*item)
		id_delta := read_i16(cmap, 14 + segcount*4 + 2 + 2*item)

		if offset == 0 {
			return Glyph_Index(u16(cp + id_delta))
		}

		index := read_u16(cmap, offset + (cp-start)*2 + 14 + segcount*6 + 2 + 2*item)

		if index == 0 {
			return GLYPH_NONE
		}

		return Glyph_Index(u16(index + id_delta))

	case 12, 13:
		low := 0
		high := read_u32(cmap, 12)

		for low < high {
			mid := low + ((high-low) >> 1)
			start_char := read_u32(cmap, 16+mid*12)
			end_char := read_u32(cmap, 16+mid*12+4)

			if cp < start_char {
				high = mid
			} else if cp > end_char {
				low = mid+1
			} else {
				start_glyph := read_u32(cmap, 16+mid*12+8)

				if format == 12 {
					return Glyph_Index(start_glyph + cp-start_char)
				}

				return Glyph_Index(start_glyph)
			}
		}
	}

	return GLYPH_NONE
}

// How much horizontal space to advance the drawing for a certain glyph. This does not include
// kerning, which you get using `get_glyph_kern_advance`.
get_glyph_advance :: proc(font: Font, glyph: Glyph_Index) -> int {
	i := min(int(glyph), font.num_advances - 1)
	return read_i16(font.horizontal_metrics, 4*i)
}

// Kerning is a small horizontal advance given a specific glyph pair. Applying this advance makes
// text look better.
get_glyph_kern_advance :: proc(font: Font, glyph1: Glyph_Index, glyph2: Glyph_Index) -> int {
	gpos_advance, gpos_advance_found := get_glyph_gpos_advance(font, int(glyph1), int(glyph2))

	if gpos_advance_found {
		return gpos_advance
	}

	if len(font.kerning_pairs) == 0 {
		return 0
	}

	data := font.kerning_pairs
	l := 0
	r := read_u16(data, 10) - 1
	needle := int(glyph1) << 16 | int(glyph2)

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

get_glyph_box :: proc(font: Font, glyph: Glyph_Index) -> Glyph_Box {
	switch f in font.format {
	case Compact_Font_Format:
		box, ok := cff_run_charstring(f, int(glyph), nil)

		if !ok {
			return {}
		}

		return box
	case True_Type_Format:
		outline := tt_get_glyph_outline(f, int(glyph))

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

	return {}
}

// Given a TTF, OTF or TTC file, find how many fonts it contains.
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
