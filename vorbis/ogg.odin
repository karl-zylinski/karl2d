#+private package
package karl2d_vorbis

import "base:intrinsics"

PAGE_FLAG_CONTINUED_PACKET :: 1
PAGE_FLAG_FIRST_PAGE :: 2
PAGE_FLAG_LAST_PAGE :: 4

read_u32 :: proc(data: []u8, offset: int) -> u32 {
	return u32(intrinsics.unaligned_load((^u32le)(raw_data(data[offset:offset + 4]))))
}

read_granule :: proc(page: []u8) -> int {
	return int(intrinsics.unaligned_load((^i64le)(raw_data(page[6:14]))))
}

find_page :: proc(data: []u8, from: int) -> (offset: int, size: int, found: bool) {
	crc_table: [256]u32

	for &entry, i in crc_table {
		entry = u32(i) << 24

		for _ in 0..<8 {
			entry = (entry << 1) ~ (entry >= 1 << 31 ? 0x04c11db7 : 0)
		}
	}

	i := from

	search: for ; i + 27 <= len(data); i += 1 {
		if data[i] != 'O' || data[i + 1] != 'g' || data[i + 2] != 'g' || data[i + 3] != 'S' {
			continue
		}

		if data[i + 4] != 0 {
			continue
		}

		segment_count := int(data[i + 26])

		if i + 27 + segment_count > len(data) {
			return i, 0, false
		}

		size = 27 + segment_count

		for length in data[i + 27:i + 27 + segment_count] {
			size += int(length)
		}

		if i + size > len(data) {
			return i, 0, false
		}

		crc: u32

		for value, j in data[i:i + size] {
			byte := j >= 22 && j < 26 ? 0 : value
			crc = (crc << 8) ~ crc_table[byte ~ u8(crc >> 24)]
		}

		if crc == read_u32(data, i + 22) {
			return i, size, true
		}
	}

	return i, 0, false
}

page_frames :: proc(
	d: ^Decoder,
	page: []u8,
	target_frame: int,
) -> (
	decoder_frame: int,
	output_frame: int,
	packets_to_skip: int,
	ok: bool,
) {
	granule := read_granule(page)

	if granule == -1 || page[5] & (PAGE_FLAG_FIRST_PAGE | PAGE_FLAG_LAST_PAGE) != 0 {
		return
	}

	segment_count := int(page[26])
	table := page[27:27 + segment_count]
	p := 27 + segment_count
	seg := 0

	if page[5] & PAGE_FLAG_CONTINUED_PACKET != 0 {
		ended := false

		for seg < segment_count && !ended {
			p += int(table[seg])
			ended = table[seg] < 255
			seg += 1
		}

		if !ended {
			return
		}
	}

	advances: [255]i32
	advance := 0
	last_right_start := 0
	last_n2 := 0
	packets := 0

	for seg < segment_count {
		start := p
		complete := false

		for seg < segment_count && !complete {
			p += int(table[seg])
			complete = table[seg] < 255
			seg += 1
		}

		if !complete {
			break
		}

		if p == start {
			return
		}

		header := u32(page[start])

		if p - start > 1 {
			header |= u32(page[start + 1]) << 8
		}

		mode, left_start, right_start, _ := packet_window(d, header) or_return

		advances[packets] = i32(right_start - left_start)
		advance += right_start - left_start
		last_right_start = right_start
		last_n2 = d.blocksize[mode.blockflag] >> 1
		packets += 1
	}

	if packets == 0 {
		return
	}

	decoder_frame = granule - last_n2 + last_right_start - advance

	if decoder_frame < 0 {
		return
	}

	output_frame = decoder_frame + int(advances[0])

	for packets_to_skip + 1 < packets {
		next_output_frame := output_frame + int(advances[packets_to_skip + 1])

		if next_output_frame > target_frame {
			break
		}

		decoder_frame = output_frame
		output_frame = next_output_frame
		packets_to_skip += 1
	}

	return decoder_frame, output_frame, packets_to_skip, true
}

read_packet :: proc(d: ^Decoder, data: []u8) -> (bytes_used: int, err: Error) {
	clear(&d.packet)
	p := 0
	seg := d.next_segment
	table := d.segments[:d.segment_count]
	flags := d.page_flags
	end_segment_with_known_frame := d.end_segment_with_known_frame
	known_frame := d.known_frame
	new_page := false
	started := false

	for {
		if seg == -1 {
			if p + 27 > len(data) {
				return 0, .Need_More_Data
			}

			if data[p] != 'O' || data[p + 1] != 'g' || data[p + 2] != 'g' || data[p + 3] != 'S' {
				return 0, .Invalid_Stream
			}

			if data[p + 4] != 0 {
				return 0, .Invalid_Stream
			}

			segment_count := int(data[p + 26])

			if p + 27 + segment_count > len(data) {
				return 0, .Need_More_Data
			}

			flags = data[p + 5]
			table = data[p + 27:p + 27 + segment_count]
			granule := read_granule(data[p:])
			end_segment_with_known_frame = -2

			if granule != -1 {
				for i := segment_count - 1; i >= 0; i -= 1 {
					if table[i] < 255 {
						end_segment_with_known_frame = i
						known_frame = granule
						break
					}
				}
			}

			p += 27 + segment_count
			seg = 0
			new_page = true

			if started && flags & PAGE_FLAG_CONTINUED_PACKET == 0 {
				return 0, .Invalid_Stream
			}

			if !started && flags & PAGE_FLAG_CONTINUED_PACKET != 0 {
				for seg < segment_count {
					length := int(table[seg])
					p += length
					seg += 1

					if length < 255 {
						break
					}
				}

				if p > len(data) {
					return 0, .Need_More_Data
				}
			}

			if seg >= segment_count {
				seg = -1
				continue
			}
		}

		started = true
		length := int(table[seg])

		if p + length > len(data) {
			return 0, .Need_More_Data
		}

		append(&d.packet, ..data[p:p + length])
		p += length
		d.packet_ends_known_frame = seg == end_segment_with_known_frame
		seg += 1

		if seg == len(table) {
			seg = -1
		}

		if length < 255 {
			break
		}
	}

	if new_page {
		copy(d.segments[:], table)
		d.segment_count = len(table)
	}

	d.next_segment = seg
	d.page_flags = flags
	d.end_segment_with_known_frame = end_segment_with_known_frame
	d.known_frame = known_frame

	for _ in 0..<PACKET_PADDING {
		append(&d.packet, 0)
	}

	return p, .None
}
