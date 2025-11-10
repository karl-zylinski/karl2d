package karl2d_minimal_example

import k2 "../.."
import "core:mem"
import "core:log"
import "core:fmt"

main :: proc() {
	context.logger = log.create_console_logger()


	when ODIN_DEBUG {
		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		context.allocator = mem.tracking_allocator(&track)

		defer {
			if len(track.allocation_map) > 0 {
				for _, entry in track.allocation_map {
					fmt.eprintf("%v leaked: %v bytes\n", entry.location, entry.size)
				}
			}
			mem.tracking_allocator_destroy(&track)
		}
	}


	k2.init(1080, 1080, "Karl2D Minimal Program")
	k2.set_window_position(300, 100)

	for !k2.shutdown_wanted() {
		k2.process_events()
		k2.clear(k2.BLUE)

		k2.draw_rect({10, 10, 60, 60}, k2.GREEN)
		k2.draw_rect({20, 20, 40, 40}, k2.BLACK)
		k2.draw_circle({120, 40}, 30, k2.BLACK)
		k2.draw_circle({120, 40}, 20, k2.GREEN)
		k2.draw_text("Hellöpe!", {10, 100}, 64, k2.WHITE)
		k2.present()
		free_all(context.temp_allocator)
	}

	k2.shutdown()
}
