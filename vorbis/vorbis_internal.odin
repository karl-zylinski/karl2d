// This is based on stb_vorbis.c by Sean Barrett. See the LICENSE file in this folder.
#+private package
package karl2d_vorbis

import "base:intrinsics"
import "core:math"
import "core:math/bits"
import "core:mem"
import "core:simd"
import "core:slice"
import "base:runtime"

Decoder_Internal :: struct {
	setup_arena: mem.Dynamic_Arena,

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
	stream_ended: bool,
	restart_offset: int,
	seek_target: int,
	segments: [MAX_PAGE_SEGMENTS]u8,
	segment_count: int,
	next_segment: int,
	page_flags: u8,
	end_segment_with_known_frame: int,
	known_frame: int,
	packet_ends_known_frame: bool,
	packet: [dynamic]u8,
}

MAX_FLOOR_VALUES :: 31 * 8 + 2
RESIDUE_PASSES :: 8
MAX_PAGE_SEGMENTS :: 255

Codebook :: struct {
	dimensions: int,
	entries: int,
	fast_mask: u64,
	max_length: int,
	fast: []u32,
	long_codewords: []u32,
	long_values: []u32,
	multiplicands: []f32,
}

Floor :: struct {
	partitions: int,
	partition_class_list: [32]u8,
	class_dimensions: [16]u8,
	class_subclasses: [16]u8,
	class_masterbooks: [16]u8,
	subclass_books: [16][8]i16,
	x_list: [MAX_FLOOR_VALUES]u16,
	sorted_order: [MAX_FLOOR_VALUES]u8,
	neighbors: [MAX_FLOOR_VALUES][2]u8,
	predict_dx: [MAX_FLOOR_VALUES]u16,
	predict_inverse: [MAX_FLOOR_VALUES]u64,
	multiplier: int,
	range_bits: int,
	values: int,
}

Residue :: struct {
	type: int,
	begin: int,
	end: int,
	part_size: int,
	classifications: int,
	classbook: int,
	classdata: []u8,
	residue_books: [][RESIDUE_PASSES]i16,
	partition_bits: [][RESIDUE_PASSES]i32,
	stages: int,
}

Mapping :: struct {
	coupling_steps: int,
	magnitude: [MAX_CHANNELS]u8,
	angle: [MAX_CHANNELS]u8,
	mux: [MAX_CHANNELS]u8,
	submaps: int,
	submap_floor: [16]u8,
	submap_residue: [16]u8,
}

Mode :: struct {
	blockflag: int,
	mapping: int,
}

Imdct_Tables :: struct {
	pre: []f32,
	post: []f32,
	positions: []u16,
	fft_twiddles: []f32,
}

Page_Start :: struct {
	decoder_frame: int,
	output_frame: int,
	packets_to_skip: int,
}

Bit_Reader :: struct {
	data: [^]u8,
	last: int,
	pos: int,
	acc: u64,
	valid: int,
	total_bits: int,
}

