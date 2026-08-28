package karl2d

import "base:runtime"

Audio_Backend_Interface :: struct #all_or_none {
	state_size: proc() -> int,
	init: proc(state: rawptr, allocator: runtime.Allocator),
	shutdown: proc(),
	set_internal_state: proc(state: rawptr),

	feed: proc(samples: [][2]Audio_Sample),
	remaining_samples: proc() -> int,

	// Stops `feed` from waiting for the device. Karl2D calls this before it joins the mixer thread.
	// A device that stopped taking samples would otherwise keep that thread inside `feed`.
	stop_feeding: proc(),

	// How many samples the backend wants the mixer to keep queued in it. A backend with a small
	// device buffer wants fewer, which lowers latency. Return 0 to use `AUDIO_MIXER_TARGET_SAMPLES`.
	target_samples: proc() -> int,
}