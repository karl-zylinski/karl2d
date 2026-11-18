#+private package
package karl2d_vorbis

import "base:intrinsics"
import "core:math/bits"
import "core:simd"

PACKET_PADDING :: 16

F32x4 :: #simd[4]f32

Bit_Reader :: struct {
	data: [^]u8,
	last: int,
	pos: int,
	acc: u64,
	valid: int,
	total_bits: int,
}

bits_init :: proc(b: ^Bit_Reader, padded_packet: []u8) {
	b.data = raw_data(padded_packet)
	b.last = len(padded_packet) - 8
	b.pos = 0
	b.acc = 0
	b.valid = 0
	b.total_bits = (len(padded_packet) - PACKET_PADDING) * 8
}

bits_refill :: #force_inline proc(b: ^Bit_Reader) #no_bounds_check {
	if b.pos <= b.last {
		b.acc |= u64(intrinsics.unaligned_load((^u64le)(&b.data[b.pos]))) << uint(b.valid & 63)
	}

	b.pos += (63 - b.valid) >> 3
	b.valid |= 56
}

bits_eop :: #force_inline proc(b: ^Bit_Reader) -> bool {
	return b.pos * 8 - b.valid > b.total_bits
}

get_bits :: #force_inline proc(b: ^Bit_Reader, n: int) -> u32 {
	if b.valid < n {
		bits_refill(b)
	}

	z := u32(b.acc & (u64(1) << uint(n & 63) - 1))
	b.acc >>= uint(n & 63)
	b.valid -= n
	return z
}

codebook_decode_long :: proc(c: ^Codebook, acc: u32) -> u32 #no_bounds_check {
	n := len(c.long_codewords)

	if n == 0 {
		return 0
	}

	code := bits.reverse_bits(acc)
	x := 0

	for n > 1 {
		m := x + (n >> 1)

		if c.long_codewords[m] <= code {
			x = m
			n -= n >> 1
		} else {
			n >>= 1
		}
	}

	value := c.long_values[x]

	if (code ~ c.long_codewords[x]) >> (32 - (value & 255)) != 0 {
		return 0
	}

	return value
}

bits_refill_unchecked :: #force_inline proc(b: ^Bit_Reader) #no_bounds_check {
	b.acc |= u64(intrinsics.unaligned_load((^u64le)(&b.data[b.pos]))) << uint(b.valid & 63)
	b.pos += (63 - b.valid) >> 3
	b.valid |= 56
}

codebook_decode_refilled :: #force_inline proc(
	b: ^Bit_Reader,
	c: ^Codebook,
	fast: [^]u32,
	fast_mask: u64,
) -> int #no_bounds_check {
	value := fast[b.acc & fast_mask]

	if value == 0 {
		value = codebook_decode_long(c, u32(b.acc))
	}

	n := int(value & 255)
	b.acc >>= uint(n & 63)
	b.valid -= n
	return int(value >> 8)
}

codebook_decode :: #force_inline proc(b: ^Bit_Reader, c: ^Codebook) -> int {
	if b.valid < 32 {
		bits_refill(b)
	}

	return codebook_decode_refilled(b, c, raw_data(c.fast), c.fast_mask)
}

decode_partition :: #force_no_inline proc(
	b: ^Bit_Reader,
	book: ^Codebook,
	target: [^]f32,
	part_size: int,
	worst_case_bits: int,
) -> bool #no_bounds_check {
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
		br: ^Bit_Reader,
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
				bits_refill_unchecked(br)
				first := codebook_decode_refilled(br, book, fast, fast_mask)
				second := codebook_decode_refilled(br, book, fast, fast_mask)
				add(target[k:], values[first * DIMS:], DIMS)
				add(target[k + DIMS:], values[second * DIMS:], DIMS)
			}
		}

		for ; k < part_size; k += DIMS {
			bits_refill_unchecked(br)
			entry := codebook_decode_refilled(br, book, fast, fast_mask)
			add(target[k:], values[entry * DIMS:], DIMS)
		}
	}

	br := b^

	defer b^ = br

	dims := book.dimensions

	if br.total_bits - (br.pos * 8 - br.valid) >= worst_case_bits {
		switch dims {
		case 1:
			decode_vectors(&br, book, target, part_size, 1)
			return true

		case 2:
			decode_vectors(&br, book, target, part_size, 2)
			return true

		case 4:
			decode_vectors(&br, book, target, part_size, 4)
			return true

		case 8:
			decode_vectors(&br, book, target, part_size, 8)
			return true
		}
	}

	values := raw_data(book.multiplicands)

	for k := 0; k < part_size; k += dims {
		entry := codebook_decode(&br, book)

		if bits_eop(&br) {
			return false
		}

		for l in 0..<dims {
			target[k + l] += values[entry * dims + l]
		}
	}

	return true
}