_create_decoder :: proc(
	data: []u8,
	allocator: runtime.Allocator,
	temp_allocator: runtime.Allocator,
) -> (
	_decoder: Decoder,
	_bytes_used: int,
	_err: Error,
) {
	FAST_HUFFMAN_BITS :: 10

	float32_unpack :: proc(x: u32) -> f32 {
		mantissa := x & 0x1fffff
		sign := x & 0x80000000
		exp := (x & 0x7fe00000) >> 21
		value := sign != 0 ? -f64(mantissa) : f64(mantissa)
		return f32(math.ldexp(f64(f32(value)), int(exp) - 788))
	}

	ID_HEADER :: 1
	COMMENT_HEADER :: 3
	SETUP_HEADER :: 5
	HEADER_PREFIX_SIZE :: 7

	ID_OFFSET_VERSION :: 7
	ID_OFFSET_CHANNELS :: 11
	ID_OFFSET_SAMPLE_RATE :: 12
	ID_OFFSET_BLOCKSIZES :: 28
	ID_OFFSET_FRAMING :: 29
	ID_PACKET_SIZE :: 30
	ID_PAGE_SIZE :: PAGE_HEADER_SIZE + 1 + ID_PACKET_SIZE

	MIN_BLOCKSIZE_LOG2 :: 6
	MAX_BLOCKSIZE_LOG2 :: 13

	if len(data) < ID_PAGE_SIZE {
		return {}, 0, .Need_More_Data
	}

	if string(data[:4]) != "OggS" || data[PAGE_OFFSET_VERSION] != 0 {
		return {}, 0, .Invalid_Stream
	}

	if data[PAGE_OFFSET_FLAGS] != PAGE_FLAG_FIRST_PAGE {
		return {}, 0, .Invalid_Stream
	}

	packet_start := PAGE_HEADER_SIZE + int(data[PAGE_OFFSET_SEGMENT_COUNT])

	if len(data) < packet_start + HEADER_PREFIX_SIZE {
		return {}, 0, .Need_More_Data
	}

	prefix := data[packet_start:][:HEADER_PREFIX_SIZE]

	if prefix[0] != ID_HEADER || string(prefix[1:]) != "vorbis" {
		return {}, 0, .Unsupported_Stream
	}

	if data[PAGE_OFFSET_SEGMENT_COUNT] != 1 || data[PAGE_HEADER_SIZE] != ID_PACKET_SIZE {
		return {}, 0, .Invalid_Stream
	}

	id := data[packet_start:ID_PAGE_SIZE]

	if read_u32(id, ID_OFFSET_VERSION) != 0 || id[ID_OFFSET_FRAMING] & 1 == 0 {
		return {}, 0, .Invalid_Stream
	}

	d: Decoder
	d.channels = int(id[ID_OFFSET_CHANNELS])
	d.sample_rate = int(read_u32(id, ID_OFFSET_SAMPLE_RATE))

	if d.channels == 0 || d.sample_rate == 0 {
		return {}, 0, .Invalid_Stream
	}

	if d.channels > MAX_CHANNELS {
		return {}, 0, .Unsupported_Stream
	}

	short_log2 := uint(id[ID_OFFSET_BLOCKSIZES] & 15)
	long_log2 := uint(id[ID_OFFSET_BLOCKSIZES] >> 4)

	if short_log2 < MIN_BLOCKSIZE_LOG2 || long_log2 > MAX_BLOCKSIZE_LOG2 || short_log2 > long_log2 {
		return {}, 0, .Invalid_Stream
	}

	d.blocksize = { 1 << short_log2, 1 << long_log2 }
	d.next_segment = NO_SEGMENT
	d.packet = make([dynamic]u8, allocator)
	mem.dynamic_arena_init(&d.setup_arena, allocator, allocator)
	setup_allocator := mem.dynamic_arena_allocator(&d.setup_arena)

	defer if _err != .None {
		_destroy_decoder(&d)
	}

	bytes_used := ID_PAGE_SIZE

	packet_bytes, packet_err := read_packet(&d, data[bytes_used:])

	if packet_err != .None {
		return {}, 0, packet_err
	}

	bytes_used += packet_bytes

	if len(d.packet) < HEADER_PREFIX_SIZE + PACKET_PADDING || d.packet[0] != COMMENT_HEADER {
		return {}, 0, .Invalid_Stream
	}

	packet_bytes, packet_err = read_packet(&d, data[bytes_used:])

	if packet_err != .None {
		return {}, 0, packet_err
	}

	bytes_used += packet_bytes

	if len(d.packet) < HEADER_PREFIX_SIZE + PACKET_PADDING || d.packet[0] != SETUP_HEADER {
		return {}, 0, .Invalid_Stream
	}

	MAX_CODEBOOK_FLOATS :: 1 << 22

	reader: Bit_Reader
	bits_init(&reader, d.packet[:])

	if get_bits(&reader, 8) != SETUP_HEADER {
		return {}, 0, .Invalid_Stream
	}

	for ch in "vorbis" {
		if get_bits(&reader, 8) != u32(ch) {
			return {}, 0, .Invalid_Stream
		}
	}

	codebook_count := int(get_bits(&reader, 8)) + 1
	d.codebooks = make([]Codebook, codebook_count, setup_allocator)

	for &book in d.codebooks {
		CODEBOOK_SYNC :: 0x564342
		NO_CODE :: 255
		MAX_CODEWORD_LENGTH :: 31
		LOOKUP_NONE :: 0
		LOOKUP_LATTICE :: 1
		LOOKUP_EXPLICIT :: 2

		Long_Code :: struct {
			codeword: u32,
			value: u32,
		}

		if get_bits(&reader, 24) != CODEBOOK_SYNC {
			return {}, 0, .Invalid_Stream
		}

		book.dimensions = int(get_bits(&reader, 16))
		book.entries = int(get_bits(&reader, 24))
		ordered := get_bits(&reader, 1) != 0
		sparse := ordered ? false : get_bits(&reader, 1) != 0

		if book.dimensions == 0 && book.entries != 0 {
			return {}, 0, .Invalid_Stream
		}

		if bits_eop(&reader) || book.entries > reader.total_bits {
			return {}, 0, .Invalid_Stream
		}

		lengths := make([]u8, book.entries, temp_allocator)

		if ordered {
			current_entry := 0
			current_length := int(get_bits(&reader, 5)) + 1

			for current_entry < book.entries {
				limit := book.entries - current_entry
				count := int(get_bits(&reader, ilog(limit)))
				end := current_entry + count

				if current_length > MAX_CODEWORD_LENGTH || end > book.entries || bits_eop(&reader) {
					return {}, 0, .Invalid_Stream
				}

				slice.fill(lengths[current_entry:end], u8(current_length))
				current_entry = end
				current_length += 1
			}
		} else {
			for &length in lengths {
				length = NO_CODE

				if !sparse || get_bits(&reader, 1) != 0 {
					length = u8(get_bits(&reader, 5)) + 1

					if length > MAX_CODEWORD_LENGTH {
						return {}, 0, .Invalid_Stream
					}
				}
			}
		}

		codewords := make([]u32, book.entries, temp_allocator)
		available: [MAX_CODEWORD_LENGTH + 1]u32
		first := 0

		for first < book.entries && lengths[first] == NO_CODE {
			first += 1
		}

		if first < book.entries {
			for i in 1..=int(lengths[first]) {
				available[i] = u32(1) << u32(32 - i)
			}
		}

		for i in first + 1..<book.entries {
			level := int(lengths[i])

			if level == NO_CODE {
				continue
			}

			for level > 0 && available[level] == 0 {
				level -= 1
			}

			if level == 0 {
				return {}, 0, .Invalid_Stream
			}

			code := available[level]
			available[level] = 0
			codewords[i] = bits.reverse_bits(code)

			for y := int(lengths[i]); y > level; y -= 1 {
				available[y] = code + (u32(1) << u32(32 - y))
			}
		}

		max_length := 0
		long_count := 0

		for length in lengths {
			if length != NO_CODE {
				max_length = max(max_length, int(length))

				if length > FAST_HUFFMAN_BITS {
					long_count += 1
				}
			}
		}

		book.max_length = max_length
		fast_bits := min(max_length, FAST_HUFFMAN_BITS)
		book.fast = make([]u32, 1 << uint(fast_bits), setup_allocator)
		book.fast_mask = u64(len(book.fast) - 1)
		long_codes := make([]Long_Code, long_count, temp_allocator)
		long_count = 0

		for length, i in lengths {
			if length == NO_CODE {
				continue
			}

			value := u32(i) << CODE_LENGTH_BITS | u32(length)

			if int(length) <= fast_bits {
				for slot := codewords[i]; slot < u32(len(book.fast)); slot += u32(1) << length {
					book.fast[slot] = value
				}
			} else {
				long_codes[long_count] = { bits.reverse_bits(codewords[i]), value }
				long_count += 1
			}
		}

		slice.sort_by(long_codes, proc(a: Long_Code, b: Long_Code) -> bool {
			return a.codeword < b.codeword
		})

		book.long_codewords = make([]u32, long_count, setup_allocator)
		book.long_values = make([]u32, long_count, setup_allocator)

		for long_code, i in long_codes {
			book.long_codewords[i] = long_code.codeword
			book.long_values[i] = long_code.value
		}

		lookup_type := get_bits(&reader, 4)

		if lookup_type > LOOKUP_EXPLICIT {
			return {}, 0, .Invalid_Stream
		}

		if lookup_type != LOOKUP_NONE {
			minimum_value := float32_unpack(get_bits(&reader, 32))
			delta_value := float32_unpack(get_bits(&reader, 32))
			value_bits := int(get_bits(&reader, 4)) + 1
			sequence_p := get_bits(&reader, 1) != 0

			book_floats := i64(book.entries) * i64(book.dimensions)

			if book.dimensions == 0 || book_floats > MAX_CODEBOOK_FLOATS {
				return {}, 0, .Invalid_Stream
			}

			lookup_values := book.entries * book.dimensions

			if lookup_type == LOOKUP_LATTICE {
				lookup_values = 0

				for {
					power := i64(1)

					for _ in 0..<book.dimensions {
						power *= i64(lookup_values + 1)

						if power > i64(book.entries) {
							break
						}
					}

					if power > i64(book.entries) {
						break
					}

					lookup_values += 1
				}
			}

			if lookup_values == 0 {
				return {}, 0, .Invalid_Stream
			}

			if bits_eop(&reader) || i64(lookup_values) * i64(value_bits) > i64(reader.total_bits) {
				return {}, 0, .Invalid_Stream
			}

			mults := make([]u16, lookup_values, temp_allocator)

			for &m in mults {
				m = u16(get_bits(&reader, value_bits))
			}

			book.multiplicands = make([]f32, book.entries * book.dimensions, setup_allocator)

			for j in 0..<book.entries {
				if lengths[j] == NO_CODE {
					continue
				}

				div := i64(1)
				last: f32

				for k in 0..<book.dimensions {
					index := j * book.dimensions + k

					if lookup_type == LOOKUP_LATTICE {
						index = int((i64(j) / div) % i64(lookup_values))
					}

					value := f32(mults[index]) * delta_value + minimum_value + last
					book.multiplicands[j * book.dimensions + k] = value

					if sequence_p {
						last = value
					}

					if lookup_type == LOOKUP_LATTICE && k + 1 < book.dimensions {
						if div > i64(max(u32)) / i64(lookup_values) {
							return {}, 0, .Invalid_Stream
						}

						div *= i64(lookup_values)
					}
				}
			}
		}
	}

	time_count := int(get_bits(&reader, 6)) + 1

	for _ in 0..<time_count {
		if get_bits(&reader, 16) != 0 {
			return {}, 0, .Invalid_Stream
		}
	}

	floor_count := int(get_bits(&reader, 6)) + 1
	d.floors = make([]Floor, floor_count, setup_allocator)

	for &floor in d.floors {
		floor_type := get_bits(&reader, 16)

		if floor_type == 0 {
			return {}, 0, .Unsupported_Stream
		}

		if floor_type != 1 {
			return {}, 0, .Invalid_Stream
		}

		max_class := -1
		floor.partitions = int(get_bits(&reader, 5))

		for j in 0..<floor.partitions {
			floor.partition_class_list[j] = u8(get_bits(&reader, 4))
			max_class = max(max_class, int(floor.partition_class_list[j]))
		}

		for j in 0..=max_class {
			floor.class_dimensions[j] = u8(get_bits(&reader, 3)) + 1
			floor.class_subclasses[j] = u8(get_bits(&reader, 2))

			if floor.class_subclasses[j] != 0 {
				floor.class_masterbooks[j] = u8(get_bits(&reader, 8))

				if int(floor.class_masterbooks[j]) >= codebook_count {
					return {}, 0, .Invalid_Stream
				}
			}

			for k in 0..<1 << floor.class_subclasses[j] {
				floor.subclass_books[j][k] = i16(get_bits(&reader, 8)) - 1

				if int(floor.subclass_books[j][k]) >= codebook_count {
					return {}, 0, .Invalid_Stream
				}
			}
		}

		floor.multiplier = int(get_bits(&reader, 2)) + 1
		floor.range_bits = int(get_bits(&reader, 4))
		floor.x_list[0] = 0
		floor.x_list[1] = u16(1) << uint(floor.range_bits)
		floor.values = 2

		for j in 0..<floor.partitions {
			class := floor.partition_class_list[j]

			for _ in 0..<floor.class_dimensions[class] {
				if floor.values >= MAX_FLOOR_VALUES {
					return {}, 0, .Invalid_Stream
				}

				floor.x_list[floor.values] = u16(get_bits(&reader, floor.range_bits))
				floor.values += 1
			}
		}

		for j in 0..<floor.values {
			floor.sorted_order[j] = u8(j)
		}

		for j in 1..<floor.values {
			point := floor.sorted_order[j]
			k := j

			for k > 0 && floor.x_list[floor.sorted_order[k - 1]] > floor.x_list[point] {
				floor.sorted_order[k] = floor.sorted_order[k - 1]
				k -= 1
			}

			floor.sorted_order[k] = point
		}

		for j in 0..<floor.values - 1 {
			if floor.x_list[floor.sorted_order[j]] == floor.x_list[floor.sorted_order[j + 1]] {
				return {}, 0, .Invalid_Stream
			}
		}

		for j in 2..<floor.values {
			low := -1
			high := max(int)

			for i in 0..<j {
				x := int(floor.x_list[i])

				if x > low && x < int(floor.x_list[j]) {
					floor.neighbors[j][0] = u8(i)
					low = x
				}

				if x < high && x > int(floor.x_list[j]) {
					floor.neighbors[j][1] = u8(i)
					high = x
				}
			}

			adx := u64(high - low)
			floor.predict_dx[j] = u16(int(floor.x_list[j]) - low)
			floor.predict_inverse[j] = (1 << PREDICT_SHIFT + adx - 1) / adx
		}
	}

	residue_count := int(get_bits(&reader, 6)) + 1
	d.residues = make([]Residue, residue_count, setup_allocator)

	for &residue in d.residues {
		residue_cascade: [64]u8
		residue.type = int(get_bits(&reader, 16))

		if residue.type > 2 {
			return {}, 0, .Invalid_Stream
		}

		residue.begin = int(get_bits(&reader, 24))
		residue.end = int(get_bits(&reader, 24))

		if residue.end < residue.begin {
			return {}, 0, .Invalid_Stream
		}

		residue.part_size = int(get_bits(&reader, 24)) + 1
		residue.classifications = int(get_bits(&reader, 6)) + 1
		residue.classbook = int(get_bits(&reader, 8))

		if residue.classbook >= codebook_count {
			return {}, 0, .Invalid_Stream
		}

		for j in 0..<residue.classifications {
			high_bits: u8
			low_bits := u8(get_bits(&reader, 3))

			if get_bits(&reader, 1) != 0 {
				high_bits = u8(get_bits(&reader, 5))
			}

			residue_cascade[j] = high_bits * 8 + low_bits
		}

		class_count := residue.classifications
		residue.residue_books = make([][RESIDUE_PASSES]i16, class_count, setup_allocator)
		residue.partition_bits = make([][RESIDUE_PASSES]i32, class_count, setup_allocator)

		for j in 0..<residue.classifications {
			for k in 0..<RESIDUE_PASSES {
				if residue_cascade[j] & (1 << uint(k)) != 0 {
					residue.residue_books[j][k] = i16(get_bits(&reader, 8))

					if int(residue.residue_books[j][k]) >= codebook_count {
						return {}, 0, .Invalid_Stream
					}

					book := &d.codebooks[residue.residue_books[j][k]]

					if len(book.multiplicands) == 0 {
						return {}, 0, .Invalid_Stream
					}

					if residue.part_size % book.dimensions != 0 {
						return {}, 0, .Unsupported_Stream
					}

					residue.stages = max(residue.stages, k + 1)
					partition_vectors := residue.part_size / book.dimensions
					residue.partition_bits[j][k] = i32(partition_vectors * book.max_length)
				} else {
					residue.residue_books[j][k] = -1
				}
			}
		}

		classbook := &d.codebooks[residue.classbook]
		classwords := classbook.dimensions

		if i64(classbook.entries) * i64(classwords) > MAX_CODEBOOK_FLOATS || classwords == 0 {
			return {}, 0, .Invalid_Stream
		}

		residue.classdata = make([]u8, classbook.entries * classwords, setup_allocator)

		for j in 0..<classbook.entries {
			remaining := j

			for k := classwords - 1; k >= 0; k -= 1 {
				residue.classdata[j * classwords + k] = u8(remaining % residue.classifications)
				remaining /= residue.classifications
			}
		}
	}

	mapping_count := int(get_bits(&reader, 6)) + 1
	d.mappings = make([]Mapping, mapping_count, setup_allocator)

	for &mapping in d.mappings {
		if get_bits(&reader, 16) != 0 {
			return {}, 0, .Invalid_Stream
		}

		mapping.submaps = 1

		if get_bits(&reader, 1) != 0 {
			mapping.submaps = int(get_bits(&reader, 4)) + 1
		}

		if get_bits(&reader, 1) != 0 {
			mapping.coupling_steps = int(get_bits(&reader, 8)) + 1

			if mapping.coupling_steps > d.channels {
				return {}, 0, .Invalid_Stream
			}

			for k in 0..<mapping.coupling_steps {
				mapping.magnitude[k] = u8(get_bits(&reader, ilog(d.channels - 1)))
				mapping.angle[k] = u8(get_bits(&reader, ilog(d.channels - 1)))

				if int(mapping.magnitude[k]) >= d.channels || int(mapping.angle[k]) >= d.channels {
					return {}, 0, .Invalid_Stream
				}

				if mapping.magnitude[k] == mapping.angle[k] {
					return {}, 0, .Invalid_Stream
				}
			}
		}

		if get_bits(&reader, 2) != 0 {
			return {}, 0, .Invalid_Stream
		}

		if mapping.submaps > 1 {
			for j in 0..<d.channels {
				mapping.mux[j] = u8(get_bits(&reader, 4))

				if int(mapping.mux[j]) >= mapping.submaps {
					return {}, 0, .Invalid_Stream
				}
			}
		}

		for j in 0..<mapping.submaps {
			get_bits(&reader, 8)
			mapping.submap_floor[j] = u8(get_bits(&reader, 8))
			mapping.submap_residue[j] = u8(get_bits(&reader, 8))

			if int(mapping.submap_floor[j]) >= floor_count {
				return {}, 0, .Invalid_Stream
			}

			if int(mapping.submap_residue[j]) >= residue_count {
				return {}, 0, .Invalid_Stream
			}
		}
	}

	d.mode_count = int(get_bits(&reader, 6)) + 1
	d.mode_bits = ilog(d.mode_count - 1)

	for &mode in d.modes[:d.mode_count] {
		mode.blockflag = int(get_bits(&reader, 1))
		window_type := get_bits(&reader, 16)
		transform_type := get_bits(&reader, 16)
		mode.mapping = int(get_bits(&reader, 8))

		if window_type != 0 || transform_type != 0 || mode.mapping >= mapping_count {
			return {}, 0, .Invalid_Stream
		}
	}

	if bits_eop(&reader) {
		return {}, 0, .Invalid_Stream
	}

	max_part_read := 0

	for residue in d.residues {
		actual_size := d.blocksize[1]
		limit_begin := min(residue.begin, actual_size)
		limit_end := min(residue.end, actual_size)
		max_part_read = max(max_part_read, (limit_end - limit_begin) / residue.part_size)
	}

	for i in 0..<d.channels {
		d.channel_buffers[0][i] = make([]f32, d.blocksize[1], setup_allocator)
		d.channel_buffers[1][i] = make([]f32, d.blocksize[1], setup_allocator)
		d.part_classes[i] = make([]i32, max_part_read + 1, setup_allocator)
	}

	d.imdct_scratch = make([]f32, d.blocksize[1] / 2, setup_allocator)
	d.interleaved = make([]f32, d.channels * d.blocksize[1] + 8, setup_allocator)

	for n, blocktype in d.blocksize {
		n2 := n >> 1
		window := make([]f32, n2, setup_allocator)

		for i in 0..<n2 {
			s := f32(math.sin((f64(i) + 0.5) / f64(n2) * 0.5 * math.PI))
			window[i] = f32(math.sin(0.5 * math.PI * f64(s * s)))
		}

		d.window[blocktype] = window
		d.imdct_tables[blocktype] = make_imdct_tables(n, setup_allocator)
	}

	d.first_decode = true

	if d.next_segment == NO_SEGMENT {
		d.restart_offset = bytes_used
	}

	return d, bytes_used, .None
}

