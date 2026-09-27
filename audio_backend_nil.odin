#+vet explicit-allocators
#+private package
package karl2d

@(private="package")
AUDIO_BACKEND_NIL :: Audio_Backend_Interface {
	init = abnil_init,
	shutdown = abnil_shutdown,
	mix_chunk_size = 700,
	has_mixer_thread = false,
	push_samples = abnil_push_samples,
	pushed_samples_remaining = abnil_pushed_samples_remaining,
}

import "core:time"

ABNil_State :: struct {
	allocator: Allocator,
	start: time.Tick,
	pushed: int,
}

abnil_init :: proc(
	allocator: Allocator,
	loc := #caller_location,
) -> (Audio_Backend_State, bool) {
	s := new(ABNil_State, allocator, loc)
	s.allocator = allocator
	s.start = time.tick_now()
	return (Audio_Backend_State)(s), true
}

abnil_shutdown :: proc(as: Audio_Backend_State) {
	s := (^ABNil_State)(as)
	a := s.allocator
	free(s, a)
}

abnil_push_samples :: proc(as: Audio_Backend_State, samples: [][2]Audio_Sample) {
	s := (^ABNil_State)(as)
	s.pushed += len(samples)
}

abnil_pushed_samples_remaining :: proc(as: Audio_Backend_State) -> int {
	s := (^ABNil_State)(as)
	elapsed := int(time.duration_seconds(time.tick_since(s.start)) * AUDIO_MIX_SAMPLE_RATE)
	return max(s.pushed - elapsed, 0)
}
