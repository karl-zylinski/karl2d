package karl2d_minimal_example

import k2 "../.."
import "core:log"
import "core:time"

main :: proc() {
	context.logger = log.create_console_logger()
	k2.init(1280, 720, "Karl2D Minimal Program")
	k2.set_window_position(300, 100)

	start_time := time.now()

	for !k2.shutdown_wanted() {
		t := f32(time.duration_seconds(time.since(start_time)))
		k2.process_events()
		k2.clear(k2.BLUE)
		k2.present()

		free_all(context.temp_allocator)
	}

	k2.shutdown()
}