_destroy_decoder :: proc(d: ^Decoder) {
	delete(d.packet)
	mem.dynamic_arena_destroy(&d.setup_arena)
	d^ = {}
}

_decode_chunk :: proc(
	d: ^Decoder,
	data: []u8,
) -> (
	bytes_used: int,
	samples: []f32,
	err: Error,
) {
	if d.stream_ended {
		return len(data), {}, len(data) == 0 ? .Need_More_Data : .None
	}

	if d.needs_sync {
		found: bool
		bytes_used, found = sync_to_page(d, data)

		if !found {
			return bytes_used, {}, .Need_More_Data
		}
	}

	packet_bytes, packet_err := read_packet(d, data[bytes_used:])

	if d.stream_ended {
		return len(data), {}, .None
	}

	if packet_err != .None {
		return bytes_used, {}, packet_err
	}

	bytes_used += packet_bytes

	if len(d.packet) == PACKET_PADDING {
		return bytes_used, {}, .None
	}

	length, left_start, right_start, packet_ok := decode_packet(d)

	if !packet_ok {
		return bytes_used, {}, .None
	}

	return bytes_used, finish_frame(d, length, left_start, right_start), .None
}

sync_to_page :: proc(d: ^Decoder, data: []u8) -> (bytes_used: int, found: bool) {
	offset, size, page_found := find_page(data, 0)

	if !page_found {
		return offset, false
	}

	page := data[offset:offset + size]
	segment_count := int(page[PAGE_OFFSET_SEGMENT_COUNT])
	copy(d.segments[:], page[PAGE_HEADER_SIZE:][:segment_count])
	d.segment_count = segment_count
	d.page_flags = page[PAGE_OFFSET_FLAGS]
	d.end_segment_with_known_frame = NO_KNOWN_FRAME
	granule := read_granule(page)
	bytes_used = offset + PAGE_HEADER_SIZE + segment_count
	d.next_segment = 0

	if granule != NO_GRANULE {
		for i := segment_count - 1; i >= 0; i -= 1 {
			if d.segments[i] < FULL_SEGMENT {
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

			if length < FULL_SEGMENT {
				break
			}
		}
	}

	if d.page_flags & PAGE_FLAG_FIRST_PAGE != 0 {
		d.first_decode = true
	} else if start, start_ok := page_start(d, page, d.seek_target); start_ok {
		d.current_frame = start.decoder_frame
		d.current_frame_valid = true

		for _ in 0..<start.packets_to_skip {
			for {
				length := int(d.segments[d.next_segment])
				bytes_used += length
				d.next_segment += 1

				if length < FULL_SEGMENT {
					break
				}
			}
		}
	}

	if d.next_segment >= segment_count {
		d.next_segment = NO_SEGMENT
	}

	d.seek_target = NO_SEEK_TARGET
	d.needs_sync = false
	return bytes_used, true
}

decode_packet :: proc(
	d: ^Decoder,
) -> (
	length: int,
	left: int,
	right: int,
	ok: bool,
) {
	couple :: #force_inline proc(m: F32x4, a: F32x4) -> (F32x4, F32x4) {
		zero: F32x4
		delta := simd.select(simd.lanes_gt(m, zero), a, -a)
		a_positive := simd.lanes_gt(a, zero)
		return simd.select(a_positive, m, m + delta), simd.select(a_positive, m - delta, m)
	}

	reader: Bit_Reader
	bits_init(&reader, d.packet[:])
	header := u32(d.packet[0]) | u32(d.packet[1]) << 8
	mode, left_start, right_start, right_end := packet_window(d, header) or_return

	get_bits(&reader, 1 + d.mode_bits + (mode.blockflag != 0 ? 2 : 0))
	n := d.blocksize[mode.blockflag]
	n2 := n >> 1
	d.buffer_index = 1 - d.buffer_index
	buffers := d.channel_buffers[d.buffer_index]
	mapping := &d.mappings[mode.mapping]
	zero_channel: [MAX_CHANNELS]bool
	really_zero_channel: [MAX_CHANNELS]bool

	for i in 0..<d.channels {
		floor := &d.floors[mapping.submap_floor[mapping.mux[i]]]
		zero_channel[i] = !decode_floor(d, &reader, floor, &d.final_y[i])
	}

	really_zero_channel = zero_channel
	coupling_steps := mapping.coupling_steps

	for i in 0..<mapping.coupling_steps {
		if !zero_channel[mapping.magnitude[i]] || !zero_channel[mapping.angle[i]] {
			zero_channel[mapping.magnitude[i]] = false
			zero_channel[mapping.angle[i]] = false
		}
	}

	for i in 0..<mapping.submaps {
		residue_buffers: [MAX_CHANNELS][^]f32
		ch := 0

		for j in 0..<d.channels {
			if int(mapping.mux[j]) == i {
				if !zero_channel[j] {
					residue_buffers[ch] = raw_data(buffers[j])
				}

				ch += 1
			}
		}

		residue := &d.residues[mapping.submap_residue[i]]

		if residue.type != 2 || ch != 2 {
			decode_residue(d, &reader, residue_buffers, ch, n2, residue)
			continue
		}

		if zero_channel[0] && zero_channel[1] {
			continue
		}

		decode_residue_stereo(d, &reader, residue, n2)

		interleaved := raw_data(d.interleaved)
		c0 := raw_data(buffers[0])
		c1 := raw_data(buffers[1])

		if coupling_steps != 1 {
			#no_bounds_check for j := 0; j < n2; j += 4 {
				x0 := load(interleaved, j * 2)
				x1 := load(interleaved, j * 2 + 4)
				store(c0, j, simd.shuffle(x0, x1, 0, 2, 4, 6))
				store(c1, j, simd.shuffle(x0, x1, 1, 3, 5, 7))
			}

			continue
		}

		coupling_steps = 0
		magnitude := raw_data(buffers[mapping.magnitude[0]])
		angle := raw_data(buffers[mapping.angle[0]])
		magnitude_is_first := mapping.magnitude[0] == 0

		#no_bounds_check for j := 0; j < n2; j += 4 {
			x0 := load(interleaved, j * 2)
			x1 := load(interleaved, j * 2 + 4)
			m := simd.shuffle(x0, x1, 0, 2, 4, 6)
			a := simd.shuffle(x0, x1, 1, 3, 5, 7)

			if !magnitude_is_first {
				m, a = a, m
			}

			m, a = couple(m, a)
			store(magnitude, j, m)
			store(angle, j, a)
		}
	}

	for i := coupling_steps - 1; i >= 0; i -= 1 {
		magnitude := raw_data(buffers[mapping.magnitude[i]])
		angle := raw_data(buffers[mapping.angle[i]])

		#no_bounds_check for j := 0; j < n2; j += 4 {
			m, a := couple(load(magnitude, j), load(angle, j))
			store(magnitude, j, m)
			store(angle, j, a)
		}
	}

	for i in 0..<d.channels {
		buffer := raw_data(buffers[i])

		if really_zero_channel[i] {
			intrinsics.mem_zero(buffer, n * size_of(f32))
			continue
		}

		floor := &d.floors[mapping.submap_floor[mapping.mux[i]]]
		apply_floor(floor, n2, buffer, &d.final_y[i])
		inverse_mdct(d, buffer, n, mode.blockflag)
	}

	if d.first_decode {
		d.current_frame = -n2
		d.discard_frames_deferred = n - right_end
		d.current_frame_valid = true
		d.first_decode = false
	} else if d.discard_frames_deferred != 0 {
		if d.discard_frames_deferred >= right_start - left_start {
			d.discard_frames_deferred -= right_start - left_start
			left_start = right_start
		} else {
			left_start += d.discard_frames_deferred
			d.discard_frames_deferred = 0
		}
	}

	if d.packet_ends_known_frame {
		if d.current_frame_valid && d.page_flags & PAGE_FLAG_LAST_PAGE != 0 {
			current_end := d.known_frame

			if current_end < d.current_frame + (right_end - left_start) {
				length = max(current_end - d.current_frame, 0)
				length += left_start
				length = min(length, right_end)
				d.current_frame += length
				return length, left_start, right_start, true
			}
		}

		d.current_frame = d.known_frame - (n2 - left_start)
		d.current_frame_valid = true
	}

	if d.current_frame_valid {
		d.current_frame += right_start - left_start
	}

	return right_end, left_start, right_start, true
}

