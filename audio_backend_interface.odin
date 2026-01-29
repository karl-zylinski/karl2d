package karl2d

import "base:runtime"

Audio_Backend_Interface :: struct #all_or_none {
	state_size: proc() -> int,
	init: proc(state: rawptr, allocator: runtime.Allocator),
	shutdown: proc(),
	set_internal_state: proc(state: rawptr),

	feed_mixed_samples: proc(samples: []u8),
	remaining_samples: proc() -> int,
}