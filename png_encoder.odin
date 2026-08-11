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
@(private="package")
encode_png :: proc(img: Image, allocator: runtime.Allocator) -> (data: []u8, ok: bool) {
	if img.width <= 0 || img.height <= 0 {
		return nil, false
	}

	if len(img.pixels) != img.width*img.height {
		return nil, false
	}

	stride := img.width*4

	// A PNG scanline is one filter-type byte followed by that row's pixel bytes.
	row_size := 1 + stride
	raw_size := img.height*row_size

	STORED_BLOCK_MAX :: 65535

	// Each stored block holds whole scanlines. That puts the block boundaries on row boundaries, so
	// we can write rows straight into the output with no scratch buffer.
	rows_per_block := STORED_BLOCK_MAX/row_size

	if rows_per_block == 0 {
		// A single scanline does not fit in a stored block, so it would have to be split across
		// blocks. Only images wider than 16383 pixels hit this, which no cursor is.
		return nil, false
	}

	num_blocks := (img.height + rows_per_block - 1)/rows_per_block

	// zlib stream = 2-byte header + stored deflate blocks + 4-byte big-endian Adler-32 of the
	// scanline data.
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

		// Adler-32 is over the scanline data, which is not contiguous in `out` because a block
		// header sits between each run of rows. It is chained a block at a time instead: the seed
		// is the running state, so feeding the blocks in order matches hashing the whole thing.
		adler := u32(1)
		row := 0

		for row < img.height {
			block_rows := min(rows_per_block, img.height - row)
			block_size := block_rows*row_size
			is_final := row + block_rows >= img.height

			out[pos] = is_final ? 1 : 0 // BFINAL in bit 0, BTYPE (00 = stored) in bits 1-2
			pos += 1

			len16 := u16(block_size)
			endian.put_u16(out[pos:], .Little, len16)
			pos += 2
			endian.put_u16(out[pos:], .Little, ~len16)
			pos += 2

			block_start := pos

			for _ in 0..<block_rows {
				out[pos] = 0 // filter type: none
				pos += 1

				row_pixels := img.pixels[row*img.width:(row + 1)*img.width]
				copy(out[pos:], slice.reinterpret([]u8, row_pixels))
				pos += stride

				row += 1
			}

			adler = hash.adler32(out[block_start:pos], adler)
		}

		endian.put_u32(out[pos:], .Big, adler)
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
