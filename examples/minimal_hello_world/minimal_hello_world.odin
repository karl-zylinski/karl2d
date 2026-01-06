// A minimal program that opens a window and draws some text in it each frame.
//
// There's a web-compatible version of this example in `../minimal_hello_world_web`.
package karl2d_minimal_hello_world

import k2 "../.."

main :: proc() {
	// Init Karl2D and open a window with drawing area of 1280x720 pixels and the supplied title.
	k2.init(1280, 720, "Greetings from Karl2D!")

	// Main game loop. Runs until `update` returns false, which it does when the player tries to
	// close the window.
	//
	// Update will make sure all the input state and frame timers are up-to-date.
	for k2.update() {
		// Clear the screen with a color
		k2.clear(k2.LIGHT_BLUE)

		// Write a message at coordinates (x, y) = (50, 50) with font height 100.
		k2.draw_text("Hellope!", {50, 50}, 100, k2.DARK_BLUE)

		// Nothing you drew this frame is shown until you call this.
		k2.present()
	}

	// Close the window and clean up the library's internal state.
	k2.shutdown()
}