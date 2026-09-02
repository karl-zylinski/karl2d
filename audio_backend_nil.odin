#+vet explicit-allocators
#+private file
package karl2d

@(private="package")
AUDIO_BACKEND_NIL :: Audio_Backend_Interface {
	state_size = abnil_state_size,
	init = abnil_init,
	shutdown = abnil_shutdown,
	set_internal_state = abnil_set_internal_state,
	has_mixer_thread = false,
	push_samples = abnil_push_samples,
	pushed_samples_remaining = abnil_pushed_samples_remaining,
}

import "base:runtime"
import "core:time"

Nil_State :: struct {
	start: time.Tick,
	pushed: int,
}

s: ^Nil_State

abnil_state_size :: proc() -> int {
	return size_of(Nil_State)
}

abnil_init :: proc(state: rawptr, allocator: runtime.Allocator) -> bool {
	assert(state != nil)
	s = (^Nil_State)(state)
	s.start = time.tick_now()
	return true
}

abnil_shutdown :: proc() {
}

abnil_set_internal_state :: proc(state: rawptr) {
	assert(state != nil)
	s = (^Nil_State)(state)
}

abnil_push_samples :: proc(samples: [][2]Audio_Sample) {
	s.pushed += len(samples)
}

abnil_pushed_samples_remaining :: proc() -> int {
	elapsed := int(time.duration_seconds(time.tick_since(s.start)) * AUDIO_MIX_SAMPLE_RATE)
	return max(s.pushed - elapsed, 0)
}
