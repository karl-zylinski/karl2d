// This is based on stb_vorbis.c by Sean Barrett. See the LICENSE file in this folder.
package karl2d_vorbis

import "core:mem"

MAX_CHANNELS :: 2
MAX_OGG_PAGE_SIZE :: 65307

Error :: enum {
	None,
	Need_More_Data,
	Invalid_Stream,
	Unsupported_Stream,
}

Decoder :: struct {
	channels: int,
	sample_rate: int,
	current_frame: int,
	current_frame_valid: bool,

	arena: mem.Dynamic_Arena,
	blocksize: [2]int,
	codebooks: []Codebook,
	floors: []Floor,
	residues: []Residue,
	mappings: []Mapping,
	modes: [64]Mode,
	mode_count: int,
	mode_bits: int,

	window: [2][]f32,
	imdct_scratch: []f32,
	imdct_tables: [2]Imdct_Tables,
	interleaved: []f32,

	channel_buffers: [2][MAX_CHANNELS][]f32,
	buffer_index: int,
	previous_start: int,
	previous_length: int,
	final_y: [MAX_CHANNELS][MAX_FLOOR_VALUES]i16,
	part_classes: [MAX_CHANNELS][]i32,

	first_decode: bool,
	discard_frames_deferred: int,

	needs_sync: bool,
	seek_target: int,
	segments: [255]u8,
	segment_count: int,
	next_segment: int,
	page_flags: u8,
	end_segment_with_known_frame: int,
	known_frame: int,
	packet_ends_known_frame: bool,
	packet: [dynamic]u8,
}

make_decoder :: proc(
	data: []u8,
	allocator := context.allocator,
	temp_allocator := context.temp_allocator,
) -> (
	decoder: Decoder,
	bytes_used: int,
	err: Error,
) {
	ID_PAGE_SIZE :: 28 + 30

	if len(data) < ID_PAGE_SIZE {
		return {}, 0, .Need_More_Data
	}

	if string(data[:4]) != "OggS" || data[4] != 0 || data[5] != PAGE_FLAG_FIRST_PAGE {
		return {}, 0, .Invalid_Stream
	}

	packet_start := 27 + int(data[26])

	if len(data) < packet_start + 7 {
		return {}, 0, .Need_More_Data
	}

	if data[packet_start] != 1 || string(data[packet_start + 1:packet_start + 7]) != "vorbis" {
		return {}, 0, .Unsupported_Stream
	}

	if data[26] != 1 || data[27] != 30 || data[28] != 1 || string(data[29:35]) != "vorbis" {
		return {}, 0, .Invalid_Stream
	}

	id := data[28:ID_PAGE_SIZE]

	if read_u32(id, 7) != 0 || id[29] & 1 == 0 {
		return {}, 0, .Invalid_Stream
	}

	d: Decoder
	d.channels = int(id[11])
	d.sample_rate = int(read_u32(id, 12))

	if d.channels == 0 || d.sample_rate == 0 {
		return {}, 0, .Invalid_Stream
	}

	if d.channels > MAX_CHANNELS {
		return {}, 0, .Unsupported_Stream
	}

	log0 := uint(id[28] & 15)
	log1 := uint(id[28] >> 4)

	if log0 < 6 || log0 > 13 || log1 < 6 || log1 > 13 || log0 > log1 {
		return {}, 0, .Invalid_Stream
	}

	d.blocksize = { 1 << log0, 1 << log1 }
	d.next_segment = -1
	d.packet = make([dynamic]u8, allocator)
	bytes_used = ID_PAGE_SIZE

	for packet_type in ([2]u8 { 3, 5 }) {
		used, packet_err := read_packet(&d, data[bytes_used:])

		if packet_err != .None {
			delete(d.packet)
			return {}, 0, packet_err
		}

		bytes_used += used

		if len(d.packet) < 7 + PACKET_PADDING || d.packet[0] != packet_type {
			delete(d.packet)
			return {}, 0, .Invalid_Stream
		}
	}

	mem.dynamic_arena_init(&d.arena, allocator, allocator)
	setup_err := parse_setup(&d, mem.dynamic_arena_allocator(&d.arena), temp_allocator)

	if setup_err != .None {
		delete_decoder(&d)
		return {}, 0, setup_err
	}

	d.first_decode = true
	return d, bytes_used, .None
}

delete_decoder :: proc(d: ^Decoder) {
	delete(d.packet)
	mem.dynamic_arena_destroy(&d.arena)
	d^ = {}
}

