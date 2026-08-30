package karl2d

import "base:runtime"

Audio_Backend_Interface :: struct #all_or_none {
	state_size: proc() -> int,
	init: proc(state: rawptr, allocator: runtime.Allocator),
	shutdown: proc(),
	set_internal_state: proc(state: rawptr),

	// True when the backend runs the mixer itself. It owns a thread, and that thread calls
	// `_mix_audio` to fill whatever buffer the device is about to play. Karl2D then runs no thread
	// of its own, and `feed` and `remaining_samples` are never used.
	//
	// False when the backend has to be handed samples instead. `update_audio_mixer` mixes them on
	// the thread that calls it. Web works that way: its audio worklet is a real thread, but it is
	// a separate JS realm and cannot call back into the wasm module.
	mixes_itself: bool,

	// Only used when `mixes_itself` is false.
	feed: proc(samples: [][2]Audio_Sample),
	remaining_samples: proc() -> int,
}