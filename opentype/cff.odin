// This is based on stb_truetype.h by Sean Barrett. See the LICENSE file in this folder.
#+private package
package karl2d_stb_truetype

CFF_Info :: struct {
	table: []u8,
	charstrings: []u8,
	global_subroutines: []u8,
	local_subroutines: []u8,
	font_dicts: []u8,
	font_dict_select: []u8,
}

cff_init :: proc(table: []u8) -> (CFF_Info, bool) {
	if len(table) == 0 {
		return {}, false
	}

	cff := CFF_Info {
		table = table,
	}

	_, name_index_end := cff_read_index(table, cff_uint(table, 2, 1))
	top_dicts, top_dicts_end := cff_read_index(table, name_index_end)
	topdict := cff_index_item(top_dicts, 0)
	_, string_index_end := cff_read_index(table, top_dicts_end)
	cff.global_subroutines, _ = cff_read_index(table, string_index_end)

	charstrings, _ := cff_dict_get_ints(topdict, 17)
	cstype, cstype_count := cff_dict_get_ints(topdict, 0x100 | 6)
	fdarray, _ := cff_dict_get_ints(topdict, 0x100 | 36)
	fdselect, _ := cff_dict_get_ints(topdict, 0x100 | 37)
	cff.local_subroutines = cff_local_subroutines(table, topdict)

	if (cstype_count > 0 && cstype[0] != 2) || charstrings[0] == 0 {
		return {}, false
	}

	if fdarray[0] != 0 {
		if fdselect[0] == 0 {
			return {}, false
		}

		cff.font_dicts, _ = cff_read_index(table, int(fdarray[0]))
		cff.font_dict_select = cff_slice(table, int(fdselect[0]), len(table) - int(fdselect[0]))
	}

	cff.charstrings, _ = cff_read_index(table, int(charstrings[0]))
	return cff, true
}

cff_uint :: proc(data: []u8, offset: int, size: int) -> int {
	v := 0

	for i in 0..<size {
		v <<= 8

		if offset + i >= 0 && offset + i < len(data) {
			v |= int(data[offset + i])
		}
	}

	return v
}

cff_read_uint :: proc(data: []u8, cursor: ^int, size: int) -> int {
	v := cff_uint(data, cursor^, size)
	cursor^ = min(cursor^ + size, len(data))
	return v
}

cff_clamp_offset :: proc(data: []u8, offset: int) -> int {
	return (offset > len(data) || offset < 0) ? len(data) : offset
}

cff_slice :: proc(data: []u8, offset: int, size: int) -> []u8 {
	if offset < 0 || size < 0 || offset > len(data) || size > len(data) - offset {
		return nil
	}

	return data[offset:offset + size]
}

cff_read_index :: proc(data: []u8, offset: int) -> (index: []u8, next: int) {
	start := cff_clamp_offset(data, offset)
	cursor := start
	count := cff_read_uint(data, &cursor, 2)

	if count != 0 {
		offsize := cff_read_uint(data, &cursor, 1)
		assert(offsize >= 1 && offsize <= 4)
		cursor = cff_clamp_offset(data, cursor + offsize * count)
		last := cff_read_uint(data, &cursor, offsize)
		cursor = cff_clamp_offset(data, cursor + last - 1)
	}

	return data[start:cursor], cursor
}

cff_index_item :: proc(index: []u8, i: int) -> []u8 {
	count := cff_uint(index, 0, 2)
	offsize := cff_uint(index, 2, 1)
	assert(i >= 0 && i < count)
	assert(offsize >= 1 && offsize <= 4)
	offset := 3 + i * offsize
	start := cff_uint(index, offset, offsize)
	end := cff_uint(index, offset + offsize, offsize)
	return cff_slice(index, 2 + (count + 1) * offsize + start, end - start)
}

cff_int :: proc(data: []u8, cursor: ^int) -> u32 {
	b0 := cff_read_uint(data, cursor, 1)

	if b0 >= 32 && b0 <= 246 {
		return u32(b0 - 139)
	} else if b0 >= 247 && b0 <= 250 {
		return u32((b0 - 247)*256 + cff_read_uint(data, cursor, 1) + 108)
	} else if b0 >= 251 && b0 <= 254 {
		return u32(-(b0 - 251)*256 - cff_read_uint(data, cursor, 1) - 108)
	} else if b0 == 28 {
		return u32(cff_read_uint(data, cursor, 2))
	} else if b0 == 29 {
		return u32(cff_read_uint(data, cursor, 4))
	}

	assert(false)
	return 0
}

cff_dict_get_ints :: proc(dict: []u8, key: int) -> (values: [2]u32, count: int) {
	cursor := 0

	for cursor < len(dict) {
		start := cursor

		for cff_uint(dict, cursor, 1) >= 28 {
			if cff_uint(dict, cursor, 1) == 30 {
				cursor += 1

				for cursor < len(dict) {
					v := cff_read_uint(dict, &cursor, 1)

					if (v & 0xF) == 0xF || (v >> 4) == 0xF {
						break
					}
				}
			} else {
				cff_int(dict, &cursor)
			}
		}

		end := cursor
		op := cff_read_uint(dict, &cursor, 1)

		if op == 12 {
			op = cff_read_uint(dict, &cursor, 1) | 0x100
		}

		if op == key {
			operands := dict[start:end]
			operand_cursor := 0

			for count < len(values) && operand_cursor < len(operands) {
				values[count] = cff_int(operands, &operand_cursor)
				count += 1
			}

			return values, count
		}
	}

	return values, count
}

