#+vet explicit-allocators
#+private package
package karl2d

import "core:time"

ABNil_State :: struct {
	using base_type: Audio_Backend_State,
	start: time.Tick,
	pushed: int,
}

AUDIO_BACKEND_NIL :: Audio_Backend_Interface {
	state_type = ABNil_State,
	init = abnil_init,
	shutdown = abnil_shutdown,
	mix_chunk_size = 700,
	has_mixer_thread = false,
	push_samples = abnil_push_samples,
	pushed_samples_remaining = abnil_pushed_samples_remaining,
}

abnil_init :: proc(s: ^ABNil_State) -> bool {
	s.start = time.tick_now()
	return true
}

abnil_shutdown :: proc(s: ^ABNil_State) {
}

abnil_push_samples :: proc(s: ^ABNil_State, samples: [][2]Audio_Sample) {
	s.pushed += len(samples)
}

abnil_pushed_samples_remaining :: proc(s: ^ABNil_State) -> int {
	elapsed := int(time.duration_seconds(time.tick_since(s.start)) * AUDIO_MIX_SAMPLE_RATE)
	return max(s.pushed - elapsed, 0)
}
