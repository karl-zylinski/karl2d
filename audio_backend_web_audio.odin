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
	mix_chunk_size = 1400,
	has_mixer_thread = false,
	push_samples = web_audio_push_samples,
	pushed_samples_remaining = web_audio_pushed_samples_remaining,
}

import "core:slice"

foreign import karl2d_web_audio "karl2d_web_audio"

// The `js_` prefix is there to just avoid clashes with the procs in this file.
@(default_calling_convention="contextless")
foreign karl2d_web_audio {
	@(link_name="web_audio_init")
	js_web_audio_init :: proc() ---
	@(link_name="web_audio_shutdown")
	js_web_audio_shutdown :: proc() ---
	@(link_name="web_audio_push_samples")
	js_web_audio_push_samples :: proc(samples: []f32) ---
	@(link_name="web_audio_pushed_samples_remaining")
	js_web_audio_pushed_samples_remaining :: proc() -> int ---
}

web_audio_state_size :: proc() -> int {
	return 0
}

web_audio_init :: proc(state: rawptr) -> bool {
	js_web_audio_init()
	return true
}

web_audio_shutdown :: proc() {
	js_web_audio_shutdown()
}

web_audio_set_internal_state :: proc(state: rawptr) {
	// No hot reload on web.
}

web_audio_push_samples :: proc(samples: [][2]Audio_Sample) {
	// The JS backend just sees an array of f32. But it knows that they are interleaved Left & Right
	js_web_audio_push_samples(slice.reinterpret([]f32, samples))
}

web_audio_pushed_samples_remaining :: proc() -> int {
	return js_web_audio_pushed_samples_remaining()
}