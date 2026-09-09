package flac

import "base:intrinsics"

File :: struct {
	data:      []u8,
	pos:       u64,
	bit_buf:   u64,
	bit_count: u64,

	info:    Info,
	buf_pos: u64,
	buf_len: u64,
	pcm_buf: [8][65535]i32,
}

Info :: struct {
	sample_rate:  u64,
	channels:     u64,
	bit_depth:    u64,
	sample_count: u64,
}

Frame_Header :: struct {
	blocking_strategy:   u64,
	block_size:          u64,
	sample_rate:         u64,
	bits_per_sample:     u64,
	channel_count:       u64,
	channel:             Channel,
	sample_or_frame_num: u64,
}

Subframe_Type :: enum {
	Constant,
	Verbatim,
	Fixed,
	LPC,
}

Channel :: enum {
	Independent_Mono   = 0,
	Independent_Stereo = 1,
	Independent_3C     = 2,
	Independent_4C     = 3,
	Independent_5C     = 4,
	Independent_6C     = 5,
	Independent_7C     = 6,
	Independent_8C     = 7,
	Left_Side_Stereo   = 8,
	Right_Side_Stereo  = 9,
	Mid_Side_Stereo    = 10,
}

open_memory :: proc(data: []u8) -> ^File {
	if len(data) < 4 || string(data[:4]) != "fLaC" {
		return nil
	}

	f := new(File)
	f.data = data[4:]

	if !parse(f) || f.info.sample_rate == 0 {
		free(f)
		return nil
	}

	return f
}

parse :: proc(f: ^File) -> bool {
	for {
		is_last := read_bits(f, 1) or_return
		type := read_bits(f, 7) or_return
		len := read_bits(f, 24) or_return
		end_pos := f.pos + len

		if type == 0 {
			if len != 34 do return false
			parse_stream_info(f) or_return
		}

		f.pos = end_pos
		align_to_byte(f)
		if is_last != 0 do break
	}

	return true
}

parse_stream_info :: proc(f: ^File) -> bool {
	read_bits(f, 16) or_return
	read_bits(f, 16) or_return
	read_bits(f, 24) or_return
	read_bits(f, 24) or_return
	f.info.sample_rate = read_bits(f, 20) or_return
	f.info.channels = (read_bits(f, 3) or_return) + 1
	f.info.bit_depth = (read_bits(f, 5) or_return) + 1
	f.info.sample_count = read_bits(f, 36) or_return

	return true
}

frame_header :: proc(f: ^File) -> (fh: Frame_Header, ok: bool) {
	align_to_byte(f)

	fh.bits_per_sample = f.info.bit_depth
	fh.sample_rate = f.info.sample_rate

	sync := read_bits(f, 14) or_return
	if sync != 0x3FFE do return
	if (read_bits(f, 1) or_return) != 0 do return
	fh.blocking_strategy = read_bits(f, 1) or_return

	block_size_enum := read_bits(f, 4) or_return
	sample_rate_enum := read_bits(f, 4) or_return
	channel_enum := read_bits(f, 4) or_return
	bit_depth_enum := read_bits(f, 3) or_return
	if (read_bits(f, 1) or_return) != 0 do return

	bs := BLOCK_SIZES[block_size_enum]
	if bs < 0 do return
	if bs > 0 do fh.block_size = u64(bs)

	sr := SAMPLE_RATES[sample_rate_enum]
	if sr < 0 do return
	if sr > 0 do fh.sample_rate = u64(sr)

	ss := SAMPLE_SIZES[bit_depth_enum]
	if ss < 0 do return
	if ss > 0 do fh.bits_per_sample = u64(ss)

	if channel_enum > 10 do return
	fh.channel = Channel(channel_enum)
	fh.channel_count = channel_enum >= 8 ? 2 : channel_enum + 1

	sync_val := read_utf8_uint(f) or_return
	fh.sample_or_frame_num = sync_val

	switch block_size_enum {
	case 6:
		v := read_bits(f, 8) or_return
		fh.block_size = u64(v) + 1
	case 7:
		v := read_bits(f, 16) or_return
		fh.block_size = u64(v) + 1
	}

	switch sample_rate_enum {
	case 12:
		v := read_bits(f, 8) or_return
		fh.sample_rate = u64(v) * 1000
	case 13:
		v := read_bits(f, 16) or_return
		fh.sample_rate = u64(v)
	case 14:
		v := read_bits(f, 16) or_return
		fh.sample_rate = u64(v) * 10
	}

	_ = read_bits(f, 8) or_return

	return fh, true
}

