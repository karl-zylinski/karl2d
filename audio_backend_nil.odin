#+vet explicit-allocators
#+private file
package karl2d

@(private="package")
AUDIO_BACKEND_NIL :: Audio_Backend_Interface {
	state_size = audionil_state_size,
	init = audionil_init,
	shutdown = audionil_shutdown,
	set_internal_state = audionil_set_internal_state,
}

import "base:runtime"

audionil_state_size :: proc() -> int {
	return 0
}

audionil_init :: proc(state: rawptr, allocator: runtime.Allocator) {
}

audionil_shutdown :: proc() {
}

audionil_set_internal_state :: proc(state: rawptr) {
}