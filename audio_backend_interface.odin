package karl2d

I_Audio_Backend :: struct #all_or_none {
	init: proc(s: ^I_Audio_Backend) -> bool,
	shutdown: proc(s: ^I_Audio_Backend),

	// How many samples the master bus and all other buses should mix per mixing pass.
	mix_chunk_size: int,

	// If `true` then `push_samples` and `pushed_samples_remaining` must be nil. In that case the
	// backend will use a thread that directly calls `_mix_audio_into_buffer`.
	has_mixer_thread: bool,

	// For non-threaded mixing. Karl2D will run the mixer as part of `k2.update` and push in the new
	// samples using these procs.
	push_samples: proc(s: ^I_Audio_Backend, samples: [][2]Audio_Sample),
	pushed_samples_remaining: proc(s: ^I_Audio_Backend) -> int,
}