package karl2d

import "base:runtime"

Audio_Backend_Interface :: struct {
	state_size: proc() -> int,
	init: proc(state: rawptr, allocator: runtime.Allocator),
	shutdown: proc(),
	set_internal_state: proc(state: rawptr),

	// If true, then `update_audio_mixer` will not do any mixing. Instead, the backend is assumed to
	// have a thread of its own that calls `_mix_audio_into_buffer`.
	mixes_itself: bool,

	// These are not required when `mixes_itself` is true.
	push_samples: proc(samples: [][2]Audio_Sample),
	pushed_samples_remaining: proc() -> int,
}