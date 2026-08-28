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
	stop_feeding = abnil_stop_feeding,
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

// `feed` never waits on this backend, so there is nothing to stop.
abnil_stop_feeding :: proc() {
}

// This backend has no device, so it asks for nothing.
abnil_target_samples :: proc() -> int {
	return 0
}