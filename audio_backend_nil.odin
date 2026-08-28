#+vet explicit-allocators
#+private file
package karl2d

@(private="package")
AUDIO_BACKEND_NIL :: Audio_Backend_Interface {
	state_size = abnil_state_size,
	init = abnil_init,
	shutdown = abnil_shutdown,
	set_internal_state = abnil_set_internal_state,

	feed = abnil_feed,

	remaining_samples = abnil_remaining_samples,
	interrupt_feed = abnil_interrupt_feed,
	queued_samples = abnil_queued_samples,
	target_samples = abnil_target_samples,
}

import "base:runtime"

abnil_state_size :: proc() -> int {
	return 0
}

abnil_init :: proc(state: rawptr, allocator: runtime.Allocator) {
}

abnil_shutdown :: proc() {
}

abnil_set_internal_state :: proc(state: rawptr) {
}

abnil_feed :: proc(samples: [][2]Audio_Sample) {
}

abnil_remaining_samples :: proc() -> int {
	return 0
}
// `feed` never waits on this backend, so there is nothing to interrupt.
abnil_interrupt_feed :: proc() {
}


// Not measured on this backend yet. Zero leaves the mixer on its own defaults.
abnil_queued_samples :: proc() -> int {
	return 0
}

abnil_target_samples :: proc() -> int {
	return 0
}