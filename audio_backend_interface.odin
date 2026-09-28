package karl2d

// Audio_Backend_State is defined per platform, in for example `audio_linux.odin`.
Audio_Backend_Interface :: struct {
	// Set up the audio backend. The backend returns the new state pointer and `true` on success. It
	// can return `nil` for the pointer but still return `true` for the bool, which is useful when
	// a backend does not have any state.
	create: proc(allocator: Allocator, loc := #caller_location) -> ^Audio_Backend_Interface,

	destroy: proc(s: ^Audio_Backend_Interface),

	// How many samples the master bus and all other buses should mix per mixing pass.
	mix_chunk_size: int,

	// If `false`, then `update_audio` will mix the audio and push it to this backend using
	// `push_samples`.
	//
	// If `true` then `update_audio` will not do any mixing and will not push any samples to the
	// backend. Instead, that backend is assumed to set up a thread that directly calls
	// `_mix_audio_into_buffer`.
	has_mixer_thread: bool,

	// These are not required when `has_mixer_thread` is true.
	push_samples: proc(s: ^Audio_Backend_Interface, samples: [][2]Audio_Sample),
	pushed_samples_remaining: proc(s: ^Audio_Backend_Interface) -> int,
}