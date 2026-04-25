// For making a release exe that does not use hot reload.

package karl2d_hot_reload_main_release

import "core:log"
import "core:os"

import game "../game"

USE_TRACKING_ALLOCATOR :: #config(USE_TRACKING_ALLOCATOR, false)

main :: proc() {
	when USE_TRACKING_ALLOCATOR {
		default_allocator := context.allocator
		tracking_allocator: Tracking_Allocator
		tracking_allocator_init(&tracking_allocator, default_allocator)
		context.allocator = allocator_from_tracking_allocator(&tracking_allocator)
	}

	logh, logh_err := os.open("log.txt", {.Create, .Trunc, .Read, .Write })

	if logh_err == os.ERROR_NONE {
		os.stdout = logh
		os.stderr = logh
	}

	logger := logh_err == os.ERROR_NONE ? log.create_file_logger(logh) : log.create_console_logger()
	context.logger = logger
	
	k2_state := game.app_startup(context.allocator)
	game.app_init_state(k2_state, context.allocator)

	window_open := true
	for window_open {
		window_open = game.app_update()

		when USE_TRACKING_ALLOCATOR {
			for b in tracking_allocator.bad_free_array {
				log.error("Bad free at: %v", b.location)
			}

			clear(&tracking_allocator.bad_free_array)
		}

		free_all(context.temp_allocator)
	}

	free_all(context.temp_allocator)
	game.app_destroy_state()
	game.app_shutdown()
	
	if logh_err == os.ERROR_NONE {
		log.destroy_file_logger(logger)
	}

	when USE_TRACKING_ALLOCATOR {
		for key, value in tracking_allocator.allocation_map {
			log.error("%v: Leaked %v bytes\n", value.location, value.size)
		}

		tracking_allocator_destroy(&tracking_allocator)
	}
}

// make game use good GPU on laptops etc

@(export)
NvOptimusEnablement: u32 = 1

@(export)
AmdPowerXpressRequestHighPerformance: i32 = 1