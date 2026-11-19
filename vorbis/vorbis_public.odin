// This is based on stb_vorbis.c by Sean Barrett. See the LICENSE file in this folder.
package karl2d_vorbis

import "base:runtime"

MAX_CHANNELS :: 2

Decoder :: struct {
	// 1 or 2 channels (mono or stereo)
	channels: int,

	// Sample rate in Hz. Read from the file, but not used by the decoder. The user needs it to
	// convert between seconds and frames, and to know how fast to play the decoded frames.
	sample_rate: int,

	// The frame that the next call to `decode_chunk` will output. A frame is a sample in mono, or
	// two samples in stereo.
	current_frame: int,

	// `true` if `current_frame` holds a real position. `false` after a flush/seek before the
	// decoder has been able to figure out where it is.
	current_frame_valid: bool,

	using _: Decoder_Internal,
}

Error :: enum {
	None,
	Need_More_Data,
	Invalid_Stream,
	Unsupported_Stream,
}

// Try to create a new Vorbis Decoder from the contents of `data`. You can read just a bit of a file
// into `data` and run this. The error will say `Needs_More_Data` if you need to read more. When the
// creation of the decoder succeeds, then `bytes_used` tells you how many bytes of `data` that it
// ended up using.
//
// Use the returned `Decoder` with `decode_chunk`, `flush` or `seek` to control the stream.
//
// The decoder allocates memory using `allocator`. Destroy the decoder using `delete_
create_decoder :: proc(
	data: []u8,
	allocator: runtime.Allocator,
	temp_allocator: runtime.Allocator,
) -> (
	decoder: Decoder,
	bytes_used: int,
	err: Error,
) {
	return _create_decoder(data, allocator, temp_allocator)
}

// Destroy a decoder previously created with `create_decoder`.
destroy_decoder :: proc(d: ^Decoder) {
	_destroy_decoder(d)
}

// Decode a chunk of samples from `data`. If there is not enough data in `data`, then the error
// `Needs_More_Data` is returned. Upon success, the decoded samples are returned in `output`.
//
// The interleaved. For stereo sounds (`d.channels == 2`) this means that the format is L R L R etc.
// For mono sounds the samples are just M M M etc.
decode_chunk :: proc(
	d: ^Decoder,
	data: []u8,
) -> (
	bytes_used: int,
	samples: []f32,
	err: Error,
) {
	return _decode_chunk(d, data)
}

// Seek the stream to a specific target frame.
seek :: proc(
	d: ^Decoder,
	data: []u8,
	target_frame: int,
) -> (
	offset: int,
	frame: int,
) {
	return _seek(d, data, target_frame)
}

// Flushing
flush :: proc(d: ^Decoder) {
	_flush(d)
}

total_frames :: proc(data: []u8) -> int {
	return _total_frames(data)
}
