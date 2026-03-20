#+private package
#+build !js
package karl2d

import stbv "vendor:stb/vorbis"
import hm "core:container/handle_map"
import "core:os"
import "log"
import "base:runtime"
import "core:mem"

Audio_Stream_Manager :: struct {
	streams: hm.Dynamic_Handle_Map(Audio_Stream_Data, Audio_Stream),
	vorbis_alloc: stbv.vorbis_alloc,
	allocator: runtime.Allocator,

	// A pointer to the `audio_buffers` map in `State`.
	buffers: ^hm.Dynamic_Handle_Map(Audio_Buffer, Audio_Buffer_Handle),

	// A pointer to the `playing_audio_buffers` map in `State`.
	playing_buffers: ^hm.Dynamic_Handle_Map(Playing_Audio_Buffer, Playing_Audio_Buffer_Handle),
}

audio_stream_init_manager :: proc(
	as: ^Audio_Stream_Manager,
	buffers: ^hm.Dynamic_Handle_Map(Audio_Buffer, Audio_Buffer_Handle),
	playing_buffers: ^hm.Dynamic_Handle_Map(Playing_Audio_Buffer, Playing_Audio_Buffer_Handle),
	allocator: runtime.Allocator,
) {
	VORBIS_STATE_SIZE :: 500 * mem.Kilobyte
	as.vorbis_alloc = {
		alloc_buffer = make([^]u8, VORBIS_STATE_SIZE, allocator),
		alloc_buffer_length_in_bytes = VORBIS_STATE_SIZE,
	}

	hm.dynamic_init(&as.streams, allocator)
	as.buffers = buffers
	as.playing_buffers = playing_buffers
	as.allocator = allocator
}

audio_stream_destroy_manager :: proc(as: ^Audio_Stream_Manager) {
	streams_iter := hm.iterator_make(&as.streams)

	for _, h in hm.iterate(&streams_iter) {
		audio_stream_destroy(as, h)
	}

	hm.dynamic_destroy(&as.streams)
	free(as.vorbis_alloc.alloc_buffer, as.allocator)
}