decode_floor :: proc(
	d: ^Decoder,
	reader: ^Bit_Reader,
	floor: ^Floor,
	final_y: ^[MAX_FLOOR_VALUES]i16,
) -> bool {
	if get_bits(reader, 1) == 0 {
		return false
	}

	RANGE_LIST := [4]int { 256, 128, 86, 64 }
	RANGE_BITS := [4]int { 8, 7, 7, 6 }
	range := RANGE_LIST[floor.multiplier - 1]
	range_bits := RANGE_BITS[floor.multiplier - 1]
	step2_flag: [MAX_FLOOR_VALUES]bool
	offset := 2
	final_y[0] = i16(get_bits(reader, range_bits))
	final_y[1] = i16(get_bits(reader, range_bits))

	for j in 0..<floor.partitions {
		class := floor.partition_class_list[j]
		class_dims := int(floor.class_dimensions[class])
		subclass_bits := floor.class_subclasses[class]
		subclass_mask := (1 << subclass_bits) - 1
		class_value := 0

		if subclass_bits != 0 {
			class_value = codebook_decode(reader, &d.codebooks[floor.class_masterbooks[class]])
		}

		for _ in 0..<class_dims {
			book := floor.subclass_books[class][class_value & subclass_mask]
			class_value >>= subclass_bits

			if book >= 0 {
				final_y[offset] = i16(codebook_decode(reader, &d.codebooks[book]))
			} else {
				final_y[offset] = 0
			}

			offset += 1
		}
	}

	if bits_eop(reader) {
		return false
	}

	step2_flag[0] = true
	step2_flag[1] = true

	for j in 2..<floor.values {
		low := floor.neighbors[j][0]
		high := floor.neighbors[j][1]
		y0 := int(final_y[low])
		dy := int(final_y[high]) - y0
		prediction := u64(abs(dy)) * u64(floor.predict_dx[j]) * floor.predict_inverse[j]
		predicted_offset := int(prediction >> PREDICT_SHIFT)
		predicted := dy < 0 ? y0 - predicted_offset : y0 + predicted_offset
		delta := int(final_y[j])
		highroom := range - predicted
		lowroom := predicted
		room := min(highroom, lowroom) * 2

		if delta != 0 {
			step2_flag[low] = true
			step2_flag[high] = true
			step2_flag[j] = true

			if delta >= room {
				if highroom > lowroom {
					final_y[j] = i16(delta - lowroom + predicted)
				} else {
					final_y[j] = i16(predicted - delta + highroom - 1)
				}
			} else if delta & 1 != 0 {
				final_y[j] = i16(predicted - ((delta + 1) >> 1))
			} else {
				final_y[j] = i16(predicted + (delta >> 1))
			}
		} else {
			final_y[j] = i16(predicted)
		}
	}

	for j in 0..<floor.values {
		if !step2_flag[j] {
			final_y[j] = -1
		}
	}

	return true
}

finish_frame :: proc(
	d: ^Decoder,
	length: int,
	left_start: int,
	right_start: int,
) -> []f32 #no_bounds_check {
	previous_length := d.previous_length
	frames := 0

	if previous_length != 0 {
		frames = min(right_start, length) - left_start
	}

	out := raw_data(d.interleaved)
	overlap := min(previous_length, frames)
	w := raw_data(d.window[previous_length * 2 == d.blocksize[0] ? 0 : 1])
	current := d.channel_buffers[d.buffer_index]
	previous := d.channel_buffers[1 - d.buffer_index]

	if d.channels == 2 {
		left := raw_data(current[0])[left_start:]
		right := raw_data(current[1])[left_start:]
		previous_left := raw_data(previous[0])[d.previous_start:]
		previous_right := raw_data(previous[1])[d.previous_start:]

		for j := 0; j < overlap; j += 4 {
			w_forward := load(w, j)
			w_reversed := simd.swizzle(load(w, previous_length - 4 - j), 3, 2, 1, 0)
			l := load(left, j) * w_forward + load(previous_left, j) * w_reversed
			r := load(right, j) * w_forward + load(previous_right, j) * w_reversed
			store(out, j * 2, simd.shuffle(l, r, 0, 4, 1, 5))
			store(out, j * 2 + 4, simd.shuffle(l, r, 2, 6, 3, 7))
		}

		for j := overlap; j < frames; j += 4 {
			l := load(left, j)
			r := load(right, j)
			store(out, j * 2, simd.shuffle(l, r, 0, 4, 1, 5))
			store(out, j * 2 + 4, simd.shuffle(l, r, 2, 6, 3, 7))
		}
	} else {
		mono := raw_data(current[0])[left_start:]
		previous_mono := raw_data(previous[0])[d.previous_start:]

		for j := 0; j < overlap; j += 4 {
			w_reversed := simd.swizzle(load(w, previous_length - 4 - j), 3, 2, 1, 0)
			store(out, j, load(mono, j) * load(w, j) + load(previous_mono, j) * w_reversed)
		}

		intrinsics.mem_copy(&out[overlap], &mono[overlap], (frames - overlap) * size_of(f32))
	}

	d.previous_length = length - right_start
	d.previous_start = right_start

	if d.previous_length * 2 != d.blocksize[0] && d.previous_length * 2 != d.blocksize[1] {
		d.previous_length = 0
	}

	return d.interleaved[:frames * d.channels]
}

