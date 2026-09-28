package karl2d

// Audio_Backend_State is defined per platform, in for example `audio_linux.odin`.
Audio_Backend_Interface :: struct {
	destroy: proc(s: ^Audio_Backend_Interface),

	// How many samples the master bus and all other buses should mix per mixing pass.
	mix_chunk_size: int,

	// If `true` then `start_mixer_thread` must be non-nil.
	//
	// If `false` then `push_samples` and `pushed_samples_remaining` must be non-nil.
	has_mixer_thread: bool,

	start_mixer_thread: proc(s: ^Audio_Backend_Interface),

	// For non-threaded mixing. Karl2D will run the mixer as part of `k2.update` and push in the new
	// samples using these procs.
	push_samples: proc(s: ^Audio_Backend_Interface, samples: [][2]Audio_Sample),
	pushed_samples_remaining: proc(s: ^Audio_Backend_Interface) -> int,
}