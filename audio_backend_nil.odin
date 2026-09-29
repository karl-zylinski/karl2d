#+vet explicit-allocators
#+private package
package karl2d

import "core:time"

Audio_Backend_Nil :: struct {
	using interface: I_Audio_Backend,
	start: time.Tick,
	pushed: int,
}

AUDIO_BACKEND_NIL_PROTOTYPE :: Audio_Backend_Nil {
	interface = {
		init = abnil_init,
		shutdown = abnil_shutdown,
		mix_chunk_size = 700,
		has_mixer_thread = false,
		push_samples = abnil_push_samples,
		pushed_samples_remaining = abnil_pushed_samples_remaining,
	},
}

abnil_init :: proc(s: ^Audio_Backend_Nil) -> bool {
	s.start = time.tick_now()
	return true
}

abnil_shutdown :: proc(s: ^Audio_Backend_Nil) {
}

abnil_push_samples :: proc(s: ^Audio_Backend_Nil, samples: [][2]Audio_Sample) {
	s.pushed += len(samples)
}

abnil_pushed_samples_remaining :: proc(s: ^Audio_Backend_Nil) -> int {
	elapsed := int(time.duration_seconds(time.tick_since(s.start)) * AUDIO_MIX_SAMPLE_RATE)
	return max(s.pushed - elapsed, 0)
}