decode_frame :: proc(f: ^File) -> bool {
	fh := frame_header(f) or_return

	block_size := fh.block_size
	if block_size > u64(len(f.pcm_buf[0])) do return false

	for chan_idx in 0 ..< fh.channel_count {
		if chan_idx >= u64(len(f.pcm_buf)) do return false
		if (read_bits(f, 1) or_return) != 0 do return false

		sf_type_bits := read_bits(f, 6) or_return
		wasted_flag := read_bits(f, 1) or_return

		wasted_bits: u64 = 0
		if wasted_flag == 1 {
			wasted_bits = (read_unary(f) or_return) + 1
		}

		if wasted_bits >= fh.bits_per_sample do return false
		bps := fh.bits_per_sample - wasted_bits

		if (fh.channel == .Left_Side_Stereo && chan_idx == 1) ||
		   (fh.channel == .Right_Side_Stereo && chan_idx == 0) ||
		   (fh.channel == .Mid_Side_Stereo && chan_idx == 1) {
			bps += 1
		}

		sf_type: Subframe_Type
		order: u64 = 0

		if (sf_type_bits & 0x20) != 0 {
			sf_type = .LPC
			order = (sf_type_bits & 0x1F) + 1
		} else if (sf_type_bits & 0x08) != 0 {
			sf_type = .Fixed
			order = sf_type_bits & 0x07
			if order > 4 do return false
		} else if (sf_type_bits & 0x01) != 0 {
			sf_type = .Verbatim
		} else if sf_type_bits == 0 {
			sf_type = .Constant
		} else {
			return false
		}

		switch sf_type {
		case .Constant:
			s := sign_extend(read_bits(f, bps) or_return, bps)
			for i in 0 ..< block_size {
				f.pcm_buf[chan_idx][i] = s
			}
		case .Verbatim:
			for i in 0 ..< block_size {
				f.pcm_buf[chan_idx][i] = sign_extend(read_bits(f, bps) or_return, bps)
			}
		case .Fixed:
			if block_size < order do return false
			for i in 0 ..< order {
				f.pcm_buf[chan_idx][i] = sign_extend(read_bits(f, bps) or_return, bps)
			}
			decode_residual(f, chan_idx, block_size, order) or_return
			restore_fixed_signal(f.pcm_buf[chan_idx][:], block_size, order)
		case .LPC:
			if block_size < order do return false
			for i in 0 ..< order {
				f.pcm_buf[chan_idx][i] = sign_extend(read_bits(f, bps) or_return, bps)
			}
			lpc_prec := (read_bits(f, 4) or_return) + 1
			if lpc_prec == 16 do return false
			lpc_shift := sign_extend(read_bits(f, 5) or_return, 5)
			if lpc_shift < 0 do return false

			coeffs: [32]i32
			for j in 0 ..< order {
				coeffs[j] = sign_extend(read_bits(f, lpc_prec) or_return, lpc_prec)
			}

			decode_residual(f, chan_idx, block_size, order) or_return
			restore_lpc_signal(f.pcm_buf[chan_idx][:], block_size, order, coeffs[:order], lpc_shift)
		}

		if wasted_bits > 0 {
			for i in 0 ..< block_size {
				f.pcm_buf[chan_idx][i] <<= wasted_bits
			}
		}
	}

	if len(f.pcm_buf) >= 2 {
		c0 := &f.pcm_buf[0]
		c1 := &f.pcm_buf[1]
		#partial switch fh.channel {
		case .Left_Side_Stereo:
			for i in 0 ..< block_size {
				c1[i] = c0[i] - c1[i]
			}
		case .Right_Side_Stereo:
			for i in 0 ..< block_size {
				c0[i] = c0[i] + c1[i]
			}
		case .Mid_Side_Stereo:
			for i in 0 ..< block_size {
				mid := c0[i] << 1 | (c1[i] & 1)
				c0[i] = (mid + c1[i]) >> 1
				c1[i] = (mid - c1[i]) >> 1
			}
		case:
		}
	}

	align_to_byte(f)
	_ = read_bits(f, 16) or_return

	f.buf_pos = 0
	f.buf_len = block_size
	return true
}