audio_stream_load_from_file :: proc(as: ^Audio_Stream_Manager, filename: string) -> Audio_Stream {
	f, f_err := os.open(filename)

	if f_err != nil {
		log.errorf("Failed opening file %v. Error: %v", filename, f_err)
		return AUDIO_STREAM_NONE
	}

	buf := make([dynamic]u8, frame_allocator)
	read_buf: [256]u8
	nbytes_read, read_err := os.read(f, read_buf[:])

	if read_err != nil {
		log.errorf("Failed reading from audio stream file %v. Error: %v", filename, read_err)

		if close_err := os.close(f); close_err != nil {
			log.errorf("Failed closing file. Error: %v", close_err)
		}
		
		return AUDIO_STREAM_NONE
	}

	append(&buf, ..read_buf[:nbytes_read])
	vorbis_res: ^stbv.vorbis

	for {
		vorbis_err: stbv.Error
		consumed: i32
		vorbis := stbv.open_pushdata(
			raw_data(buf),
			i32(len(buf)),
			&consumed,
			&vorbis_err,
			&as.vorbis_alloc,
		)

		if vorbis_err == nil {
			vorbis_res = vorbis
			os.seek(f, i64(consumed), .Start)
			break
		} else if vorbis_err == .need_more_data {
			nbytes_read, read_err = os.read(f, read_buf[:])

			if read_err != nil {
				log.errorf("Failed reading from audio stream file %v. Error: %v", filename, read_err)
				
				if close_err := os.close(f); close_err != nil {
					log.errorf("Failed closing file. Error: %v", close_err)
				}
				
				return AUDIO_STREAM_NONE
			}

			if nbytes_read == 0 {
				log.errorf("Failed to load audio stream. Reached end of file before stream could be loaded.")

				if close_err := os.close(f); close_err != nil {
					log.errorf("Failed closing file. Error: %v", close_err)
				}
				
				return AUDIO_STREAM_NONE
			}

			append(&buf, ..read_buf[:nbytes_read])
		} else {
			log.errorf("Failed to load audio stream. Error: %v", vorbis_err)

			if close_err := os.close(f); close_err != nil {
				log.errorf("Failed closing file. Error: %v", close_err)
			}
			
			return AUDIO_STREAM_NONE
		}
	}

	info := stbv.get_info(vorbis_res)

	channels: Audio_Channels

	if info.channels == 1 {
		channels = Audio_Channels.Mono
	} else if info.channels == 2 {
		channels = Audio_Channels.Stereo
	} else{
		log.errorf("Unsupported number of channels: %v", info.channels)

		if close_err := os.close(f); close_err != nil {
			log.errorf("Failed closing file. Error: %v", close_err)
		}
		
		return AUDIO_STREAM_NONE
	}

	buffer := Audio_Buffer {
		sample_rate = int(info.sample_rate),
		samples = make([]Audio_Sample, AUDIO_STREAM_BUFFER_SIZE, as.allocator),
		references = 1,
		channels = channels,
	}

	buffer_handle, buffer_handle_add_err := hm.add(as.buffers, buffer)

	if buffer_handle_add_err != nil {
		log.errorf("Failed to load audio stream. Error: %v", buffer_handle_add_err)
		
		if close_err := os.close(f); close_err != nil {
			log.errorf("Failed closing file. Error: %v", close_err)
		}

		delete(buffer.samples, as.allocator)
		return AUDIO_STREAM_NONE
	}

	asd := Audio_Stream_Data {
		file = f,
		vorbis = vorbis_res,
		buffer_handle = buffer_handle,
		playback_settings = {
			pan = 0,
			volume = 1,
			pitch = 1,
		},
		read_buf = make([dynamic]u8, as.allocator),
	}

	stream, stream_add_err := hm.add(&as.streams, asd)

	if stream_add_err != nil {
		log.errorf("Failed to create audio stream from file. Error: %v", stream_add_err)
		os.close(asd.file)
		delete(asd.read_buf)
		delete(buffer.samples, as.allocator)
		hm.remove(as.buffers, buffer_handle)
		return AUDIO_STREAM_NONE
	}

	return stream
}

audio_stream_destroy :: proc(as: ^Audio_Stream_Manager, stream: Audio_Stream) {
	sd := hm.get(&as.streams, stream)

	if sd == nil {
		log.error("Trying to destroy invalid audio stream. It may already be destroyed, or the handle may be invalid.")
		return
	}

	if playing := hm.get(as.playing_buffers, sd.playing_buffer_handle); playing != nil {
		hm.remove(as.playing_buffers, sd.playing_buffer_handle)
	}

	if ab := hm.get(as.buffers, sd.buffer_handle); ab != nil {
		ab.references -= 1

		if ab.references == 0 {
			delete(ab.samples, as.allocator)
			hm.remove(as.buffers, sd.buffer_handle)
		}
	}

	os.close(sd.file)
	hm.remove(&as.streams, stream)
	delete(sd.read_buf)
}

audio_stream_play :: proc(as: ^Audio_Stream_Manager, stream: Audio_Stream, loop: bool) {
	sd := hm.get(&as.streams, stream)

	if sd == nil {
		log.error("Cannot play audio stream, stream does not exist.")
		return
	}

	if existing := hm.get(as.playing_buffers, sd.playing_buffer_handle); existing != nil {
		audio_stream_stop(as, stream)
	}

	playing_audio_buffer := Playing_Audio_Buffer {
		audio_buffer = sd.buffer_handle,
		target_settings = sd.playback_settings,
		current_settings = sd.playback_settings,

		// This means that we are looping the buffer itself. We will use this buffer as a circular
		// buffer, filling it with samples as we stream in more. Thus it needs to be looped to not
		// stop when the end of the circular buffer is reached.
		loop = true,
	}

	add_err: runtime.Allocator_Error
	sd.playing_buffer_handle, add_err = hm.add(as.playing_buffers, playing_audio_buffer)

	if add_err != nil {
		log.errorf("Failed adding audio stream's buffer to list of playing audio buffers. Error: %v", add_err)
	}

	sd.loop = loop
}

