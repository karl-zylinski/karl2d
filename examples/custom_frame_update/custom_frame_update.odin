// This program shows how to do the work that `k2.update()` does, but manually. This gives you more
// control.
//
// Most Karl2D examples use `k2.update()`. It updates the internal state of the library and returns
// a bool that says if the user is trying to close the window.
//
// Instead, one can skip `k2.update()`. In that case you need to call `k2.reset_frame_allocator()`,
// `k2.calculate_frame_time()`, `k2.process_events()` and `k2.close_window_requested()` manually.
package karl2d_custom_frame_update

import k2 "../.."
import "core:fmt"

main :: proc() {
	k2.init(1280, 720, "Karl2D Custom Frame Update")

	// This loop runs forever until something stops it using `break`
	for {
		// Reset the internal frame allocator that the library uses.
		k2.reset_frame_allocator()

		// Update the times returned by `k2.get_frame_time()` and `k2.get_time()`
		k2.calculate_frame_time()

		// Thus proc fetches events from the platform API and acts on them. It makes sure that procs
		// like `k2.key_is_held(.A)` has up-to-date input information.
		k2.process_events()

		// Returns true if the user has tried to close the window. In that case: Stop the main loop!
		if k2.close_window_requested() {
			break
		}

		// Draw things
		k2.clear(k2.BLUE)
		k2.draw_text(fmt.tprintf("Hellope! Time: %.3f s", k2.get_time()), {10, 10}, 50)

		// Present what we drew to the user.
		k2.present()

		// `fmt.tprintf` uses temp allocator, so clear it. Note that this is _not_ the same
		// allocator that `k2.reset_frame_allocator()` clear. The frame allocator is also a temp
		// alloator, but internal to the library.
		free_all(context.temp_allocator)
	}

	k2.shutdown()
}
