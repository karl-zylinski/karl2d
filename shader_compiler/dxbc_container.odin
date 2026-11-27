package karl2d_shader_compiler

import "base:runtime"
import "core:math/bits"

Dxbc_Chunk :: struct {
	fourcc: string,
	data: []u8,
}

dxbc_md5_transform :: proc(state: ^[4]u32, block: []u8) {
	shifts := [64]u32 {
		7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
		5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
		4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
		6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21,
	}

	sines := [64]u32 {
		0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee, 0xf57c0faf, 0x4787c62a, 0xa8304613, 0xfd469501,
		0x698098d8, 0x8b44f7af, 0xffff5bb1, 0x895cd7be, 0x6b901122, 0xfd987193, 0xa679438e, 0x49b40821,
		0xf61e2562, 0xc040b340, 0x265e5a51, 0xe9b6c7aa, 0xd62f105d, 0x02441453, 0xd8a1e681, 0xe7d3fbc8,
		0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed, 0xa9e3e905, 0xfcefa3f8, 0x676f02d9, 0x8d2a4c8a,
		0xfffa3942, 0x8771f681, 0x6d9d6122, 0xfde5380c, 0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70,
		0x289b7ec6, 0xeaa127fa, 0xd4ef3085, 0x04881d05, 0xd9d4d039, 0xe6db99e5, 0x1fa27cf8, 0xc4ac5665,
		0xf4292244, 0x432aff97, 0xab9423a7, 0xfc93a039, 0x655b59c3, 0x8f0ccc92, 0xffeff47d, 0x85845dd1,
		0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1, 0xf7537e82, 0xbd3af235, 0x2ad7d2bb, 0xeb86d391,
	}

	words: [16]u32

	for i in 0..<16 {
		words[i] = get_u32(block, i * 4)
	}

	a := state[0]
	b := state[1]
	c := state[2]
	d := state[3]

	for i in 0..<64 {
		f: u32
		word: int

		switch i / 16 {
		case 0:
			f = (b & c) | (~b & d)
			word = i

		case 1:
			f = (d & b) | (~d & c)
			word = (5 * i + 1) % 16

		case 2:
			f = b ~ c ~ d
			word = (3 * i + 5) % 16

		case 3:
			f = c ~ (b | ~d)
			word = (7 * i) % 16
		}

		f += a + sines[i] + words[word]
		a = d
		d = c
		c = b
		b += bits.rotate_left32(f, int(shifts[i]))
	}

	state[0] += a
	state[1] += b
	state[2] += c
	state[3] += d
}

dxbc_checksum :: proc(container: []u8) -> [16]u8 {
	data := container[20:]
	state := [4]u32 { 0x67452301, 0xefcdab89, 0x98badcfe, 0x10325476 }
	full_blocks := len(data) / 64

	for i in 0..<full_blocks {
		dxbc_md5_transform(&state, data[i * 64:])
	}

	rest := data[full_blocks * 64:]
	num_bits := u32(len(data)) * 8
	last_word := u32(len(data)) * 2 | 1
	block: [64]u8

	if len(rest) >= 56 {
		copy(block[:], rest)
		block[len(rest)] = 0x80
		dxbc_md5_transform(&state, block[:])
		block = {}
		set_u32(block[:], 0, num_bits)
		set_u32(block[:], 60, last_word)
		dxbc_md5_transform(&state, block[:])
	} else {
		set_u32(block[:], 0, num_bits)
		copy(block[4:], rest)
		block[4 + len(rest)] = 0x80
		set_u32(block[:], 60, last_word)
		dxbc_md5_transform(&state, block[:])
	}

	result: [16]u8

	for i in 0..<4 {
		set_u32(result[:], i * 4, state[i])
	}

	return result
}

dxbc_build_container :: proc(chunks: []Dxbc_Chunk, allocator: runtime.Allocator) -> []u8 {
	total := 32 + len(chunks) * 4

	for ch in chunks {
		total += 8 + len(ch.data)
	}

	out := make([]u8, total, allocator)
	copy(out, "DXBC")
	set_u32(out, 20, 1)
	set_u32(out, 24, u32(total))
	set_u32(out, 28, u32(len(chunks)))
	at := 32 + len(chunks) * 4

	for ch, ch_idx in chunks {
		set_u32(out, 32 + ch_idx * 4, u32(at))
		copy(out[at:], ch.fourcc)
		set_u32(out, at + 4, u32(len(ch.data)))
		copy(out[at + 8:], ch.data)
		at += 8 + len(ch.data)
	}

	sum := dxbc_checksum(out)
	copy(out[4:20], sum[:])
	return out
}
