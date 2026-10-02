package karl2d

Audio_Backend_State :: struct {}

Audio_Backend_Interface :: struct #all_or_none {
	// State usually has `using base_type: Audio_Backend_State` as first field.
	state_type: typeid,
	
	init: proc(s: ^Audio_Backend_State) -> bool,
	shutdown: proc(s: ^Audio_Backend_State),

	// How many samples the master bus and all other buses should mix per mixing pass.
	mix_chunk_size: int,

	// If `true` then `push_samples` and `pushed_samples_remaining` must be nil. In that case the
	// backend will use a thread that directly calls `_mix_audio_into_buffer`.
	has_mixer_thread: bool,

	// For non-threaded mixing. Karl2D will run the mixer as part of `k2.update` and push in the new
	// samples using these procs.
	push_samples: proc(s: ^Audio_Backend_State, samples: [][2]Audio_Sample),
	pushed_samples_remaining: proc(s: ^Audio_Backend_State) -> int,
}