decode_residue :: proc(
	d: ^Decoder,
	source: ^Bit_Reader,
	residue_buffers: [MAX_CHANNELS][^]f32,
	ch: int,
	n: int,
	residue: ^Residue,
) #no_bounds_check {
	classbook := &d.codebooks[residue.classbook]
	classwords := classbook.dimensions
	part_size := residue.part_size
	part_read := (min(residue.end, n) - min(residue.begin, n)) / part_size
	reader := source^

	defer source^ = reader

	for j in 0..<ch {
		if residue_buffers[j] != nil {
			intrinsics.mem_zero(residue_buffers[j], n * size_of(f32))
		}
	}

	for pass in 0..<residue.stages {
		partition := 0
		class_set := 0

		for partition < part_read {
			if pass == 0 {
				for j in 0..<ch {
					if residue_buffers[j] != nil {
						classification := codebook_decode(&reader, classbook)

						if bits_eop(&reader) {
							return
						}

						d.part_classes[j][class_set] = i32(classification)
					}
				}
			}

			for word := 0; word < classwords && partition < part_read; word += 1 {
				for j in 0..<ch {
					if residue_buffers[j] == nil {
						continue
					}

					class_index := int(d.part_classes[j][class_set]) * classwords + word
					class := residue.classdata[class_index]
					book_index := residue.residue_books[class][pass]

					if book_index < 0 {
						continue
					}

					book := &d.codebooks[book_index]
					target := residue_buffers[j][residue.begin + partition * part_size:]

					if residue.type != 0 {
						worst_case_bits := int(residue.partition_bits[class][pass])

						partition_ok := decode_partition(
							&reader,
							book,
							target,
							part_size,
							worst_case_bits,
						)

						if !partition_ok {
							return
						}

						continue
					}

					dims := book.dimensions
					step := part_size / dims

					for k in 0..<step {
						entry := codebook_decode(&reader, book)

						if bits_eop(&reader) {
							return
						}

						for l in 0..<dims {
							target[k + l * step] += book.multiplicands[entry * dims + l]
						}
					}
				}

				partition += 1
			}

			class_set += 1
		}
	}
}

decode_residue_stereo :: proc(
	d: ^Decoder,
	source: ^Bit_Reader,
	residue: ^Residue,
	n: int,
) #no_bounds_check {
	out := raw_data(d.interleaved)
	intrinsics.mem_zero(out, n * 2 * size_of(f32))
	classbook := &d.codebooks[residue.classbook]
	classwords := classbook.dimensions
	part_classes := raw_data(d.part_classes[0])
	part_size := residue.part_size
	part_read := (min(residue.end, n * 2) - min(residue.begin, n * 2)) / part_size
	reader := source^

	defer source^ = reader

	for pass in 0..<residue.stages {
		partition := 0
		class_set := 0

		for partition < part_read {
			if pass == 0 {
				classification := codebook_decode(&reader, classbook)

				if bits_eop(&reader) {
					return
				}

				part_classes[class_set] = i32(classification)
			}

			class_row := residue.classdata[int(part_classes[class_set]) * classwords:]

			for word := 0; word < classwords && partition < part_read; word += 1 {
				class := class_row[word]
				book_index := residue.residue_books[class][pass]

				if book_index >= 0 {
					book := &d.codebooks[book_index]
					target := out[residue.begin + partition * part_size:]
					worst_case_bits := int(residue.partition_bits[class][pass])

					if !decode_partition(&reader, book, target, part_size, worst_case_bits) {
						return
					}
				}

				partition += 1
			}

			class_set += 1
		}
	}
}

decode_partition :: #force_no_inline proc(
	source: ^Bit_Reader,
	book: ^Codebook,
	target: [^]f32,
	part_size: int,
	worst_case_bits: int,
) -> bool #no_bounds_check {
	refill :: #force_inline proc(reader: ^Bit_Reader) #no_bounds_check {
		word := u64(intrinsics.unaligned_load((^u64le)(&reader.data[reader.pos])))
		reader.acc |= word << uint(reader.valid & 63)
		reader.pos += (63 - reader.valid) >> 3
		reader.valid |= 56
	}

	add :: #force_inline proc(target: [^]f32, values: [^]f32, $DIMS: int) #no_bounds_check {
		when DIMS == 1 {
			target[0] += values[0]
		} else when DIMS == 2 {
			target[0] += values[0]
			target[1] += values[1]
		} else when DIMS == 4 {
			store(target, 0, load(target, 0) + load(values, 0))
		} else when DIMS == 8 {
			store(target, 0, load(target, 0) + load(values, 0))
			store(target, 4, load(target, 4) + load(values, 4))
		}
	}

	decode_vectors :: #force_inline proc(
		reader: ^Bit_Reader,
		book: ^Codebook,
		target: [^]f32,
		part_size: int,
		$DIMS: int,
	) #no_bounds_check {
		MAX_LENGTH_FOR_TWO_PER_REFILL :: 28

		fast := raw_data(book.fast)
		fast_mask := book.fast_mask
		values := raw_data(book.multiplicands)
		k := 0

		if book.max_length <= MAX_LENGTH_FOR_TWO_PER_REFILL {
			for ; k + DIMS < part_size; k += DIMS * 2 {
				refill(reader)
				first := codebook_decode_refilled(reader, book, fast, fast_mask)
				second := codebook_decode_refilled(reader, book, fast, fast_mask)
				add(target[k:], values[first * DIMS:], DIMS)
				add(target[k + DIMS:], values[second * DIMS:], DIMS)
			}
		}

		for ; k < part_size; k += DIMS {
			refill(reader)
			entry := codebook_decode_refilled(reader, book, fast, fast_mask)
			add(target[k:], values[entry * DIMS:], DIMS)
		}
	}

	reader := source^

	defer source^ = reader

	dims := book.dimensions

	if reader.total_bits - (reader.pos * 8 - reader.valid) >= worst_case_bits {
		switch dims {
		case 1:
			decode_vectors(&reader, book, target, part_size, 1)
			return true

		case 2:
			decode_vectors(&reader, book, target, part_size, 2)
			return true

		case 4:
			decode_vectors(&reader, book, target, part_size, 4)
			return true

		case 8:
			decode_vectors(&reader, book, target, part_size, 8)
			return true
		}
	}

	values := raw_data(book.multiplicands)

	for k := 0; k < part_size; k += dims {
		entry := codebook_decode(&reader, book)

		if bits_eop(&reader) {
			return false
		}

		for l in 0..<dims {
			target[k + l] += values[entry * dims + l]
		}
	}

	return true
}

