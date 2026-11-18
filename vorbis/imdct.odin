#+private package
package karl2d_vorbis

import "base:intrinsics"
import "base:runtime"
import "core:math"
import "core:simd"

U32x4 :: #simd[4]u32

SIGN :: 0x80000000

Imdct_Tables :: struct {
	pre: []f32,
	post: []f32,
	positions: []u16,
	fft_twiddles: []f32,
}

load :: #force_inline proc(p: [^]f32, i: int) -> F32x4 #no_bounds_check {
	return intrinsics.unaligned_load((^F32x4)(&p[i]))
}

store :: #force_inline proc(p: [^]f32, i: int, v: F32x4) #no_bounds_check {
	intrinsics.unaligned_store((^F32x4)(&p[i]), v)
}

flip :: #force_inline proc(v: F32x4, mask: U32x4) -> F32x4 {
	return transmute(F32x4)simd.bit_xor(transmute(U32x4)v, mask)
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
	t: Imdct_Tables
	t.pre = make([]f32, q * 2, allocator)
	t.post = make([]f32, q * 2, allocator)
	t.positions = make([]u16, q, allocator)
	t.fft_twiddles = make([]f32, q * 3, allocator)

	for k in 0..<q {
		slot := k / 4 * 8 + k % 4
		pre_angle := math.PI * f64(4 * k + 1) / f64(4 * m)
		post_angle := math.PI * f64(k) / f64(m)
		t.pre[slot] = f32(math.cos(pre_angle))
		t.pre[slot + 4] = f32(math.sin(pre_angle))
		t.post[slot] = f32(math.cos(post_angle))
		t.post[slot + 4] = f32(math.sin(post_angle))
	}

	for natural in 0..<q {
		group := natural - natural % 16
		position := group + 4 * (natural % 4) + natural % 16 / 4
		t.positions[output_index(natural, q, radix_2)] = u16(position)
	}

	length := q
	w := 0

	if radix_2 {
		for j in 0..<length / 2 {
			angle := 2 * math.PI * f64(j) / f64(length)
			slot := w + j / 4 * 8 + j % 4
			t.fft_twiddles[slot] = f32(math.cos(angle))
			t.fft_twiddles[slot + 4] = f32(-math.sin(angle))
		}

		w += length
		length /= 2
	}

	for length >= 16 {
		for j in 0..<length / 4 {
			for power in 1..=3 {
				angle := 2 * math.PI * f64(j * power) / f64(length)
				slot := w + j / 4 * 24 + (power - 1) * 8 + j % 4
				t.fft_twiddles[slot] = f32(math.cos(angle))
				t.fft_twiddles[slot + 4] = f32(-math.sin(angle))
			}
		}

		w += length / 4 * 6
		length /= 4
	}

	return t
}

inverse_mdct :: proc(d: ^Decoder, buffer: [^]f32, n: int, blocktype: int) #no_bounds_check {
	gather :: #force_inline proc(p: [^]f32, positions: [^]u16) -> F32x4 #no_bounds_check {
		return { p[positions[0]], p[positions[1]], p[positions[2]], p[positions[3]] }
	}

	t := &d.imdct_tables[blocktype]
	m := n / 2
	q := n / 4
	re := raw_data(d.imdct_scratch)
	im := re[q:]
	pre := raw_data(t.pre)

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
	twiddles := raw_data(t.fft_twiddles)

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

	post := raw_data(t.post)
	positions := raw_data(t.positions)
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
		store(buffer, m + m / 2 + 2 * k, simd.shuffle(negative_re_front, im_back, 0, 7, 1, 6))
		store(buffer, m + m / 2 + 2 * k + 4, simd.shuffle(negative_re_front, im_back, 2, 5, 3, 4))
		store(buffer, m + m / 2 - 8 - 2 * k, simd.shuffle(im_back, negative_re_front, 0, 7, 1, 6))
		store(buffer, m + m / 2 - 4 - 2 * k, simd.shuffle(im_back, negative_re_front, 2, 5, 3, 4))
		store(buffer, m / 2 - 8 - 2 * k, simd.shuffle(re_back, negative_im_front, 0, 7, 1, 6))
		store(buffer, m / 2 - 4 - 2 * k, simd.shuffle(re_back, negative_im_front, 2, 5, 3, 4))
		store(buffer, m / 2 + 2 * k, simd.shuffle(im_front, negative_re_back, 0, 7, 1, 6))
		store(buffer, m / 2 + 2 * k + 4, simd.shuffle(im_front, negative_re_back, 2, 5, 3, 4))
	}
}