decode_residue_stereo :: proc(d: ^Decoder, b: ^Bit_Reader, r: ^Residue, n: int) #no_bounds_check {
	out := raw_data(d.interleaved)
	intrinsics.mem_zero(out, n * 2 * size_of(f32))
	classbook := &d.codebooks[r.classbook]
	classwords := classbook.dimensions
	part_classes := raw_data(d.part_classes[0])
	part_size := r.part_size
	part_read := (min(r.end, n * 2) - min(r.begin, n * 2)) / part_size
	br := b^

	defer b^ = br

	for pass in 0..<r.stages {
		pcount := 0
		class_set := 0

		for pcount < part_read {
			if pass == 0 {
				q := codebook_decode(&br, classbook)

				if bits_eop(&br) {
					return
				}

				part_classes[class_set] = i32(q)
			}

			class_row := r.classdata[int(part_classes[class_set]) * classwords:]

			for i := 0; i < classwords && pcount < part_read; i += 1 {
				class := class_row[i]
				book_index := r.residue_books[class][pass]

				if book_index >= 0 {
					book := &d.codebooks[book_index]
					target := out[r.begin + pcount * part_size:]
					worst_case_bits := int(r.partition_bits[class][pass])

					if !decode_partition(&br, book, target, part_size, worst_case_bits) {
						return
					}
				}

				pcount += 1
			}

			class_set += 1
		}
	}
}

decode_residue :: proc(
	d: ^Decoder,
	b: ^Bit_Reader,
	residue_buffers: [MAX_CHANNELS][^]f32,
	ch: int,
	n: int,
	r: ^Residue,
) #no_bounds_check {
	classbook := &d.codebooks[r.classbook]
	classwords := classbook.dimensions
	part_size := r.part_size
	part_read := (min(r.end, n) - min(r.begin, n)) / part_size
	br := b^

	defer b^ = br

	for i in 0..<ch {
		if residue_buffers[i] != nil {
			intrinsics.mem_zero(residue_buffers[i], n * size_of(f32))
		}
	}

	for pass in 0..<r.stages {
		pcount := 0
		class_set := 0

		for pcount < part_read {
			if pass == 0 {
				for j in 0..<ch {
					if residue_buffers[j] != nil {
						q := codebook_decode(&br, classbook)

						if bits_eop(&br) {
							return
						}

						d.part_classes[j][class_set] = i32(q)
					}
				}
			}

			for i := 0; i < classwords && pcount < part_read; i += 1 {
				for j in 0..<ch {
					if residue_buffers[j] == nil {
						continue
					}

					class := r.classdata[int(d.part_classes[j][class_set]) * classwords + i]
					book_index := r.residue_books[class][pass]

					if book_index < 0 {
						continue
					}

					book := &d.codebooks[book_index]
					target := residue_buffers[j][r.begin + pcount * part_size:]

					if r.type != 0 {
						worst_case_bits := int(r.partition_bits[class][pass])

						if !decode_partition(&br, book, target, part_size, worst_case_bits) {
							return
						}

						continue
					}

					dims := book.dimensions
					step := part_size / dims

					for k in 0..<step {
						entry := codebook_decode(&br, book)

						if bits_eop(&br) {
							return
						}

						for l in 0..<dims {
							target[k + l * step] += book.multiplicands[entry * dims + l]
						}
					}
				}

				pcount += 1
			}

			class_set += 1
		}
	}
}