apply_floor :: proc(
	floor: ^Floor,
	n2: int,
	target: [^]f32,
	final_y: ^[MAX_FLOOR_VALUES]i16,
) #no_bounds_check {
	RUN_THRESHOLD :: 4

	@(static, rodata)
	INVERSE_DB_TABLE := [256]f32 {
		1.0649863e-07, 1.1341951e-07, 1.2079015e-07, 1.2863978e-07,
		1.3699951e-07, 1.4590251e-07, 1.5538408e-07, 1.6548181e-07,
		1.7623575e-07, 1.8768855e-07, 1.9988561e-07, 2.1287530e-07,
		2.2670913e-07, 2.4144197e-07, 2.5713223e-07, 2.7384213e-07,
		2.9163793e-07, 3.1059021e-07, 3.3077411e-07, 3.5226968e-07,
		3.7516214e-07, 3.9954229e-07, 4.2550680e-07, 4.5315863e-07,
		4.8260743e-07, 5.1396998e-07, 5.4737065e-07, 5.8294187e-07,
		6.2082472e-07, 6.6116941e-07, 7.0413592e-07, 7.4989464e-07,
		7.9862701e-07, 8.5052630e-07, 9.0579828e-07, 9.6466216e-07,
		1.0273513e-06, 1.0941144e-06, 1.1652161e-06, 1.2409384e-06,
		1.3215816e-06, 1.4074654e-06, 1.4989305e-06, 1.5963394e-06,
		1.7000785e-06, 1.8105592e-06, 1.9282195e-06, 2.0535261e-06,
		2.1869758e-06, 2.3290978e-06, 2.4804557e-06, 2.6416497e-06,
		2.8133190e-06, 2.9961443e-06, 3.1908506e-06, 3.3982101e-06,
		3.6190449e-06, 3.8542308e-06, 4.1047004e-06, 4.3714470e-06,
		4.6555282e-06, 4.9580707e-06, 5.2802740e-06, 5.6234160e-06,
		5.9888572e-06, 6.3780469e-06, 6.7925283e-06, 7.2339451e-06,
		7.7040476e-06, 8.2047000e-06, 8.7378876e-06, 9.3057248e-06,
		9.9104632e-06, 1.0554501e-05, 1.1240392e-05, 1.1970856e-05,
		1.2748789e-05, 1.3577278e-05, 1.4459606e-05, 1.5399272e-05,
		1.6400004e-05, 1.7465768e-05, 1.8600792e-05, 1.9809576e-05,
		2.1096914e-05, 2.2467911e-05, 2.3928002e-05, 2.5482978e-05,
		2.7139006e-05, 2.8902651e-05, 3.0780908e-05, 3.2781225e-05,
		3.4911534e-05, 3.7180282e-05, 3.9596466e-05, 4.2169667e-05,
		4.4910090e-05, 4.7828601e-05, 5.0936773e-05, 5.4246931e-05,
		5.7772202e-05, 6.1526565e-05, 6.5524908e-05, 6.9783085e-05,
		7.4317983e-05, 7.9147585e-05, 8.4291040e-05, 8.9768747e-05,
		9.5602426e-05, 0.00010181521, 0.00010843174, 0.00011547824,
		0.00012298267, 0.00013097477, 0.00013948625, 0.00014855085,
		0.00015820453, 0.00016848555, 0.00017943469, 0.00019109536,
		0.00020351382, 0.00021673929, 0.00023082423, 0.00024582449,
		0.00026179955, 0.00027881276, 0.00029693158, 0.00031622787,
		0.00033677814, 0.00035866388, 0.00038197188, 0.00040679456,
		0.00043323036, 0.00046138411, 0.00049136745, 0.00052329927,
		0.00055730621, 0.00059352311, 0.00063209358, 0.00067317058,
		0.00071691700, 0.00076350630, 0.00081312324, 0.00086596457,
		0.00092223983, 0.00098217216, 0.0010459992, 0.0011139742,
		0.0011863665, 0.0012634633, 0.0013455702, 0.0014330129,
		0.0015261382, 0.0016253153, 0.0017309374, 0.0018434235,
		0.0019632195, 0.0020908006, 0.0022266726, 0.0023713743,
		0.0025254795, 0.0026895994, 0.0028643847, 0.0030505286,
		0.0032487691, 0.0034598925, 0.0036847358, 0.0039241906,
		0.0041792066, 0.0044507950, 0.0047400328, 0.0050480668,
		0.0053761186, 0.0057254891, 0.0060975636, 0.0064938176,
		0.0069158225, 0.0073652516, 0.0078438871, 0.0083536271,
		0.0088964928, 0.009474637, 0.010090352, 0.010746080,
		0.011444421, 0.012188144, 0.012980198, 0.013823725,
		0.014722068, 0.015678791, 0.016697687, 0.017782797,
		0.018938423, 0.020169149, 0.021479854, 0.022875735,
		0.024362330, 0.025945531, 0.027631618, 0.029427276,
		0.031339626, 0.033376252, 0.035545228, 0.037855157,
		0.040315199, 0.042935108, 0.045725273, 0.048696758,
		0.051861348, 0.055231591, 0.058820850, 0.062643361,
		0.066714279, 0.071049749, 0.075666962, 0.080584227,
		0.085821044, 0.091398179, 0.097337747, 0.10366330,
		0.11039993, 0.11757434, 0.12521498, 0.13335215,
		0.14201813, 0.15124727, 0.16107617, 0.17154380,
		0.18269168, 0.19456402, 0.20720788, 0.22067342,
		0.23501402, 0.25028656, 0.26655159, 0.28387361,
		0.30232132, 0.32196786, 0.34289114, 0.36517414,
		0.38890521, 0.41417847, 0.44109412, 0.46975890,
		0.50028648, 0.53279791, 0.56742212, 0.60429640,
		0.64356699, 0.68538959, 0.72993007, 0.77736504,
		0.82788260, 0.88168307, 0.9389798, 1.0,
	}

	scale :: #force_inline proc(target: [^]f32, from: int, to: int, value: f32) #no_bounds_check {
		x := from

		for ; x + 4 <= to; x += 4 {
			store(target, x, load(target, x) * value)
		}

		for ; x < to; x += 1 {
			target[x] *= value
		}
	}

	lx := 0
	ly := int(final_y[0]) * floor.multiplier

	for order in 1..<floor.values {
		point := floor.sorted_order[order]

		if final_y[point] < 0 {
			continue
		}

		hy := int(final_y[point]) * floor.multiplier
		hx := int(floor.x_list[point])
		dy := hy - ly
		adx := hx - lx
		ady := abs(dy)
		x1 := min(hx, n2)

		if ady == 0 {
			scale(target, lx, x1, INVERSE_DB_TABLE[ly & 255])
		} else if ady * RUN_THRESHOLD <= adx {
			step := dy < 0 ? -1 : 1
			x := lx
			y := ly
			run := int(u32(adx) / u32(ady))
			run_rem := int(u32(adx) % u32(ady))
			k := 0
			err := ady - 1

			for _ in 0..<ady {
				k += run
				err += run_rem

				if err >= ady {
					err -= ady
					k += 1
				}

				end := min(lx + k, x1)
				scale(target, x, end, INVERSE_DB_TABLE[y & 255])
				x = end
				y += step
			}
		} else if lx < x1 {
			base := int(i32(dy) / i32(adx))
			sy := dy < 0 ? base - 1 : base + 1
			ady -= abs(base) * adx
			y := ly
			err := 0
			target[lx] *= INVERSE_DB_TABLE[y & 255]

			for x in lx + 1..<x1 {
				err += ady
				over := err >= adx
				err -= over ? adx : 0
				y += over ? sy : base
				target[x] *= INVERSE_DB_TABLE[y & 255]
			}
		}

		lx = hx
		ly = hy
	}

	if lx < n2 {
		scale(target, lx, n2, INVERSE_DB_TABLE[ly & 255])
	}
}

make_imdct_tables :: proc(n: int, allocator: runtime.Allocator) -> Imdct_Tables {
	output_index :: proc(position: int, length: int, radix_2: bool) -> int {
		if length == 1 {
			return 0
		}

		radix := radix_2 ? 2 : 4
		sub_length := length / radix
		sub_index := output_index(position % sub_length, sub_length, false)
		return radix * sub_index + position / sub_length
	}

	m := n / 2
	q := n / 4
	radix_2 := ilog(q) & 1 == 0
	tables: Imdct_Tables
	tables.pre = make([]f32, q * 2, allocator)
	tables.post = make([]f32, q * 2, allocator)
	tables.positions = make([]u16, q, allocator)
	tables.fft_twiddles = make([]f32, q * 3, allocator)

	for k in 0..<q {
		slot := k / 4 * 8 + k % 4
		pre_angle := math.PI * f64(4 * k + 1) / f64(4 * m)
		post_angle := math.PI * f64(k) / f64(m)
		tables.pre[slot] = f32(math.cos(pre_angle))
		tables.pre[slot + 4] = f32(math.sin(pre_angle))
		tables.post[slot] = f32(math.cos(post_angle))
		tables.post[slot + 4] = f32(math.sin(post_angle))
	}

	for natural in 0..<q {
		group := natural - natural % 16
		position := group + 4 * (natural % 4) + natural % 16 / 4
		tables.positions[output_index(natural, q, radix_2)] = u16(position)
	}

	length := q
	w := 0

	if radix_2 {
		for j in 0..<length / 2 {
			angle := 2 * math.PI * f64(j) / f64(length)
			slot := w + j / 4 * 8 + j % 4
			tables.fft_twiddles[slot] = f32(math.cos(angle))
			tables.fft_twiddles[slot + 4] = f32(-math.sin(angle))
		}

		w += length
		length /= 2
	}

	for length >= 16 {
		for j in 0..<length / 4 {
			for power in 1..=3 {
				angle := 2 * math.PI * f64(j * power) / f64(length)
				slot := w + j / 4 * 24 + (power - 1) * 8 + j % 4
				tables.fft_twiddles[slot] = f32(math.cos(angle))
				tables.fft_twiddles[slot + 4] = f32(-math.sin(angle))
			}
		}

		w += length / 4 * 6
		length /= 4
	}

	return tables
}

