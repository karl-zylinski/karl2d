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

import "base:runtime"
import "core:slice"

foreign import karl2d_web_audio "karl2d_web_audio"

// The `js_` prefix is there to just avoid clashes with the procs in this file.
@(default_calling_convention="contextless")
foreign karl2d_web_audio {
	@(link_name="web_audio_init")
	js_web_audio_init :: proc() ---
	@(link_name="web_audio_shutdown")
	js_web_audio_shutdown :: proc() ---
	@(link_name="web_audio_feed")
	js_web_audio_feed :: proc(samples: []f32) ---
	@(link_name="web_audio_remaining_samples")
	js_web_audio_remaining_samples :: proc() -> int ---
}

web_audio_state_size :: proc() -> int {
	return 0
}

web_audio_init :: proc(state: rawptr, allocator: runtime.Allocator) {
	js_web_audio_init()
}

web_audio_shutdown :: proc() {
	js_web_audio_shutdown()
}

web_audio_set_internal_state :: proc(state: rawptr) {
	// No hot reload on web.
}

web_audio_feed :: proc(samples: []Audio_Sample) {
	// The JS backend just sees an array of f32. But it knows that they are interleaved Left & Right
	js_web_audio_feed(slice.reinterpret([]f32, samples))
}

web_audio_remaining_samples :: proc() -> int {
	return js_web_audio_remaining_samples()
}