cff_local_subroutines :: proc(table: []u8, fontdict: []u8) -> []u8 {
	private_dict, _ := cff_dict_get_ints(fontdict, 18)
	private_size := int(private_dict[0])
	private_offset := int(private_dict[1])

	if private_size == 0 || private_offset == 0 {
		return nil
	}

	subrs_offset, _ := cff_dict_get_ints(cff_slice(table, private_offset, private_size), 19)

	if subrs_offset[0] == 0 {
		return nil
	}

	subrs, _ := cff_read_index(table, private_offset + int(subrs_offset[0]))
	return subrs
}

cff_run_charstring :: proc(
	cff: ^CFF_Info,
	glyph_index: int,
	vertices: ^[dynamic]Vertex,
) -> (Glyph_Box, bool) {
	CFF_Charstring_Context :: struct {
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

	track_vertex :: proc(c: ^CFF_Charstring_Context, x: int, y: int) {
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

	add_vertex :: proc(
		c: ^CFF_Charstring_Context,
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

		append(c.vertices, make_vertex(type, x, y, cx, cy, cx1, cy1))
	}

	close_shape :: proc(ctx: ^CFF_Charstring_Context) {
		if ctx.first_x != ctx.x || ctx.first_y != ctx.y {
			add_vertex(ctx, .Line, int(ctx.first_x), int(ctx.first_y), 0, 0, 0, 0)
		}
	}

	move_to :: proc(ctx: ^CFF_Charstring_Context, dx: f32, dy: f32) {
		close_shape(ctx)
		ctx.x += dx
		ctx.y += dy
		ctx.first_x = ctx.x
		ctx.first_y = ctx.y
		add_vertex(ctx, .Move, int(ctx.x), int(ctx.y), 0, 0, 0, 0)
	}

	line_to :: proc(ctx: ^CFF_Charstring_Context, dx: f32, dy: f32) {
		ctx.x += dx
		ctx.y += dy
		add_vertex(ctx, .Line, int(ctx.x), int(ctx.y), 0, 0, 0, 0)
	}

	curve_to :: proc(
		ctx: ^CFF_Charstring_Context,
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
		add_vertex(ctx, .Cubic, int(ctx.x), int(ctx.y), int(cx1), int(cy1), int(cx2), int(cy2))
	}

	ctx := CFF_Charstring_Context {
		vertices = vertices,
	}

	c := &ctx
	in_header := true
	maskbits := 0
	subr_stack_height := 0
	sp := 0
	has_subrs := false
	s: [48]f32 = ---
	subr_stack_code: [10][]u8 = ---
	subr_stack_cursor: [10]int = ---
	subrs := cff.local_subroutines
	f: f32

	code := cff_index_item(cff.charstrings, glyph_index)
	cursor := 0

	for cursor < len(code) {
		i := 0
		clear_stack := true
		b0 := cff_read_uint(code, &cursor, 1)

		switch b0 {
		case 0x13, 0x14:
			if in_header {
				maskbits += (sp / 2)
			}

			in_header = false
			cursor = cff_clamp_offset(code, cursor + (maskbits + 7) / 8)

		case 0x01, 0x03, 0x12, 0x17:
			maskbits += (sp / 2)

		case 0x15:
			in_header = false

			if sp < 2 {
				return {}, false
			}

			move_to(c, s[sp-2], s[sp-1])

		case 0x04:
			in_header = false

			if sp < 1 {
				return {}, false
			}

			move_to(c, 0, s[sp-1])

		case 0x16:
			in_header = false

			if sp < 1 {
				return {}, false
			}

			move_to(c, s[sp-1], 0)

		case 0x05:
			if sp < 2 {
				return {}, false
			}

			for ; i + 1 < sp; i += 2 {
				line_to(c, s[i], s[i+1])
			}

		case 0x07, 0x06:
			if sp < 1 {
				return {}, false
			}

			vertical := b0 == 0x07

			for {
				if !vertical {
					if i >= sp {
						break
					}

					line_to(c, s[i], 0)
					i += 1
				}

				vertical = false

				if i >= sp {
					break
				}

				line_to(c, 0, s[i])
				i += 1
			}

		case 0x1F, 0x1E:
			if sp < 4 {
				return {}, false
			}

			horizontal := b0 == 0x1F

			for {
				if !horizontal {
					if i + 3 >= sp {
						break
					}

					curve_to(
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

				curve_to(
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
				return {}, false
			}

			for ; i + 5 < sp; i += 6 {
				curve_to(c, s[i], s[i+1], s[i+2], s[i+3], s[i+4], s[i+5])
			}

		case 0x18:
			if sp < 8 {
				return {}, false
			}

			for ; i + 5 < sp - 2; i += 6 {
				curve_to(c, s[i], s[i+1], s[i+2], s[i+3], s[i+4], s[i+5])
			}

			if i + 1 >= sp {
				return {}, false
			}

			line_to(c, s[i], s[i+1])

		case 0x19:
			if sp < 8 {
				return {}, false
			}

			for ; i + 1 < sp - 6; i += 2 {
				line_to(c, s[i], s[i+1])
			}

			if i + 5 >= sp {
				return {}, false
			}

			curve_to(c, s[i], s[i+1], s[i+2], s[i+3], s[i+4], s[i+5])

		case 0x1A, 0x1B:
			if sp < 4 {
				return {}, false
			}

			f = 0.0

			if sp & 1 != 0 {
				f = s[i]
				i += 1
			}

			for ; i + 3 < sp; i += 4 {
				if b0 == 0x1B {
					curve_to(c, s[i], f, s[i+1], s[i+2], s[i+3], 0.0)
				} else {
					curve_to(c, f, s[i], s[i+1], s[i+2], 0.0, s[i+3])
				}

				f = 0.0
			}

		case 0x0A:
			if !has_subrs {
				fdselect := cff.font_dict_select

				if len(fdselect) != 0 {
					subrs = nil
					fdselector := -1
					format := cff_uint(fdselect, 0, 1)

					if format == 0 {
						fdselector = cff_uint(fdselect, 1 + glyph_index, 1)
					} else if format == 3 {
						nranges := cff_uint(fdselect, 1, 2)
						start := cff_uint(fdselect, 3, 2)

						for r in 0..<nranges {
							v := cff_uint(fdselect, 5 + r*3, 1)
							end := cff_uint(fdselect, 6 + r*3, 2)

							if glyph_index >= start && glyph_index < end {
								fdselector = v
								break
							}

							start = end
						}
					}

					if fdselector != -1 {
						fontdict := cff_index_item(cff.font_dicts, fdselector)
						subrs = cff_local_subroutines(cff.table, fontdict)
					}
				}

				has_subrs = true
			}

			fallthrough

		case 0x1D:
			if sp < 1 || subr_stack_height >= 10 {
				return {}, false
			}

			sp -= 1
			subr_index := b0 == 0x0A ? subrs : cff.global_subroutines
			count := cff_uint(subr_index, 0, 2)
			bias := 107

			if count >= 33900 {
				bias = 32768
			} else if count >= 1240 {
				bias = 1131
			}

			subr := int(s[sp]) + bias

			if subr < 0 || subr >= count {
				return {}, false
			}

			subr_stack_code[subr_stack_height] = code
			subr_stack_cursor[subr_stack_height] = cursor
			subr_stack_height += 1
			code = cff_index_item(subr_index, subr)
			cursor = 0

			if len(code) == 0 {
				return {}, false
			}

			clear_stack = false

		case 0x0B:
			if subr_stack_height <= 0 {
				return {}, false
			}

			subr_stack_height -= 1
			code = subr_stack_code[subr_stack_height]
			cursor = subr_stack_cursor[subr_stack_height]
			clear_stack = false

		case 0x0E:
			close_shape(c)
			return {c.min_x, c.min_y, c.max_x, c.max_y}, true

		case 0x0C:
			dx1, dx2, dx3, dx4, dx5, dx6, dy1, dy2, dy3, dy4, dy5, dy6: f32
			b1 := cff_read_uint(code, &cursor, 1)

			switch b1 {
			case 0x22:
				if sp < 7 {
					return {}, false
				}

				dx1 = s[0]
				dx2 = s[1]
				dy2 = s[2]
				dx3 = s[3]
				dx4 = s[4]
				dx5 = s[5]
				dx6 = s[6]
				curve_to(c, dx1, 0, dx2, dy2, dx3, 0)
				curve_to(c, dx4, 0, dx5, -dy2, dx6, 0)

			case 0x23:
				if sp < 13 {
					return {}, false
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
				curve_to(c, dx1, dy1, dx2, dy2, dx3, dy3)
				curve_to(c, dx4, dy4, dx5, dy5, dx6, dy6)

			case 0x24:
				if sp < 9 {
					return {}, false
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
				curve_to(c, dx1, dy1, dx2, dy2, dx3, 0)
				curve_to(c, dx4, 0, dx5, dy5, dx6, -(dy1+dy2+dy5))

			case 0x25:
				if sp < 11 {
					return {}, false
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

				curve_to(c, dx1, dy1, dx2, dy2, dx3, dy3)
				curve_to(c, dx4, dy4, dx5, dy5, dx6, dy6)

			case:
				return {}, false
			}

		case:
			if b0 != 255 && b0 != 28 && b0 < 32 {
				return {}, false
			}

			if b0 == 255 {
				f = f32(i32(u32(cff_read_uint(code, &cursor, 4)))) / 0x10000
			} else {
				cursor -= 1
				f = f32(i16(cff_int(code, &cursor)))
			}

			if sp >= 48 {
				return {}, false
			}

			s[sp] = f
			sp += 1
			clear_stack = false
		}

		if clear_stack {
			sp = 0
		}
	}

	return {}, false
}
