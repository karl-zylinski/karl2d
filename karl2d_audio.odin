// The audio features of Karl2D are WIP and not ready! Don't use them yet.

package karl2d

AUDIO_MIX_SAMPLE_RATE :: 44100
AUDIO_MIX_BITRATE :: 16

AUDIO_MIX_BUFFER_NUM_SAMPLES :: 1320
AUDIO_MIX_BUFFER_LENGTH :: f32(f64(AUDIO_MIX_BUFFER_NUM_SAMPLES)/f64(AUDIO_MIX_SAMPLE_RATE)) // seconds


Audio_State :: struct {
	audio_backend: Audio_Backend_Interface,
	audio_backend_state: rawptr,
	playing_sounds: [dynamic]Playing_Sound,
	time_since_mix: f32,
	mix_buffers: [32][AUDIO_MIX_BUFFER_NUM_SAMPLES]u16,
	previous_mix_size: int,
	cur_mix_buffer: int,
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
	for idx := 0; idx < len(s.playing_sounds); idx += 1 {
		ps := &s.playing_sounds[idx]
		start := ps.offset
		ps.offset += dt
		end_t := f32(f64(len(ps.sound.data)/2) / f64(AUDIO_MIX_SAMPLE_RATE))
		done := false

		if ps.offset >= end_t {
			ps.offset = end_t
			done = true
		}

		end := ps.offset

		samp_start := int(start * AUDIO_MIX_SAMPLE_RATE)
		samp_end := int(end * AUDIO_MIX_SAMPLE_RATE)

		ab.feed_mixed_samples(slice.reinterpret([]u8, ps.sound.data[samp_start*2:samp_end*2]))

		if done {
			unordered_remove(&s.playing_sounds, idx)
			idx -= 1
		}
	}

	/*pos := ab.remaining_samples()
	log.info("pos", pos)
	remaining := s.previous_mix_size - pos
	log.info("remaining", remaining)

	if remaining > AUDIO_MIX_BUFFER_NUM_SAMPLES {
		return
	}

	to_mix := AUDIO_MIX_BUFFER_NUM_SAMPLES - remaining
	s.mix_buffers[s.cur_mix_buffer] = {}

	if len(s.playing_sounds) == 0 {
		return
	}

	for idx := 0; idx < len(s.playing_sounds); idx += 1 {
		ps := &s.playing_sounds[idx]
		start := ps.offset
		end := ps.offset + to_mix
		done := false

		if end > len(ps.sound.data) {
			end = len(ps.sound.data)
			done = true
		}

		ps.offset = end
		samples := ps.sound.data[start:end]
		copy(s.mix_buffers[s.cur_mix_buffer][:], samples)

		if done {
			unordered_remove(&s.playing_sounds, idx)
			idx -= 1
		}
	}

	ab.feed_mixed_samples(slice.reinterpret([]u8, s.mix_buffers[s.cur_mix_buffer][:to_mix]))
	s.previous_mix_size = to_mix
	log.info("to mix", to_mix)

	s.cur_mix_buffer += 1
	if s.cur_mix_buffer >= len(s.mix_buffers) {
		s.cur_mix_buffer = 0
	}*/
}

Playing_Sound :: struct {
	sound: Sound,
	offset: f32,
}

audio_shutdown :: proc() {
	free(s.audio_backend_state, s.allocator)
}

audio_set_internal_state :: proc(state: ^Audio_State) {
	s = state
}

play_sound :: proc(snd: Sound) {
	append(&s.playing_sounds, Playing_Sound { sound = snd })
}

Sound :: struct {
	data: []u16,
}
