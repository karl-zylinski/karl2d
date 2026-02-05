#+build js
#+vet explicit-allocators
#+private file
package karl2d

@(private="package")
AUDIO_BACKEND_WEB_AUDIO :: Audio_Backend_Interface {
	state_size = web_audio_state_size,
	init = web_audio_init,
	shutdown = web_audio_shutdown,
	set_internal_state = web_audio_set_internal_state,

	feed = web_audio_feed,

remaining_samples = web_audio_remaining_samples,
}

foreign import karl2d_web_audio "karl2d_web_audio"

@(default_calling_convention="contextless")
foreign karl2d_web_audio {
	_web_audio_init :: proc() ---
}

import "base:runtime"

web_audio_state_size :: proc() -> int {
	return 0
}

web_audio_init :: proc(state: rawptr, allocator: runtime.Allocator) {
	_web_audio_init()
}

web_audio_shutdown :: proc() {
}

web_audio_set_internal_state :: proc(state: rawptr) {
}

web_audio_feed :: proc(samples: []Audio_Sample) {
}

web_audio_remaining_samples :: proc() -> int {
	return 0
}