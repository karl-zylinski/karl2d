// The audio features of Karl2D are WIP and not ready! Don't use them yet.

package karl2d

AUDIO_MIX_SAMPLE_RATE :: 44100
AUDIO_MIX_CHUNK_SIZE :: 1400

Audio_State :: struct {
	audio_backend: Audio_Backend_Interface,
	audio_backend_state: rawptr,
	playing_sounds: [dynamic]Playing_Sound,
	mix_buffer: [1*mem.Megabyte]Audio_Sample,
	mix_buffer_offset: int,
	allocator: runtime.Allocator,
}

import "base:runtime"
import "core:mem"
import "log"
import "core:slice"
import "core:os"
import "core:encoding/endian"

@(private="file")
s: ^Audio_State
ab: Audio_Backend_Interface

audio_init :: proc(state: ^Audio_State, allocator: runtime.Allocator) {
	s = state
	s.audio_backend = AUDIO_BACKEND
	s.allocator = allocator
	ab = s.audio_backend

	audio_alloc_error: runtime.Allocator_Error
	s.audio_backend_state, audio_alloc_error = mem.alloc(ab.state_size(), allocator = allocator)
	log.assertf(audio_alloc_error == nil, "Failed allocating memory for audio backend: %v", audio_alloc_error)
	ab.init(s.audio_backend_state, allocator)
}

audio_update :: proc(dt: f32) {
	if ab.remaining_samples() > (3 * AUDIO_MIX_CHUNK_SIZE)/2 {
		return
	}
	
	if (s.mix_buffer_offset + AUDIO_MIX_CHUNK_SIZE) > len(s.mix_buffer) {
		s.mix_buffer_offset = 0
	}

	mix_chunk_start := s.mix_buffer_offset
	mix_chunk_end := s.mix_buffer_offset + AUDIO_MIX_CHUNK_SIZE

	// Remove old mixed data from buffer
	slice.zero(s.mix_buffer[mix_chunk_start:mix_chunk_end])

	for idx := 0; idx < len(s.playing_sounds); idx += 1 {
		ps := &s.playing_sounds[idx]
		samples_available := min(AUDIO_MIX_CHUNK_SIZE, len(ps.sound.data) - ps.offset)
	
		for samp_idx in 0..<samples_available {
			s.mix_buffer[mix_chunk_start + samp_idx] += ps.sound.data[ps.offset + samp_idx]
		}

		if ps.offset + AUDIO_MIX_CHUNK_SIZE > len(ps.sound.data) {
			if ps.sound.loop {
				extra := AUDIO_MIX_CHUNK_SIZE-samples_available
				ps.offset = 0
				for samp_idx in 0..<min(extra, len(ps.sound.data)) {
					s.mix_buffer[mix_chunk_start + samples_available + samp_idx] += ps.sound.data[ps.offset + samp_idx]
				}
				ps.offset += extra
			} else {
				unordered_remove(&s.playing_sounds, idx)
				idx -= 1
			}
		} else {
			ps.offset += AUDIO_MIX_CHUNK_SIZE
		}
	}

	out := s.mix_buffer[mix_chunk_start:mix_chunk_end]
	ab.feed(out)
	s.mix_buffer_offset += AUDIO_MIX_CHUNK_SIZE
}

Playing_Sound :: struct {
	sound: Sound,
	offset: int,
}

audio_shutdown :: proc() {
	free(s.audio_backend_state, s.allocator)
}

audio_set_internal_state :: proc(state: ^Audio_State) {
	s = state
	ab = s.audio_backend
}

play_sound :: proc(snd: Sound) {
	append(&s.playing_sounds, Playing_Sound { sound = snd })
}

load_sound_from_file :: proc(filename: string) -> Sound {
	data, data_ok := os.read_entire_file(filename)

	if !data_ok {
		log.errorf("Failed loading sound %v", filename)
		return {}
	}

	return {
		data = slice.reinterpret([]Audio_Sample, data[44:]),
	}
}


load_sound_from_memory :: proc(bytes: []byte) -> Sound {
	d := bytes

	if len(d) < 8 {
		log.error("Invalid WAV")
		return {}
	}

	if string(d[:4]) != "RIFF" {
		log.error("Invalid wav file: No RIFF identifier")
		return {}
	}

	d = d[4:]

	file_size, file_size_ok := endian.get_u32(d, .Little)

	if !file_size_ok {
		log.error("Invalid wav file: No size")
		return {}
	}

	if int(file_size) != len(bytes) - 8 {
		log.error("File size mismiatch")
		return {}
	}

	d = d[4:]

	if string(d[:4]) != "WAVE" {
		log.error("Invalid wav file: Not WAVE format")
		return {}
	}

	d = d[4:]

	Wav_Fmt :: struct {
		audio_format:    u16,
		num_channels:    u16,
		sample_rate:     u32,
		byte_per_sec:    u32, // sample_rate * byte_per_bloc
		byte_per_bloc:   u16, // (num_channels * bits_per_sample) / 8
		bits_per_sample: u16,
	}

	data: []u8

	for len(d) > 3 {
		blk_id := string(d[:4])

		d = d[4:]	

		if blk_id == "fmt " {
			blk_size, blk_size_ok := endian.get_u32(d, .Little)

			if !blk_size_ok {
				log.error("Invalid wav fmt block size")
				continue
			}

			d = d[4:]

			if int(blk_size) != 16 || len(d) < 16 {
				log.error("Invalid wav fmt block size")
				continue
			}

			audio_format, audio_format_ok := endian.get_u16(d[0:2], .Little)
			num_channels, num_channels_ok := endian.get_u16(d[2:4], .Little)
			sample_rate, sample_rate_ok := endian.get_u32(d[4:8], .Little)
			byte_per_sec, byte_per_sec_ok := endian.get_u32(d[8:12], .Little)
			byte_per_bloc, byte_per_bloc_ok := endian.get_u16(d[12:14], .Little)
			bits_per_sample, bits_per_sample_ok := endian.get_u16(d[14:16], .Little)

			if (
				!audio_format_ok ||
				!num_channels_ok ||
				!sample_rate_ok ||
				!byte_per_sec_ok ||
				!byte_per_bloc_ok ||
				!bits_per_sample_ok
			) {
				log.error("Failed reading wav fmt block")
				continue
			}

			fmt := Wav_Fmt {
				audio_format = audio_format,
				num_channels = num_channels,
				sample_rate = sample_rate,
				byte_per_sec = byte_per_sec,
				byte_per_bloc = byte_per_bloc,
				bits_per_sample = bits_per_sample,
			}

			log.info(fmt)
		} else if blk_id == "data" {
			data_size, data_size_ok := endian.get_u32(d, .Little)

			if !data_size_ok {
				log.error("Failed getting wav data size")
				continue
			}

			d = d[4:]

			if len(d) < int(data_size) {
				log.error("Data size larger than remaining wave buffer")
				continue
			}

			data = d[:data_size]
		}
	}
	
	return {
		data = slice.reinterpret([]Audio_Sample, data),
	}
}

Audio_Sample :: [2]u16

Sound :: struct {
	data: []Audio_Sample,
	loop: bool,
}
