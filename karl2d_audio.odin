// The audio features of Karl2D are WIP and not ready! Don't use them yet.

package karl2d

AUDIO_MIX_SAMPLE_RATE :: 44100
AUDIO_MIX_CHUNK_SIZE :: 1320

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
			unordered_remove(&s.playing_sounds, idx)
			idx -= 1
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

Audio_Sample :: [2]u16

Sound :: struct {
	data: []Audio_Sample,
}
