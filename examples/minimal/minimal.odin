package karl2d_minimal_example

import k2 "../.."

main :: proc() {
	k2.init(1280, 720, "Karl2D Minimal Program")

	for !k2.shutdown_wanted() {
		k2.process_events()
		k2.clear(k2.BLUE)
		k2.present()
	}

	k2.shutdown()
}