audio_stream_pause :: proc(as: ^Audio_Stream_Manager, stream: Audio_Stream) {
	sd := hm.get(&as.streams, stream)

	if sd == nil {
		log.error("Cannot pause audio stream, stream does not exist.")
		return
	}

	if existing := hm.get(as.playing_buffers, sd.playing_buffer_handle); existing != nil {
		hm.remove(as.playing_buffers, sd.playing_buffer_handle)
	}

	sd.playing_buffer_handle = PLAYING_AUDIO_BUFFER_NONE
}

audio_stream_stop :: proc(as: ^Audio_Stream_Manager, stream: Audio_Stream) {
	sd := hm.get(&as.streams, stream)

	if sd == nil {
		log.error("Cannot stop audio stream, stream does not exist.")
		return
	}

	if existing := hm.get(as.playing_buffers, sd.playing_buffer_handle); existing != nil {
		hm.remove(as.playing_buffers, sd.playing_buffer_handle)
	}

	sd.playing_buffer_handle = PLAYING_AUDIO_BUFFER_NONE
	sd.buffer_write_pos = 0
	os.seek(sd.file, 0, .Start)
	runtime.clear(&sd.read_buf)
	sd.read_buf_offset = 0
	stbv.flush_pushdata(sd.vorbis)
}

audio_stream_set_volume :: proc(as: ^Audio_Stream_Manager, stream: Audio_Stream, volume: f32) {
	sd := hm.get(&as.streams, stream)
	
	if sd == nil {
		log.error("Cannot set audio stream volume, stream does not exist.")
		return
	}

	clamped_volume := clamp(volume, 0, 1)

	if playing := hm.get(as.playing_buffers, sd.playing_buffer_handle); playing != nil {
		playing.target_settings.volume = clamped_volume
	}
	
	sd.playback_settings.volume = clamped_volume
}

audio_stream_set_pan :: proc(as: ^Audio_Stream_Manager, stream: Audio_Stream, pan: f32) {
	sd := hm.get(&as.streams, stream)
	
	if sd == nil {
		log.error("Cannot set audio stream pan, stream does not exist.")
		return
	}

	clamped_pan := clamp(pan, -1, 1)

	if playing := hm.get(as.playing_buffers, sd.playing_buffer_handle); playing != nil {
		playing.target_settings.pan = clamped_pan
	}

	sd.playback_settings.pan = clamped_pan
}

audio_stream_set_pitch :: proc(as: ^Audio_Stream_Manager, stream: Audio_Stream, pitch: f32) {
	sd := hm.get(&as.streams, stream)
	
	if sd == nil {
		log.error("Cannot set audio stream pitch, stream does not exist.")
		return
	}

	capped_pitch := max(pitch, 0.01)

	if playing := hm.get(as.playing_buffers, sd.playing_buffer_handle); playing != nil {
		playing.target_settings.pitch = capped_pitch
	}
	
	sd.playback_settings.pitch = capped_pitch
}

