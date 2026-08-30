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

	// True when the backend asks the mixer for samples itself, from whatever thread its own API
	// gives it, by calling `_pull_audio`. Karl2D then runs no mixer thread and
	// `update_audio_mixer` does nothing, because the backend is already driving the mixing.
	//
	// False when the backend has to be handed samples instead. Web works that way: its audio
	// worklet is a real thread but a separate JS realm, so it cannot call back into the wasm
	// module and the samples have to be pushed to it from the game loop.
	drives_itself: proc() -> bool,
}