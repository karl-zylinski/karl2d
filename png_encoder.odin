#+vet explicit-allocators

package karl2d

import "base:runtime"
import "core:encoding/endian"
import "core:hash"
import "core:slice"

// Encodes an image as an uncompressed PNG, i.e. one whose deflate stream is made up entirely of
// "stored" (no compression) blocks. core:image/png can only decode PNGs, not encode them, and
// core:compress only implements inflate, not deflate, so there is no PNG encoder available in
// Odin's core library. This exists to give the web backend something to hand the browser's
// `cursor` CSS property as a data URI.
//
// The files produced are much larger than a real PNG encoder would make (there is no
// compression), but every browser decodes them fine, which is the only thing this needs to do.
@(private = "package")
encode_png :: proc(img: Image, allocator: runtime.Allocator) -> (data: []u8, ok: bool) {
	if img.width <= 0 || img.height <= 0 {
		return nil, false
	}

	if len(img.pixels) != img.width*img.height {
		return nil, false
	}

	stride := img.width*4
	raw_size := img.height*(1 + stride)

	STORED_BLOCK_MAX :: 65535
	num_blocks := (raw_size + STORED_BLOCK_MAX - 1)/STORED_BLOCK_MAX

	// Lay out the raw scanline data (one filter byte per row, then that row's RGBA bytes) in a
	// scratch buffer first. It has to exist contiguously before we can compute its Adler-32, and
	// splitting it into stored-block chunks below is easier done as a second pass over it.
	raw := make([]u8, raw_size, allocator)
	defer delete(raw, allocator)

	row_pos := 0
	for y in 0 ..< img.height {
		raw[row_pos] = 0 // filter type: none
		row_pos += 1

		row_pixels := img.pixels[y*img.width:(y + 1)*img.width]
		copy(raw[row_pos:], slice.reinterpret([]u8, row_pixels))
		row_pos += stride
	}

	// zlib stream = 2-byte header + stored deflate blocks + 4-byte big-endian Adler-32 of `raw`.
	idat_data_len := 2 + num_blocks*5 + raw_size + 4
	idat_chunk_len := 4 + 4 + idat_data_len + 4

	SIGNATURE_LEN :: 8
	IHDR_CHUNK_LEN :: 4 + 4 + 13 + 4
	IEND_CHUNK_LEN :: 4 + 4 + 0 + 4

	total_size := SIGNATURE_LEN + IHDR_CHUNK_LEN + idat_chunk_len + IEND_CHUNK_LEN

	out := make([]u8, total_size, allocator)
	pos := 0

	copy(out[pos:], []u8{0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A})
	pos += SIGNATURE_LEN

	// IHDR
	{
		endian.put_u32(out[pos:], .Big, 13)
		pos += 4

		crc_start := pos
		copy(out[pos:], []u8{'I', 'H', 'D', 'R'})
		pos += 4

		endian.put_u32(out[pos:], .Big, u32(img.width))
		pos += 4
		endian.put_u32(out[pos:], .Big, u32(img.height))
		pos += 4

		out[pos] = 8 // bit depth
		pos += 1
		out[pos] = 6 // color type: truecolor with alpha (RGBA)
		pos += 1
		out[pos] = 0 // compression method: deflate (the only one PNG defines)
		pos += 1
		out[pos] = 0 // filter method: adaptive (the only one PNG defines)
		pos += 1
		out[pos] = 0 // interlace method: none
		pos += 1

		endian.put_u32(out[pos:], .Big, hash.crc32(out[crc_start:pos]))
		pos += 4
	}

	// IDAT
	{
		endian.put_u32(out[pos:], .Big, u32(idat_data_len))
		pos += 4

		crc_start := pos
		copy(out[pos:], []u8{'I', 'D', 'A', 'T'})
		pos += 4

		// zlib header: CMF=0x78 (deflate, 32K window), FLG=0x01 (no preset dictionary, chosen so
		// that CMF*256 + FLG is a multiple of 31, as the zlib format requires).
		out[pos] = 0x78
		out[pos + 1] = 0x01
		pos += 2

		offset := 0
		for offset < raw_size {
			remaining := raw_size - offset
			block_size := min(remaining, STORED_BLOCK_MAX)
			is_final := offset + block_size >= raw_size

			out[pos] = is_final ? 1 : 0 // BFINAL in bit 0, BTYPE (00 = stored) in bits 1-2
			pos += 1

			len16 := u16(block_size)
			endian.put_u16(out[pos:], .Little, len16)
			pos += 2
			endian.put_u16(out[pos:], .Little, ~len16)
			pos += 2

			copy(out[pos:], raw[offset:offset + block_size])
			pos += block_size

			offset += block_size
		}

		endian.put_u32(out[pos:], .Big, hash.adler32(raw))
		pos += 4

		endian.put_u32(out[pos:], .Big, hash.crc32(out[crc_start:pos]))
		pos += 4
	}

	// IEND
	{
		endian.put_u32(out[pos:], .Big, 0)
		pos += 4

		crc_start := pos
		copy(out[pos:], []u8{'I', 'E', 'N', 'D'})
		pos += 4

		endian.put_u32(out[pos:], .Big, hash.crc32(out[crc_start:pos]))
		pos += 4
	}

	return out, true
}
