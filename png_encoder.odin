// For encoding uncompressed PNG. Used to create cursors for web builds from `Image` structs.
#+vet explicit-allocators
#+private package

package karl2d

import "base:runtime"
import "core:encoding/endian"
import "core:hash"
import "core:slice"

encode_png :: proc(img: Image, allocator: runtime.Allocator) -> (res_data: []u8, res_ok: bool) {
	if img.width <= 0 || img.height <= 0 {
		return
	}

	if len(img.pixels) != img.width*img.height {
		return
	}

	stride := img.width*4 // 4 bytes per pixel
	row_size := 1 + stride  // 1 byte extra for PNG filter. Filter is always 0, but must be there.
	raw_size := img.height*row_size
	STORED_BLOCK_MAX :: 65535
	rows_per_block := STORED_BLOCK_MAX/row_size

	if rows_per_block == 0 {
		// This only happens for images wider than 16383 pixels, which no cursor will be.
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

	// IHDR (header)
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

	// IDAT (data)
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
