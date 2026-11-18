#+private package
package karl2d_opentype

import "base:intrinsics"

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

get_glyph_gpos_advance :: proc(font: Font, glyph1: int, glyph2: int) -> (int, bool) {
	lookup_list := font.gpos_lookups

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
