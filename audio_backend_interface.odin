package karl2d

import "base:runtime"

Audio_Backend_Interface :: struct #all_or_none {
	state_size: proc() -> int,
	init: proc(state: rawptr, allocator: runtime.Allocator),
	shutdown: proc(),
	set_internal_state: proc(state: rawptr),

	feed: proc(samples: [][2]Audio_Sample),
	remaining_samples: proc() -> int,

	// How many samples the backend has taken but has not played yet. Together with
	// `remaining_samples` this is the audio latency. Returns 0 when the backend cannot tell.
	queued_samples: proc() -> int,

	// How many samples the mixer should try to keep fed into the backend while the mixer thread
	// runs. A backend that plays from a small buffer asks for less, which lowers latency. Returns
	// 0 to let the mixer use `AUDIO_MIXER_TARGET_SAMPLES` instead.
	target_samples: proc() -> int,
}