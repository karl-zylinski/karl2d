#+vet explicit-allocators
#+private file
package karl2d

@(private="package")
AUDIO_BACKEND_NIL :: Audio_Backend_Interface {
	state_size = abnil_state_size,
	init = abnil_init,
	shutdown = abnil_shutdown,
	set_internal_state = abnil_set_internal_state,

	mixes_itself = false,
	push_samples = abnil_push_samples,

	pushed_samples_remaining = abnil_pushed_samples_remaining,
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

abnil_push_samples :: proc(samples: [][2]Audio_Sample) {
}

abnil_pushed_samples_remaining :: proc() -> int {
	return 0
}