inverse_mdct :: proc(d: ^Decoder, buffer: [^]f32, n: int, blocktype: int) #no_bounds_check {
	gather :: #force_inline proc(p: [^]f32, positions: [^]u16) -> F32x4 #no_bounds_check {
		return { p[positions[0]], p[positions[1]], p[positions[2]], p[positions[3]] }
	}

	tables := &d.imdct_tables[blocktype]
	m := n / 2
	q := n / 4
	re := raw_data(d.imdct_scratch)
	im := re[q:]
	pre := raw_data(tables.pre)

	for k := 0; k < q; k += 4 {
		x0 := load(buffer, 2 * k)
		x1 := load(buffer, 2 * k + 4)
		h0 := load(buffer, m - 8 - 2 * k)
		h1 := load(buffer, m - 4 - 2 * k)
		a := simd.shuffle(x0, x1, 0, 2, 4, 6)
		b := simd.shuffle(h1, h0, 3, 1, 7, 5)
		c := load(pre, k * 2)
		s := load(pre, k * 2 + 4)
		store(re, k, a * c + b * s)
		store(im, k, b * c - a * s)
	}

	length := q
	twiddles := raw_data(tables.fft_twiddles)

	if ilog(q) & 1 == 0 {
		half := length / 2

		for j := 0; j < half; j += 4 {
			ar := load(re, j)
			ai := load(im, j)
			br := load(re, j + half)
			bi := load(im, j + half)
			wr := load(twiddles, j * 2)
			wi := load(twiddles, j * 2 + 4)
			dr := ar - br
			di := ai - bi
			store(re, j, ar + br)
			store(im, j, ai + bi)
			store(re, j + half, dr * wr - di * wi)
			store(im, j + half, dr * wi + di * wr)
		}

		twiddles = twiddles[length:]
		length = half
	}

	for length >= 16 {
		quarter := length / 4

		for start := 0; start < q; start += length {
			w := 0

			for j := start; j < start + quarter; j += 4 {
				ar := load(re, j)
				ai := load(im, j)
				br := load(re, j + quarter)
				bi := load(im, j + quarter)
				cr := load(re, j + quarter * 2)
				ci := load(im, j + quarter * 2)
				dr := load(re, j + quarter * 3)
				di := load(im, j + quarter * 3)
				t0r := ar + cr
				t0i := ai + ci
				t1r := ar - cr
				t1i := ai - ci
				t2r := br + dr
				t2i := bi + di
				t3r := br - dr
				t3i := bi - di
				store(re, j, t0r + t2r)
				store(im, j, t0i + t2i)
				ur := t1r + t3i
				ui := t1i - t3r
				wr := load(twiddles, w)
				wi := load(twiddles, w + 4)
				store(re, j + quarter, ur * wr - ui * wi)
				store(im, j + quarter, ur * wi + ui * wr)
				ur = t0r - t2r
				ui = t0i - t2i
				wr = load(twiddles, w + 8)
				wi = load(twiddles, w + 12)
				store(re, j + quarter * 2, ur * wr - ui * wi)
				store(im, j + quarter * 2, ur * wi + ui * wr)
				ur = t1r - t3i
				ui = t1i + t3r
				wr = load(twiddles, w + 16)
				wi = load(twiddles, w + 20)
				store(re, j + quarter * 3, ur * wr - ui * wi)
				store(im, j + quarter * 3, ur * wi + ui * wr)
				w += 24
			}
		}

		twiddles = twiddles[quarter * 6:]
		length = quarter
	}

	for j := 0; j < q; j += 16 {
		r0 := load(re, j)
		r1 := load(re, j + 4)
		r2 := load(re, j + 8)
		r3 := load(re, j + 12)
		i0 := load(im, j)
		i1 := load(im, j + 4)
		i2 := load(im, j + 8)
		i3 := load(im, j + 12)
		r01_lo := simd.shuffle(r0, r1, 0, 4, 1, 5)
		r01_hi := simd.shuffle(r0, r1, 2, 6, 3, 7)
		r23_lo := simd.shuffle(r2, r3, 0, 4, 1, 5)
		r23_hi := simd.shuffle(r2, r3, 2, 6, 3, 7)
		i01_lo := simd.shuffle(i0, i1, 0, 4, 1, 5)
		i01_hi := simd.shuffle(i0, i1, 2, 6, 3, 7)
		i23_lo := simd.shuffle(i2, i3, 0, 4, 1, 5)
		i23_hi := simd.shuffle(i2, i3, 2, 6, 3, 7)
		ar := simd.shuffle(r01_lo, r23_lo, 0, 1, 4, 5)
		br := simd.shuffle(r01_lo, r23_lo, 2, 3, 6, 7)
		cr := simd.shuffle(r01_hi, r23_hi, 0, 1, 4, 5)
		dr := simd.shuffle(r01_hi, r23_hi, 2, 3, 6, 7)
		ai := simd.shuffle(i01_lo, i23_lo, 0, 1, 4, 5)
		bi := simd.shuffle(i01_lo, i23_lo, 2, 3, 6, 7)
		ci := simd.shuffle(i01_hi, i23_hi, 0, 1, 4, 5)
		di := simd.shuffle(i01_hi, i23_hi, 2, 3, 6, 7)
		t0r := ar + cr
		t0i := ai + ci
		t1r := ar - cr
		t1i := ai - ci
		t2r := br + dr
		t2i := bi + di
		t3r := br - dr
		t3i := bi - di
		store(re, j, t0r + t2r)
		store(im, j, t0i + t2i)
		store(re, j + 4, t1r + t3i)
		store(im, j + 4, t1i - t3r)
		store(re, j + 8, t0r - t2r)
		store(im, j + 8, t0i - t2i)
		store(re, j + 12, t1r - t3i)
		store(im, j + 12, t1i + t3r)
	}

	post := raw_data(tables.post)
	positions := raw_data(tables.positions)
	negate := U32x4 { SIGN, SIGN, SIGN, SIGN }

	for k := 0; k < q / 2; k += 4 {
		back := q - 4 - k
		fr := gather(re, positions[k:])
		fi := gather(im, positions[k:])
		br := gather(re, positions[back:])
		bi := gather(im, positions[back:])
		fc := load(post, k * 2)
		fs := load(post, k * 2 + 4)
		bc := load(post, back * 2)
		bs := load(post, back * 2 + 4)
		re_front := fr * fc + fi * fs
		im_front := fi * fc - fr * fs
		re_back := br * bc + bi * bs
		im_back := bi * bc - br * bs
		negative_re_front := flip(re_front, negate)
		negative_im_front := flip(im_front, negate)
		negative_re_back := flip(re_back, negate)
		high_up := m + m / 2 + 2 * k
		high_down := m + m / 2 - 8 - 2 * k
		low_down := m / 2 - 8 - 2 * k
		low_up := m / 2 + 2 * k
		store(buffer, high_up, simd.shuffle(negative_re_front, im_back, 0, 7, 1, 6))
		store(buffer, high_up + 4, simd.shuffle(negative_re_front, im_back, 2, 5, 3, 4))
		store(buffer, high_down, simd.shuffle(im_back, negative_re_front, 0, 7, 1, 6))
		store(buffer, high_down + 4, simd.shuffle(im_back, negative_re_front, 2, 5, 3, 4))
		store(buffer, low_down, simd.shuffle(re_back, negative_im_front, 0, 7, 1, 6))
		store(buffer, low_down + 4, simd.shuffle(re_back, negative_im_front, 2, 5, 3, 4))
		store(buffer, low_up, simd.shuffle(im_front, negative_re_back, 0, 7, 1, 6))
		store(buffer, low_up + 4, simd.shuffle(im_front, negative_re_back, 2, 5, 3, 4))
	}
}

_restart :: proc(d: ^Decoder) -> int {
	force_resync(d)

	if d.restart_offset != 0 {
		d.needs_sync = false
		d.first_decode = true
	}

	return d.restart_offset
}

_force_resync :: proc(d: ^Decoder, skip_to_frame: int) {
	d.stream_ended = false
	d.previous_length = 0
	d.needs_sync = true
	d.next_segment = NO_SEGMENT
	d.first_decode = false
	d.discard_frames_deferred = 0
	d.current_frame_valid = false
	d.seek_target = skip_to_frame
}

_find_seek_point :: proc(
	d: ^Decoder,
	data: []u8,
	target_frame: int,
) -> (
	offset: int,
	frame: int,
) {
	MAX_OGG_PAGE_SIZE :: 65307
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

			start, start_ok := page_start(d, data[offset:offset + size], NO_SEEK_TARGET)

			if start_ok {
				return offset, size, start.output_frame, true
			}

			offset += size
		}
	}

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
		start, _ := page_start(d, data[offset:offset + size], target_frame)
		frame = start.output_frame
	}

	return
}

