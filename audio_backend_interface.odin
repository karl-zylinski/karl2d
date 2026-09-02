package karl2d

import "base:runtime"

Audio_Backend_Interface :: struct {
	state_size: proc() -> int,
	init: proc(state: rawptr, allocator: runtime.Allocator) -> bool,
	shutdown: proc(),
	set_internal_state: proc(state: rawptr),

	// If `false`, then `audio_update` will mix the audio and push it to this backend using
	// `push_samples`.
	//
	// If `true` then `audio_update` will not do any mixing and will not push any samples to the
	// backend. Instead, that backend is assumed to set up a thread that directly calls
	// `_mix_audio_into_buffer`.
	has_mixer_thread: bool,

	// These are not required when `has_mixer_thread` is true.
	push_samples: proc(samples: [][2]Audio_Sample),
	pushed_samples_remaining: proc() -> int,
}