do_floor :: proc(
	g: ^Floor,
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
	ly := int(final_y[0]) * g.multiplier

	for q in 1..<g.values {
		j := g.sorted_order[q]

		if final_y[j] < 0 {
			continue
		}

		hy := int(final_y[j]) * g.multiplier
		hx := int(g.x_list[j])
		dy := hy - ly
		adx := hx - lx
		ady := abs(dy)
		x1 := min(hx, n2)

		if ady * RUN_THRESHOLD <= adx {
			step := dy < 0 ? -1 : 1
			x := lx
			y := ly
			run := 0
			run_rem := 0

			if ady != 0 {
				run = int(u32(adx) / u32(ady))
				run_rem = int(u32(adx) % u32(ady))
			}

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

			if ady == 0 {
				scale(target, x, x1, INVERSE_DB_TABLE[y & 255])
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

decode_packet :: proc(d: ^Decoder) -> (length: int, left: int, right: int, ok: bool) {
	b: Bit_Reader
	bits_init(&b, d.packet[:])
	header := u32(d.packet[0]) | u32(d.packet[1]) << 8
	mode, left_start, right_start, right_end := packet_window(d, header) or_return
	get_bits(&b, 1 + d.mode_bits + (mode.blockflag != 0 ? 2 : 0))
	n := d.blocksize[mode.blockflag]
	n2 := n >> 1
	d.buffer_index = 1 - d.buffer_index
	buffers := d.channel_buffers[d.buffer_index]
	mapping := &d.mappings[mode.mapping]
	zero_channel: [MAX_CHANNELS]bool
	really_zero_channel: [MAX_CHANNELS]bool

	for i in 0..<d.channels {
		g := &d.floors[mapping.submap_floor[mapping.mux[i]]]

		if get_bits(&b, 1) == 0 {
			zero_channel[i] = true
			continue
		}

		RANGE_LIST := [4]int { 256, 128, 86, 64 }
		RANGE_BITS := [4]int { 8, 7, 7, 6 }
		range := RANGE_LIST[g.multiplier - 1]
		range_bits := RANGE_BITS[g.multiplier - 1]
		final_y := &d.final_y[i]
		step2_flag: [MAX_FLOOR_VALUES]bool
		offset := 2
		final_y[0] = i16(get_bits(&b, range_bits))
		final_y[1] = i16(get_bits(&b, range_bits))

		for j in 0..<g.partitions {
			pclass := g.partition_class_list[j]
			cdim := int(g.class_dimensions[pclass])
			cbits := g.class_subclasses[pclass]
			csub := (1 << cbits) - 1
			cval := 0

			if cbits != 0 {
				cval = codebook_decode(&b, &d.codebooks[g.class_masterbooks[pclass]])
			}

			for _ in 0..<cdim {
				book := g.subclass_books[pclass][cval & csub]
				cval >>= cbits

				if book >= 0 {
					final_y[offset] = i16(codebook_decode(&b, &d.codebooks[book]))
				} else {
					final_y[offset] = 0
				}

				offset += 1
			}
		}

		if bits_eop(&b) {
			zero_channel[i] = true
			continue
		}

		step2_flag[0] = true
		step2_flag[1] = true

		for j in 2..<g.values {
			low := g.neighbors[j][0]
			high := g.neighbors[j][1]
			y0 := int(final_y[low])
			dy := int(final_y[high]) - y0
			off := int((u64(abs(dy)) * u64(g.predict_dx[j]) * g.predict_inverse[j]) >> 40)
			pred := dy < 0 ? y0 - off : y0 + off
			val := int(final_y[j])
			highroom := range - pred
			lowroom := pred
			room := min(highroom, lowroom) * 2

			if val != 0 {
				step2_flag[low] = true
				step2_flag[high] = true
				step2_flag[j] = true

				if val >= room {
					if highroom > lowroom {
						final_y[j] = i16(val - lowroom + pred)
					} else {
						final_y[j] = i16(pred - val + highroom - 1)
					}
				} else if val & 1 != 0 {
					final_y[j] = i16(pred - ((val + 1) >> 1))
				} else {
					final_y[j] = i16(pred + (val >> 1))
				}
			} else {
				final_y[j] = i16(pred)
			}
		}

		for j in 0..<g.values {
			if !step2_flag[j] {
				final_y[j] = -1
			}
		}
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

		r := &d.residues[mapping.submap_residue[i]]

		if r.type != 2 || ch != 2 {
			decode_residue(d, &b, residue_buffers, ch, n2, r)
			continue
		}

		if zero_channel[0] && zero_channel[1] {
			continue
		}

		decode_residue_stereo(d, &b, r, n2)
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

			zero: F32x4
			delta := simd.select(simd.lanes_gt(m, zero), a, -a)
			a_positive := simd.lanes_gt(a, zero)
			store(magnitude, j, simd.select(a_positive, m, m + delta))
			store(angle, j, simd.select(a_positive, m - delta, m))
		}
	}

	for i := coupling_steps - 1; i >= 0; i -= 1 {
		magnitude := raw_data(buffers[mapping.magnitude[i]])
		angle := raw_data(buffers[mapping.angle[i]])

		#no_bounds_check for j := 0; j < n2; j += 4 {
			m := load(magnitude, j)
			a := load(angle, j)
			zero: F32x4
			delta := simd.select(simd.lanes_gt(m, zero), a, -a)
			a_positive := simd.lanes_gt(a, zero)
			store(magnitude, j, simd.select(a_positive, m, m + delta))
			store(angle, j, simd.select(a_positive, m - delta, m))
		}
	}

	for i in 0..<d.channels {
		buffer := raw_data(buffers[i])

		if really_zero_channel[i] {
			intrinsics.mem_zero(buffer, n * size_of(f32))
			continue
		}

		g := &d.floors[mapping.submap_floor[mapping.mux[i]]]
		do_floor(g, n2, buffer, &d.final_y[i])
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
				length = max(current_end - d.current_frame, 0) + left_start
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

finish_frame :: proc(d: ^Decoder, length: int, left: int, right: int) -> int #no_bounds_check {
	right := right
	prev := d.previous_length

	if prev != 0 {
		w := raw_data(d.window[prev * 2 == d.blocksize[0] ? 0 : 1])

		for i in 0..<d.channels {
			buffer := raw_data(d.channel_buffers[d.buffer_index][i])[left:]
			previous := raw_data(d.channel_buffers[1 - d.buffer_index][i])[d.previous_start:]

			for j := 0; j < prev; j += 4 {
				w_reversed := simd.swizzle(load(w, prev - 4 - j), 3, 2, 1, 0)
				store(buffer, j, load(buffer, j) * load(w, j) + load(previous, j) * w_reversed)
			}
		}
	}

	d.previous_length = length - right
	d.previous_start = right

	if d.previous_length * 2 != d.blocksize[0] && d.previous_length * 2 != d.blocksize[1] {
		d.previous_length = 0
	}

	if prev == 0 {
		return 0
	}

	if length < right {
		right = length
	}

	return right - left
}