audio_stream_update :: proc(as: ^Audio_Stream_Manager, stream: Audio_Stream) {
	sd := hm.get(&as.streams, stream)

	if sd == nil {
		log.error("Trying to update destroyed audio stream")
		return
	}

	pab := hm.get(as.playing_buffers, sd.playing_buffer_handle)

	if pab == nil {
		// Don't log an error here: Not playing the stream is a valid state. It just doesn't need
		// any updating.
		return
	}

	ab := hm.get(as.buffers, pab.audio_buffer)

	if ab == nil {
		hm.remove(as.playing_buffers, sd.playing_buffer_handle)
		log.error("Trying to update audio stream with destroyed buffer")
		return
	}

	remaining :: proc(as: ^Audio_Stream_Data, pab: ^Playing_Audio_Buffer, ab: ^Audio_Buffer) -> int {
		remaining := as.buffer_write_pos - pab.offset 

		if remaining < 0 {
			remaining = len(ab.samples) - pab.offset + as.buffer_write_pos 
		}

		return remaining
	}

	for remaining(sd, pab, ab) < AUDIO_STREAM_BUFFER_SIZE / 2 {
		channels: i32
		samples: i32
		output: [^]^f32

		bytes_used := stbv.decode_frame_pushdata(
			sd.vorbis,
			raw_data(sd.read_buf[sd.read_buf_offset:]),
			i32(len(sd.read_buf) - sd.read_buf_offset),
			&channels,
			&output, 
			&samples,
		)

		if bytes_used == 0 && samples == 0 {
			read_buf_size := len(sd.read_buf)
			non_zero_resize(&sd.read_buf, read_buf_size + 256)
			read, read_err := os.read(sd.file, sd.read_buf[read_buf_size:read_buf_size+256])

			if read > 0 {
				shrink(&sd.read_buf, read_buf_size + read)
			}

			if read_err != nil {
				if read_err == .EOF {
					if sd.loop {
						os.seek(sd.file, 0, .Start)
						stbv.flush_pushdata(sd.vorbis)
						continue
					} else {
						audio_stream_stop(as, stream)
						break
					}
				} else {
					hm.remove(as.playing_buffers, sd.playing_buffer_handle)
					log.errorf("Failed reading from audio stream file. Error: %v", read_err)
					break
				}
			}
		} else if bytes_used > 0 && samples == 0 {
			sd.read_buf_offset += int(bytes_used)
		} else if bytes_used > 0 && samples > 0 {
			if channels == 1 {
				mono: [^]f32 = output[0]

				for samp_idx in 0..<samples {
					ab.samples[sd.buffer_write_pos] = mono[samp_idx]
					sd.buffer_write_pos = (sd.buffer_write_pos + 1) % len(ab.samples)
				}
			} else if channels == 2 {
				left: [^]f32 = output[0]
				right: [^]f32 = output[1]

				for samp_idx in 0..<samples {
					ab.samples[sd.buffer_write_pos] = left[samp_idx]
					ab.samples[sd.buffer_write_pos + 1] = right[samp_idx]
					sd.buffer_write_pos = (sd.buffer_write_pos + 2) % len(ab.samples)
				}
			} else {
				hm.remove(as.playing_buffers, sd.playing_buffer_handle)
				log.error("Invalid num channels")
				break
			}
			sd.read_buf_offset += int(bytes_used)
		} else {
			hm.remove(as.playing_buffers, sd.playing_buffer_handle)
			log.error("Invalid vorbis")
			break
		}
	}

	if len(sd.read_buf) > 0 {
		// We didn't consume all the data in the read buffer. Move the remaining data to the start
		// of the buffer so that it can be consumed in the next update.
		copy(sd.read_buf[:], sd.read_buf[sd.read_buf_offset:])
		shrink(&sd.read_buf, len(sd.read_buf) - sd.read_buf_offset)
		sd.read_buf_offset = 0
	}
}

Audio_Stream_Data :: struct {
	handle: Audio_Stream,
	file: ^os.File,
	buffer_write_pos: int,
	vorbis: ^stbv.vorbis,
	read_buf: [dynamic]u8,
	read_buf_offset: int,
	playing_buffer_handle: Playing_Audio_Buffer_Handle,
	buffer_handle: Audio_Buffer_Handle,
	playback_settings: Audio_Buffer_Playback_Settings,

	// Different from `loop` in `Playing_Audio_Buffer`. This says if the whole stream should loop
	// when it reaches end-of-file. The `loop` in `Playing_Audio_Buffer` just says to loop the
	// buffer itself. That's something you always want for a stream: We are continously writing
	// data from a file into a small buffer that is a few seconds long.
	loop: bool,
}