decode_residual :: proc(f: ^File, chan_idx: u64, block_size: u64, order: u64) -> bool {
	method := read_bits(f, 2) or_return
	if method > 1 do return false

	partition_order := read_bits(f, 4) or_return
	num_partitions := u64(1) << partition_order
	samples_per_partition := block_size >> partition_order
	if samples_per_partition == 0 do return false

	param_bits: u64 = (method == 0) ? 4 : 5
	escape_val: u64 = (1 << param_bits) - 1

	sample_idx := order

	for p in 0 ..< num_partitions {
		k := read_bits(f, param_bits) or_return

		p_start := p * samples_per_partition
		p_end := (p + 1) * samples_per_partition
		res_start := max(p_start, order)
		n_samples := p_end > res_start ? (p_end - res_start) : 0

		if k == escape_val {
			verbatim_bps := read_bits(f, 5) or_return
			for _ in 0 ..< n_samples {
				if sample_idx >= block_size do return false
				if verbatim_bps == 0 {
					f.pcm_buf[chan_idx][sample_idx] = 0
				} else {
					f.pcm_buf[chan_idx][sample_idx] = sign_extend(read_bits(f, verbatim_bps) or_return, verbatim_bps)
				}
				sample_idx += 1
			}
		} else {
			for _ in 0 ..< n_samples {
				if sample_idx >= block_size do return false
				q := read_unary(f) or_return
				r: u64 = 0
				if k > 0 {
					r = read_bits(f, k) or_return
				}
				val := (q << k) | r
				res := (val & 1 != 0) ? -i32(val >> 1) - 1 : i32(val >> 1)
				f.pcm_buf[chan_idx][sample_idx] = res
				sample_idx += 1
			}
		}
	}

	return true
}

restore_fixed_signal :: proc(buf: []i32, block_size: u64, order: u64) {
	c := FIXED_COEFFS[order]
	for i in order ..< block_size {
		pred: i32 = 0
		for j in 0 ..< order do pred += i32(c[j]) * buf[i - 1 - j]
		buf[i] += pred
	}
}

restore_lpc_signal :: proc(buf: []i32, block_size: u64, order: u64, coeffs: []i32, shift: i32) {
	for i in order ..< block_size {
		accu: int = 0
		for j in 0 ..< order {
			accu += int(coeffs[j]) * int(buf[i - j - 1])
		}
		buf[i] += i32(accu >> u64(shift))
	}
}

read_float :: proc(f: ^File, output: []f32, max_channels: int = 2) -> int {
	if f.info.channels == 0 || max_channels <= 0 do return 0
	if f.info.bit_depth == 0 || f.info.bit_depth > 32 do return 0

	channels := min(int(f.info.channels), max_channels)
	if channels == 0 do return 0

	scale := f32(u64(1) << (f.info.bit_depth - 1))
	total_frames := len(output) / channels
	written := 0

	for written < total_frames {
		if f.buf_pos >= f.buf_len {
			if !decode_frame(f) {
				break
			}
		}

		for f.buf_pos < f.buf_len && written < total_frames {
			for c in 0 ..< channels {
				sample_i32 := f.pcm_buf[c][f.buf_pos]
				output[written * channels + c] = f32(sample_i32) / scale
			}
			written += 1
			f.buf_pos += 1
		}
	}

	return written
}

align_to_byte :: proc(f: ^File) {
	f.bit_buf = 0
	f.bit_count = 0
}

read_bits :: #force_inline proc(f: ^File, count: u64) -> (v: u64, ok: bool) {
	for f.bit_count < count {
		if int(f.pos) >= len(f.data) do return
		f.bit_buf |= u64(f.data[f.pos]) << (56 - f.bit_count)
		f.bit_count += 8
		f.pos += 1
	}

	v = f.bit_buf >> (64 - count)
	f.bit_buf <<= count
	f.bit_count -= count
	return v, true
}

read_utf8_uint :: proc(f: ^File) -> (v: u64, ok: bool) {
	b0 := read_bits(f, 8) or_return
	if b0 & 0x80 == 0 do return b0, true

	num_ones := u64(intrinsics.count_leading_zeros(~u8(b0)))

	v = b0 & (0xFF >> (num_ones + 1))
	for _ in 1 ..< num_ones {
		cb := read_bits(f, 8) or_return
		if (cb & 0xC0) != 0x80 do return
		v = (v << 6) | (cb & 0x3F)
	}

	return v, true
}

sign_extend :: proc(x: u64, b: u64) -> i32 {
	m := u64(1) << (b - 1)
	return i32((x ~ m) - m)
}

read_unary :: proc(f: ^File) -> (q: u64, ok: bool) {
	for q < 65536 {
		bit := read_bits(f, 1) or_return
		if bit == 1 do return q, true
		q += 1
	}
	return
}

// Tables
@(rodata)
BLOCK_SIZES := [16]i32 {
	-1, 192, 576, 1152, 2304, 4608, 0, 0,
	256, 512, 1024, 2048, 4096, 8192, 16384, 32768,
}

@(rodata)
SAMPLE_RATES := [16]i32 {
	0, 88200, 176400, 192000, 8000, 16000, 22050, 24000,
	32000, 44100, 48000, 96000, 0, 0, 0, -1,
}

@(rodata)
SAMPLE_SIZES := [8]i8 { 0, 8, 12, -1, 16, 20, 24, -1 }

@(rodata)
FIXED_COEFFS := [5][4]i8 {
	{0,  0, 0,  0},
	{1,  0, 0,  0},
	{2, -1, 0,  0},
	{3, -3, 1,  0},
	{4, -6, 4, -1},
}