decode_frame :: proc(
	d: ^Decoder,
	data: []u8,
) -> (
	bytes_used: int,
	output: [MAX_CHANNELS][]f32,
	err: Error,
) {
	if d.needs_sync {
		offset, size, found := find_page(data, 0)

		if !found {
			return offset, {}, .Need_More_Data
		}

		page := data[offset:offset + size]
		segment_count := int(page[26])
		copy(d.segments[:], page[27:27 + segment_count])
		d.segment_count = segment_count
		d.page_flags = page[5]
		d.end_segment_with_known_frame = -2
		granule := read_granule(page)
		bytes_used = offset + 27 + segment_count
		d.next_segment = 0

		if granule != -1 {
			for i := segment_count - 1; i >= 0; i -= 1 {
				if d.segments[i] < 255 {
					d.end_segment_with_known_frame = i
					d.known_frame = granule
					break
				}
			}
		}

		if d.page_flags & PAGE_FLAG_CONTINUED_PACKET != 0 {
			for d.next_segment < segment_count {
				length := int(d.segments[d.next_segment])
				bytes_used += length
				d.next_segment += 1

				if length < 255 {
					break
				}
			}
		}

		if d.page_flags & PAGE_FLAG_FIRST_PAGE != 0 {
			d.first_decode = true
		} else if frame, _, skip, frame_ok := page_frames(d, page, d.seek_target); frame_ok {
			d.current_frame = frame
			d.current_frame_valid = true

			for _ in 0..<skip {
				for {
					length := int(d.segments[d.next_segment])
					bytes_used += length
					d.next_segment += 1

					if length < 255 {
						break
					}
				}
			}
		}

		if d.next_segment >= segment_count {
			d.next_segment = -1
		}

		d.seek_target = min(int)
		d.needs_sync = false
	}

	used, packet_err := read_packet(d, data[bytes_used:])

	if packet_err != .None {
		return bytes_used, {}, packet_err
	}

	bytes_used += used

	if len(d.packet) == PACKET_PADDING {
		return bytes_used, {}, .None
	}

	length, left, right, packet_ok := decode_packet(d)

	if !packet_ok {
		return bytes_used, {}, .None
	}

	frames := finish_frame(d, length, left, right)

	for i in 0..<d.channels {
		output[i] = d.channel_buffers[d.buffer_index][i][left:left + frames]
	}

	return bytes_used, output, .None
}

flush :: proc(d: ^Decoder) {
	d.previous_length = 0
	d.needs_sync = true
	d.next_segment = -1
	d.first_decode = false
	d.discard_frames_deferred = 0
	d.current_frame_valid = false
	d.seek_target = min(int)
}

seek :: proc(
	d: ^Decoder,
	data: []u8,
	target_frame: int,
) -> (
	offset: int,
	frame: int,
) {
	SMALL_RANGE :: 2 * MAX_OGG_PAGE_SIZE

	next_page_with_frame :: proc(
		d: ^Decoder,
		data: []u8,
		from: int,
	) -> (
		offset: int,
		size: int,
		frame: int,
		ok: bool,
	) {
		offset = from

		for {
			found: bool
			offset, size, found = find_page(data, offset)

			if !found {
				return
			}

			frame_ok: bool
			_, frame, _, frame_ok = page_frames(d, data[offset:offset + size], min(int))

			if frame_ok {
				return offset, size, frame, true
			}

			offset += size
		}
	}

	flush(d)
	lo := 0
	hi := len(data)
	size := 0

	for hi - lo > SMALL_RANGE {
		mid := lo + (hi - lo) / 2
		page_offset, page_size, page_frame, ok := next_page_with_frame(d, data, mid)

		if !ok || page_offset >= hi || page_frame > target_frame {
			hi = mid
			continue
		}

		lo = page_offset
		offset = page_offset
		size = page_size
		frame = page_frame
	}

	scan := lo

	for scan < hi {
		page_offset, page_size, page_frame, ok := next_page_with_frame(d, data, scan)

		if !ok || page_frame > target_frame {
			break
		}

		offset = page_offset
		size = page_size
		frame = page_frame
		scan = page_offset + page_size
	}

	if size != 0 {
		_, frame, _, _ = page_frames(d, data[offset:offset + size], target_frame)
		d.seek_target = target_frame
	}

	return
}

total_frames :: proc(data: []u8) -> int {
	MIN_OGG_PAGE_SIZE :: 27

	for idx := len(data) - MIN_OGG_PAGE_SIZE; idx >= 0; idx -= 1 {
		if string(data[idx:idx + 4]) != "OggS" {
			continue
		}

		granule := read_granule(data[idx:])

		if granule > 0 {
			return granule
		}
	}

	return 0
}
