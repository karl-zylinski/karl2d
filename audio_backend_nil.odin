#+vet explicit-allocators
#+private package
package karl2d

import "core:time"

ABNil_Interface :: Audio_Backend_Interface {
	create = abnil_create,
	destroy = abnil_destroy,
	mix_chunk_size = 700,
	has_mixer_thread = false,
	push_samples = abnil_push_samples,
	pushed_samples_remaining = abnil_pushed_samples_remaining,
}

ABNil_State :: struct {
	using interface: Audio_Backend_Interface,
	allocator: Allocator,
	start: time.Tick,
	pushed: int,
}

abnil_create :: proc(allocator: Allocator, loc := #caller_location) -> ^Audio_Backend_Interface {
	s := new(ABNil_State, allocator, loc)
	s.interface = ABNil_Interface
	s.allocator = allocator
	s.start = time.tick_now()
	return s
}

abnil_destroy :: proc(s: ^ABNil_State) {
	a := s.allocator
	free(s, a)
}

abnil_push_samples :: proc(s: ^ABNil_State, samples: [][2]Audio_Sample) {
	s.pushed += len(samples)
}

abnil_pushed_samples_remaining :: proc(s: ^ABNil_State) -> int {
	elapsed := int(time.duration_seconds(time.tick_since(s.start)) * AUDIO_MIX_SAMPLE_RATE)
	return max(s.pushed - elapsed, 0)
}
