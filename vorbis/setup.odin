#+private package
package karl2d_vorbis

import "base:runtime"
import "core:math"
import "core:math/bits"
import "core:slice"

FAST_HUFFMAN_BITS :: 10
MAX_FLOOR_VALUES :: 31 * 8 + 2

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
	residue_books: [][8]i16,
	partition_bits: [][8]i32,
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

ilog :: proc(n: int) -> int {
	if n <= 0 {
		return 0
	}

	return 64 - int(bits.count_leading_zeros(u64(n)))
}

float32_unpack :: proc(x: u32) -> f32 {
	mantissa := x & 0x1fffff
	sign := x & 0x80000000
	exp := (x & 0x7fe00000) >> 21
	res := sign != 0 ? -f64(mantissa) : f64(mantissa)
	return f32(math.ldexp(f64(f32(res)), int(exp) - 788))
}

lookup1_values :: proc(entries: int, dim: int) -> int {
	pow_at_most :: proc(r: int, dim: int, limit: int) -> bool {
		acc := i64(1)

		for _ in 0..<dim {
			acc *= i64(r)

			if acc > i64(limit) {
				return false
			}
		}

		return true
	}

	r := 0

	for pow_at_most(r + 1, dim, entries) {
		r += 1
	}

	return r
}

parse_setup :: proc(
	d: ^Decoder,
	allocator: runtime.Allocator,
	temp_allocator: runtime.Allocator,
) -> Error {
	MAX_CODEBOOK_FLOATS :: 1 << 22

	b: Bit_Reader
	bits_init(&b, d.packet[:])

	if get_bits(&b, 8) != 5 {
		return .Invalid_Stream
	}

	for ch in "vorbis" {
		if get_bits(&b, 8) != u32(ch) {
			return .Invalid_Stream
		}
	}

	codebook_count := int(get_bits(&b, 8)) + 1
	d.codebooks = make([]Codebook, codebook_count, allocator)

	for &c in d.codebooks {
		NO_CODE :: 255

		Long_Code :: struct {
			codeword: u32,
			value: u32,
		}

		if get_bits(&b, 24) != 0x564342 {
			return .Invalid_Stream
		}

		c.dimensions = int(get_bits(&b, 16))
		c.entries = int(get_bits(&b, 24))
		ordered := get_bits(&b, 1) != 0
		sparse := ordered ? false : get_bits(&b, 1) != 0

		if c.dimensions == 0 && c.entries != 0 {
			return .Invalid_Stream
		}

		if bits_eop(&b) || c.entries > b.total_bits {
			return .Invalid_Stream
		}

		lengths := make([]u8, c.entries, temp_allocator)

		if ordered {
			current_entry := 0
			current_length := int(get_bits(&b, 5)) + 1

			for current_entry < c.entries {
				limit := c.entries - current_entry
				n := int(get_bits(&b, ilog(limit)))

				if current_length >= 32 || current_entry + n > c.entries || bits_eop(&b) {
					return .Invalid_Stream
				}

				slice.fill(lengths[current_entry:current_entry + n], u8(current_length))
				current_entry += n
				current_length += 1
			}
		} else {
			for &length in lengths {
				length = NO_CODE

				if !sparse || get_bits(&b, 1) != 0 {
					length = u8(get_bits(&b, 5)) + 1

					if length == 32 {
						return .Invalid_Stream
					}
				}
			}
		}

		codewords := make([]u32, c.entries, temp_allocator)
		available: [32]u32
		first := 0

		for first < c.entries && lengths[first] == NO_CODE {
			first += 1
		}

		if first < c.entries {
			for i in 1..=int(lengths[first]) {
				available[i] = u32(1) << u32(32 - i)
			}
		}

		for i in first + 1..<c.entries {
			z := int(lengths[i])

			if z == NO_CODE {
				continue
			}

			for z > 0 && available[z] == 0 {
				z -= 1
			}

			if z == 0 {
				return .Invalid_Stream
			}

			res := available[z]
			available[z] = 0
			codewords[i] = bits.reverse_bits(res)

			for y := int(lengths[i]); y > z; y -= 1 {
				available[y] = res + (u32(1) << u32(32 - y))
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

		c.max_length = max_length
		fast_bits := min(max_length, FAST_HUFFMAN_BITS)
		c.fast = make([]u32, 1 << uint(fast_bits), allocator)
		c.fast_mask = u64(len(c.fast) - 1)
		long_codes := make([]Long_Code, long_count, temp_allocator)
		long_count = 0

		for length, i in lengths {
			if length == NO_CODE {
				continue
			}

			value := u32(i) << 8 | u32(length)

			if int(length) <= fast_bits {
				for z := codewords[i]; z < u32(len(c.fast)); z += u32(1) << length {
					c.fast[z] = value
				}
			} else {
				long_codes[long_count] = { bits.reverse_bits(codewords[i]), value }
				long_count += 1
			}
		}

		slice.sort_by(long_codes, proc(a: Long_Code, b: Long_Code) -> bool {
			return a.codeword < b.codeword
		})

		c.long_codewords = make([]u32, long_count, allocator)
		c.long_values = make([]u32, long_count, allocator)

		for long_code, i in long_codes {
			c.long_codewords[i] = long_code.codeword
			c.long_values[i] = long_code.value
		}

		lookup_type := get_bits(&b, 4)

		if lookup_type > 2 {
			return .Invalid_Stream
		}

		if lookup_type > 0 {
			minimum_value := float32_unpack(get_bits(&b, 32))
			delta_value := float32_unpack(get_bits(&b, 32))
			value_bits := int(get_bits(&b, 4)) + 1
			sequence_p := get_bits(&b, 1) != 0

			if c.dimensions == 0 || i64(c.entries) * i64(c.dimensions) > MAX_CODEBOOK_FLOATS {
				return .Invalid_Stream
			}

			lookup_values := c.entries * c.dimensions

			if lookup_type == 1 {
				lookup_values = lookup1_values(c.entries, c.dimensions)
			}

			if lookup_values == 0 {
				return .Invalid_Stream
			}

			if bits_eop(&b) || i64(lookup_values) * i64(value_bits) > i64(b.total_bits) {
				return .Invalid_Stream
			}

			mults := make([]u16, lookup_values, temp_allocator)

			for &m in mults {
				m = u16(get_bits(&b, value_bits))
			}

			c.multiplicands = make([]f32, c.entries * c.dimensions, allocator)

			for j in 0..<c.entries {
				if lengths[j] == NO_CODE {
					continue
				}

				div := i64(1)
				last: f32

				for k in 0..<c.dimensions {
					off := j * c.dimensions + k

					if lookup_type == 1 {
						off = int((i64(j) / div) % i64(lookup_values))
					}

					val := f32(mults[off]) * delta_value + minimum_value + last
					c.multiplicands[j * c.dimensions + k] = val

					if sequence_p {
						last = val
					}

					if lookup_type == 1 && k + 1 < c.dimensions {
						if div > i64(max(u32)) / i64(lookup_values) {
							return .Invalid_Stream
						}

						div *= i64(lookup_values)
					}
				}
			}
		}
	}

	time_count := int(get_bits(&b, 6)) + 1

	for _ in 0..<time_count {
		if get_bits(&b, 16) != 0 {
			return .Invalid_Stream
		}
	}

	floor_count := int(get_bits(&b, 6)) + 1
	d.floors = make([]Floor, floor_count, allocator)

	for &g in d.floors {
		floor_type := get_bits(&b, 16)

		if floor_type == 0 {
			return .Unsupported_Stream
		}

		if floor_type != 1 {
			return .Invalid_Stream
		}

		max_class := -1
		g.partitions = int(get_bits(&b, 5))

		for j in 0..<g.partitions {
			g.partition_class_list[j] = u8(get_bits(&b, 4))
			max_class = max(max_class, int(g.partition_class_list[j]))
		}

		for j in 0..=max_class {
			g.class_dimensions[j] = u8(get_bits(&b, 3)) + 1
			g.class_subclasses[j] = u8(get_bits(&b, 2))

			if g.class_subclasses[j] != 0 {
				g.class_masterbooks[j] = u8(get_bits(&b, 8))

				if int(g.class_masterbooks[j]) >= codebook_count {
					return .Invalid_Stream
				}
			}

			for k in 0..<1 << g.class_subclasses[j] {
				g.subclass_books[j][k] = i16(get_bits(&b, 8)) - 1

				if int(g.subclass_books[j][k]) >= codebook_count {
					return .Invalid_Stream
				}
			}
		}

		g.multiplier = int(get_bits(&b, 2)) + 1
		g.range_bits = int(get_bits(&b, 4))
		g.x_list[0] = 0
		g.x_list[1] = u16(1) << uint(g.range_bits)
		g.values = 2

		for j in 0..<g.partitions {
			class := g.partition_class_list[j]

			for _ in 0..<g.class_dimensions[class] {
				if g.values >= MAX_FLOOR_VALUES {
					return .Invalid_Stream
				}

				g.x_list[g.values] = u16(get_bits(&b, g.range_bits))
				g.values += 1
			}
		}

		for j in 0..<g.values {
			g.sorted_order[j] = u8(j)
		}

		for j in 1..<g.values {
			id := g.sorted_order[j]
			k := j

			for k > 0 && g.x_list[g.sorted_order[k - 1]] > g.x_list[id] {
				g.sorted_order[k] = g.sorted_order[k - 1]
				k -= 1
			}

			g.sorted_order[k] = id
		}

		for j in 0..<g.values - 1 {
			if g.x_list[g.sorted_order[j]] == g.x_list[g.sorted_order[j + 1]] {
				return .Invalid_Stream
			}
		}

		for j in 2..<g.values {
			low := -1
			high := 65536

			for i in 0..<j {
				x := int(g.x_list[i])

				if x > low && x < int(g.x_list[j]) {
					g.neighbors[j][0] = u8(i)
					low = x
				}

				if x < high && x > int(g.x_list[j]) {
					g.neighbors[j][1] = u8(i)
					high = x
				}
			}

			adx := u64(high - low)
			g.predict_dx[j] = u16(int(g.x_list[j]) - low)
			g.predict_inverse[j] = (1 << 40 + adx - 1) / adx
		}
	}

	residue_count := int(get_bits(&b, 6)) + 1
	d.residues = make([]Residue, residue_count, allocator)

	for &r in d.residues {
		residue_cascade: [64]u8
		r.type = int(get_bits(&b, 16))

		if r.type > 2 {
			return .Invalid_Stream
		}

		r.begin = int(get_bits(&b, 24))
		r.end = int(get_bits(&b, 24))

		if r.end < r.begin {
			return .Invalid_Stream
		}

		r.part_size = int(get_bits(&b, 24)) + 1
		r.classifications = int(get_bits(&b, 6)) + 1
		r.classbook = int(get_bits(&b, 8))

		if r.classbook >= codebook_count {
			return .Invalid_Stream
		}

		for j in 0..<r.classifications {
			high_bits: u8
			low_bits := u8(get_bits(&b, 3))

			if get_bits(&b, 1) != 0 {
				high_bits = u8(get_bits(&b, 5))
			}

			residue_cascade[j] = high_bits * 8 + low_bits
		}

		r.residue_books = make([][8]i16, r.classifications, allocator)
		r.partition_bits = make([][8]i32, r.classifications, allocator)

		for j in 0..<r.classifications {
			for k in 0..<8 {
				if residue_cascade[j] & (1 << uint(k)) != 0 {
					r.residue_books[j][k] = i16(get_bits(&b, 8))

					if int(r.residue_books[j][k]) >= codebook_count {
						return .Invalid_Stream
					}

					book := &d.codebooks[r.residue_books[j][k]]

					if len(book.multiplicands) == 0 {
						return .Invalid_Stream
					}

					if r.part_size % book.dimensions != 0 {
						return .Unsupported_Stream
					}

					r.stages = max(r.stages, k + 1)
					r.partition_bits[j][k] = i32(r.part_size / book.dimensions * book.max_length)
				} else {
					r.residue_books[j][k] = -1
				}
			}
		}

		classbook := &d.codebooks[r.classbook]
		classwords := classbook.dimensions

		if i64(classbook.entries) * i64(classwords) > MAX_CODEBOOK_FLOATS || classwords == 0 {
			return .Invalid_Stream
		}

		r.classdata = make([]u8, classbook.entries * classwords, allocator)

		for j in 0..<classbook.entries {
			temp := j

			for k := classwords - 1; k >= 0; k -= 1 {
				r.classdata[j * classwords + k] = u8(temp % r.classifications)
				temp /= r.classifications
			}
		}
	}

	mapping_count := int(get_bits(&b, 6)) + 1
	d.mappings = make([]Mapping, mapping_count, allocator)

	for &m in d.mappings {
		if get_bits(&b, 16) != 0 {
			return .Invalid_Stream
		}

		m.submaps = 1

		if get_bits(&b, 1) != 0 {
			m.submaps = int(get_bits(&b, 4)) + 1
		}

		if get_bits(&b, 1) != 0 {
			m.coupling_steps = int(get_bits(&b, 8)) + 1

			if m.coupling_steps > d.channels {
				return .Invalid_Stream
			}

			for k in 0..<m.coupling_steps {
				m.magnitude[k] = u8(get_bits(&b, ilog(d.channels - 1)))
				m.angle[k] = u8(get_bits(&b, ilog(d.channels - 1)))

				if int(m.magnitude[k]) >= d.channels || int(m.angle[k]) >= d.channels {
					return .Invalid_Stream
				}

				if m.magnitude[k] == m.angle[k] {
					return .Invalid_Stream
				}
			}
		}

		if get_bits(&b, 2) != 0 {
			return .Invalid_Stream
		}

		if m.submaps > 1 {
			for j in 0..<d.channels {
				m.mux[j] = u8(get_bits(&b, 4))

				if int(m.mux[j]) >= m.submaps {
					return .Invalid_Stream
				}
			}
		}

		for j in 0..<m.submaps {
			get_bits(&b, 8)
			m.submap_floor[j] = u8(get_bits(&b, 8))
			m.submap_residue[j] = u8(get_bits(&b, 8))

			if int(m.submap_floor[j]) >= floor_count {
				return .Invalid_Stream
			}

			if int(m.submap_residue[j]) >= residue_count {
				return .Invalid_Stream
			}
		}
	}

	d.mode_count = int(get_bits(&b, 6)) + 1
	d.mode_bits = ilog(d.mode_count - 1)

	for &m in d.modes[:d.mode_count] {
		m.blockflag = int(get_bits(&b, 1))
		window_type := get_bits(&b, 16)
		transform_type := get_bits(&b, 16)
		m.mapping = int(get_bits(&b, 8))

		if window_type != 0 || transform_type != 0 || m.mapping >= mapping_count {
			return .Invalid_Stream
		}
	}

	if bits_eop(&b) {
		return .Invalid_Stream
	}

	max_part_read := 0

	for r in d.residues {
		actual_size := d.blocksize[1]
		limit_begin := min(r.begin, actual_size)
		limit_end := min(r.end, actual_size)
		max_part_read = max(max_part_read, (limit_end - limit_begin) / r.part_size)
	}

	for i in 0..<d.channels {
		d.channel_buffers[0][i] = make([]f32, d.blocksize[1], allocator)
		d.channel_buffers[1][i] = make([]f32, d.blocksize[1], allocator)
		d.part_classes[i] = make([]i32, max_part_read + 1, allocator)
	}

	d.imdct_scratch = make([]f32, d.blocksize[1] / 2, allocator)
	d.interleaved = make([]f32, d.blocksize[1], allocator)

	for n, blocktype in d.blocksize {
		n2 := n >> 1
		window := make([]f32, n2, allocator)

		for i in 0..<n2 {
			s := f32(math.sin((f64(i) + 0.5) / f64(n2) * 0.5 * math.PI))
			window[i] = f32(math.sin(0.5 * math.PI * f64(s * s)))
		}

		d.window[blocktype] = window
		d.imdct_tables[blocktype] = make_imdct_tables(n, allocator)
	}

	return .None
}
