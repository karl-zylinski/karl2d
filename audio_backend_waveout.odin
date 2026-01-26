#+build windows
#+vet explicit-allocators
#+private file
package karl2d

@(private="package")
AUDIO_BACKEND_WAVEOUT :: Audio_Backend_Interface {
	state_size = waveout_state_size,
	init = waveout_init,
	shutdown = waveout_shutdown,
	set_internal_state = waveout_set_internal_state,
}

import "base:runtime"

Waveout_State :: struct {
	allocator: runtime.Allocator,
}

waveout_state_size :: proc() -> int {
	return size_of(Waveout_State)
}

s: ^Waveout_State

waveout_init :: proc(state: rawptr, allocator: runtime.Allocator) {
	assert(state != nil)
	s = (^Waveout_State)(state)
}

waveout_shutdown :: proc() {
}

waveout_set_internal_state :: proc(state: rawptr) {
	assert(state != nil)
	s = (^Waveout_State)(state)
}