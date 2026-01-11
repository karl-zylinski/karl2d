// A minimal program that opens a window and draws some text in it each frame.
//
// This is a web-compatible version of `../minimal_hello_world`. Usually I try to make all examples
// web compatible. But I wanted to keep the `minimal_hello_world` example clean.
//
// The web compatibility comes from splitting the example up into `init` and `step`.
//
// Compile using command-line by going to the Karl2D repository root folder and executing:
// `odin run build_web -- examples/minimal_hello_world_web`
// The output will be in `examples/minimal_hello_world_web/bin/web`
package karl2d_minimal_hello_world_web

import k2 "../.."

init :: proc() {
	// Init Karl2D and open a window with drawing area of 1280x720 pixels and the supplied title.
	k2.init(1280, 720, "Greetings from Karl2D!")
}

step :: proc() -> bool {
	// Update will make sure all the input state and frame timers are up-to-date.
	//
	// If update returns false, then it means that the player tried to close the window. On web this
	// doesn't really mean anything since you can't stop the browser from closing.
	if !k2.update() {
		return false
	}

	// Clear the screen with a color
	k2.clear(k2.LIGHT_BLUE)

	// Write a message at coordinates (x, y) = (50, 50) with font height 100.
	k2.draw_text("Hellope!", {50, 50}, 100, k2.DARK_BLUE)

	// Nothing you drew this frame is shown until you call this.
	k2.present()

	return true
}
