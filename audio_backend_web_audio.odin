#+build js
#+vet explicit-allocators
#+private package
package karl2d

@(rodata)
WEB_AUDIO_BACKEND_INTERFACE := Audio_Backend_Interface {
	destroy = web_audio_destroy,
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

web_audio_create :: proc(
	allocator: Allocator,
	loc := #caller_location,
) -> ^Audio_Backend_Interface {
	js_web_audio_init()
	return &WEB_AUDIO_BACKEND_INTERFACE
}

web_audio_destroy :: proc(s: ^Audio_Backend_Interface) {
	js_web_audio_shutdown()
}

web_audio_push_samples :: proc(s: ^Audio_Backend_Interface, samples: [][2]Audio_Sample) {
	// The JS backend just sees an array of f32. But it knows that they are interleaved Left & Right
	js_web_audio_push_samples(slice.reinterpret([]f32, samples))
}

web_audio_pushed_samples_remaining :: proc(s: ^Audio_Backend_Interface) -> int {
	return js_web_audio_pushed_samples_remaining()
}