_total_frames :: proc(data: []u8) -> int {
	for idx := len(data) - PAGE_HEADER_SIZE; idx >= 0; idx -= 1 {
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

ilog :: proc(n: int) -> int {
	if n <= 0 {
		return 0
	}

	return 64 - int(bits.count_leading_zeros(u64(n)))
}

PAGE_OFFSET_VERSION :: 4
PAGE_OFFSET_FLAGS :: 5
PAGE_OFFSET_GRANULE :: 6
PAGE_OFFSET_CHECKSUM :: 22
PAGE_OFFSET_SEGMENT_COUNT :: 26
PAGE_HEADER_SIZE :: 27

NO_KNOWN_FRAME :: -2
NO_GRANULE :: -1
NO_SEGMENT :: -1
NO_SEEK_TARGET :: min(int)
FULL_SEGMENT :: 255

CODE_LENGTH_BITS :: 8
CODE_LENGTH_MASK :: 255
PREDICT_SHIFT :: 40

PAGE_FLAG_CONTINUED_PACKET :: 1
PAGE_FLAG_FIRST_PAGE :: 2
PAGE_FLAG_LAST_PAGE :: 4

read_u32 :: proc(data: []u8, offset: int) -> u32 {
	return u32(intrinsics.unaligned_load((^u32le)(raw_data(data[offset:offset + 4]))))
}

read_granule :: proc(page: []u8) -> int {
	return int(intrinsics.unaligned_load((^i64le)(raw_data(page[PAGE_OFFSET_GRANULE:][:8]))))
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

	search: for ; i + PAGE_HEADER_SIZE <= len(data); i += 1 {
		if data[i] != 'O' || data[i + 1] != 'g' || data[i + 2] != 'g' || data[i + 3] != 'S' {
			continue
		}

		if data[i + PAGE_OFFSET_VERSION] != 0 {
			continue
		}

		segment_count := int(data[i + PAGE_OFFSET_SEGMENT_COUNT])

		if i + PAGE_HEADER_SIZE + segment_count > len(data) {
			return i, 0, false
		}

		size = PAGE_HEADER_SIZE + segment_count

		for length in data[i + PAGE_HEADER_SIZE:][:segment_count] {
			size += int(length)
		}

		if i + size > len(data) {
			return i, 0, false
		}

		crc: u32

		for value, j in data[i:i + size] {
			byte := j >= PAGE_OFFSET_CHECKSUM && j < PAGE_OFFSET_CHECKSUM + 4 ? 0 : value
			crc = (crc << 8) ~ crc_table[byte ~ u8(crc >> 24)]
		}

		if crc == read_u32(data, i + PAGE_OFFSET_CHECKSUM) {
			return i, size, true
		}
	}

	return i, 0, false
}

page_start :: proc(
	d: ^Decoder,
	page: []u8,
	target_frame: int,
) -> (
	start: Page_Start,
	ok: bool,
) {
	granule := read_granule(page)

	flags := page[PAGE_OFFSET_FLAGS]

	if granule == NO_GRANULE || flags & (PAGE_FLAG_FIRST_PAGE | PAGE_FLAG_LAST_PAGE) != 0 {
		return
	}

	segment_count := int(page[PAGE_OFFSET_SEGMENT_COUNT])
	table := page[PAGE_HEADER_SIZE:][:segment_count]
	position := PAGE_HEADER_SIZE + segment_count
	segment := 0

	if flags & PAGE_FLAG_CONTINUED_PACKET != 0 {
		ended := false

		for segment < segment_count && !ended {
			position += int(table[segment])
			ended = table[segment] < FULL_SEGMENT
			segment += 1
		}

		if !ended {
			return
		}
	}

	advances: [MAX_PAGE_SEGMENTS]i32
	advance := 0
	last_right_start := 0
	last_n2 := 0
	packets := 0

	for segment < segment_count {
		start := position
		complete := false

		for segment < segment_count && !complete {
			position += int(table[segment])
			complete = table[segment] < FULL_SEGMENT
			segment += 1
		}

		if !complete {
			break
		}

		if position == start {
			return
		}

		header := u32(page[start])

		if position - start > 1 {
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

	start.decoder_frame = granule - last_n2 + last_right_start - advance

	if start.decoder_frame < 0 {
		return
	}

	start.output_frame = start.decoder_frame + int(advances[0])

	for start.packets_to_skip + 1 < packets {
		next_output_frame := start.output_frame + int(advances[start.packets_to_skip + 1])

		if next_output_frame > target_frame {
			break
		}

		start.decoder_frame = start.output_frame
		start.output_frame = next_output_frame
		start.packets_to_skip += 1
	}

	return start, true
}

read_packet :: proc(d: ^Decoder, data: []u8) -> (bytes_used: int, err: Error) {
	clear(&d.packet)
	position := 0
	segment := d.next_segment
	table := d.segments[:d.segment_count]
	flags := d.page_flags
	end_segment_with_known_frame := d.end_segment_with_known_frame
	known_frame := d.known_frame
	new_page := false
	started := false

	for {
		if segment == NO_SEGMENT {
			if position + PAGE_HEADER_SIZE > len(data) {
				return 0, .Need_More_Data
			}

			if string(data[position:position + 4]) != "OggS" {
				return 0, .Invalid_Stream
			}

			if data[position + PAGE_OFFSET_VERSION] != 0 {
				return 0, .Invalid_Stream
			}

			segment_count := int(data[position + PAGE_OFFSET_SEGMENT_COUNT])

			if position + PAGE_HEADER_SIZE + segment_count > len(data) {
				return 0, .Need_More_Data
			}

			flags = data[position + PAGE_OFFSET_FLAGS]

			if flags & PAGE_FLAG_FIRST_PAGE != 0 {
				d.stream_ended = true
				return 0, .None
			}

			table = data[position + PAGE_HEADER_SIZE:][:segment_count]
			granule := read_granule(data[position:])
			end_segment_with_known_frame = NO_KNOWN_FRAME

			if granule != NO_GRANULE {
				for i := segment_count - 1; i >= 0; i -= 1 {
					if table[i] < FULL_SEGMENT {
						end_segment_with_known_frame = i
						known_frame = granule
						break
					}
				}
			}

			position += PAGE_HEADER_SIZE + segment_count
			segment = 0
			new_page = true

			if started && flags & PAGE_FLAG_CONTINUED_PACKET == 0 {
				return 0, .Invalid_Stream
			}

			if !started && flags & PAGE_FLAG_CONTINUED_PACKET != 0 {
				for segment < segment_count {
					length := int(table[segment])
					position += length
					segment += 1

					if length < FULL_SEGMENT {
						break
					}
				}

				if position > len(data) {
					return 0, .Need_More_Data
				}
			}

			if segment >= segment_count {
				segment = NO_SEGMENT
				continue
			}
		}

		started = true
		length := int(table[segment])

		if position + length > len(data) {
			return 0, .Need_More_Data
		}

		append(&d.packet, ..data[position:position + length])
		position += length
		d.packet_ends_known_frame = segment == end_segment_with_known_frame
		segment += 1

		if segment == len(table) {
			segment = NO_SEGMENT
		}

		if length < FULL_SEGMENT {
			break
		}
	}

	if new_page {
		copy(d.segments[:], table)
		d.segment_count = len(table)
	}

	d.next_segment = segment
	d.page_flags = flags
	d.end_segment_with_known_frame = end_segment_with_known_frame
	d.known_frame = known_frame

	for _ in 0..<PACKET_PADDING {
		append(&d.packet, 0)
	}

	return position, .None
}

F32x4 :: #simd[4]f32
U32x4 :: #simd[4]u32
SIGN :: 0x80000000

load :: #force_inline proc(p: [^]f32, i: int) -> F32x4 #no_bounds_check {
	return intrinsics.unaligned_load((^F32x4)(&p[i]))
}

store :: #force_inline proc(p: [^]f32, i: int, v: F32x4) #no_bounds_check {
	intrinsics.unaligned_store((^F32x4)(&p[i]), v)
}

flip :: #force_inline proc(v: F32x4, mask: U32x4) -> F32x4 {
	return transmute(F32x4)simd.bit_xor(transmute(U32x4)v, mask)
}

PACKET_PADDING :: 16

bits_init :: proc(reader: ^Bit_Reader, padded_packet: []u8) {
	reader.data = raw_data(padded_packet)
	reader.last = len(padded_packet) - 8
	reader.pos = 0
	reader.acc = 0
	reader.valid = 0
	reader.total_bits = (len(padded_packet) - PACKET_PADDING) * 8
}

bits_refill :: #force_inline proc(reader: ^Bit_Reader) #no_bounds_check {
	if reader.pos <= reader.last {
		word := u64(intrinsics.unaligned_load((^u64le)(&reader.data[reader.pos])))
		reader.acc |= word << uint(reader.valid & 63)
	}

	reader.pos += (63 - reader.valid) >> 3
	reader.valid |= 56
}

bits_eop :: #force_inline proc(reader: ^Bit_Reader) -> bool {
	return reader.pos * 8 - reader.valid > reader.total_bits
}

get_bits :: #force_inline proc(reader: ^Bit_Reader, n: int) -> u32 {
	if reader.valid < n {
		bits_refill(reader)
	}

	z := u32(reader.acc & (u64(1) << uint(n & 63) - 1))
	reader.acc >>= uint(n & 63)
	reader.valid -= n
	return z
}

codebook_decode_long :: proc(book: ^Codebook, acc: u32) -> u32 #no_bounds_check {
	count := len(book.long_codewords)

	if count == 0 {
		return 0
	}

	code := bits.reverse_bits(acc)
	x := 0

	for count > 1 {
		m := x + (count >> 1)

		if book.long_codewords[m] <= code {
			x = m
			count -= count >> 1
		} else {
			count >>= 1
		}
	}

	value := book.long_values[x]

	if (code ~ book.long_codewords[x]) >> (32 - (value & CODE_LENGTH_MASK)) != 0 {
		return 0
	}

	return value
}

codebook_decode_refilled :: #force_inline proc(
	reader: ^Bit_Reader,
	book: ^Codebook,
	fast: [^]u32,
	fast_mask: u64,
) -> int #no_bounds_check {
	value := fast[reader.acc & fast_mask]

	if value == 0 {
		value = codebook_decode_long(book, u32(reader.acc))
	}

	n := int(value & CODE_LENGTH_MASK)
	reader.acc >>= uint(n & 63)
	reader.valid -= n
	return int(value >> CODE_LENGTH_BITS)
}

codebook_decode :: #force_inline proc(reader: ^Bit_Reader, book: ^Codebook) -> int {
	if reader.valid < 32 {
		bits_refill(reader)
	}

	return codebook_decode_refilled(reader, book, raw_data(book.fast), book.fast_mask)
}

packet_window :: proc(
	d: ^Decoder,
	header: u32,
) -> (
	mode: ^Mode,
	left_start: int,
	right_start: int,
	right_end: int,
	ok: bool,
) {
	if header & 1 != 0 {
		return
	}

	mode_index := int(header >> 1) & (1 << uint(d.mode_bits) - 1)

	if mode_index >= d.mode_count {
		return
	}

	mode = &d.modes[mode_index]
	n := d.blocksize[mode.blockflag]
	prev := mode.blockflag != 0 && header >> uint(d.mode_bits + 1) & 1 != 0
	next := mode.blockflag != 0 && header >> uint(d.mode_bits + 2) & 1 != 0
	right_start = n >> 1
	right_end = n

	if mode.blockflag != 0 && !prev {
		left_start = (n - d.blocksize[0]) >> 2
	}

	if mode.blockflag != 0 && !next {
		right_start = (n * 3 - d.blocksize[0]) >> 2
		right_end = (n * 3 + d.blocksize[0]) >> 2
	}

	return mode, left_start, right_start, right_end, true
}

