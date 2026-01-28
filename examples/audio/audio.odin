// AUDIO IS WORK IN PROGRESS -- I use this file to test things as I work on it. Do not use it yet.
package karl2d_audio_example

import k2 "../.."
import "core:fmt"
import "core:math/linalg"
import "core:math"
import "core:slice"

pos: k2.Vec2
snd: k2.Sound

init :: proc() {
	k2.init(1280, 720, "Karl2D Basics")

	// make 2 second sine wave
	
	FREQ :: 440.0
	PERIODS_PER_SEC :: 44100.0 / FREQ

	
	// u16 because 16 bit sound... easier to the generator code below

	// 44100 samples per second, 2 channels, 2 seconds... u16 per sample (16 bit sound)
	test_sound_block := make([]u16, 44100*2*2)

	INC :: f32(2.0*f64(math.PI)) / PERIODS_PER_SEC
	for &samp, i in test_sound_block {
		sf := math.sin(f32(i/2) * INC)
		sf *= f32(max(i16))
		samp = u16(sf)
	}

	snd = {
		data = slice.reinterpret([]u8, test_sound_block[:]),
	}
}

step :: proc() -> bool {
	// `update` proceses input and updates frame timers. It returns false if the user has tried to
	// close the window.
	if !k2.update() {
		return false
	}

	movement: k2.Vec2

	if k2.key_is_held(.Left) {
		movement.x -= 1
	}

	if k2.key_is_held(.Right) {
		movement.x += 1
	}

	if k2.key_is_held(.Up) {
		movement.y -= 1
	}

	if k2.key_is_held(.Down) {
		movement.y += 1
	}

	if k2.key_went_down(.T) {
		k2.play_sound(snd)
	}

	// Normalizing makes the movement not go faster when going diagonally.
	pos += linalg.normalize0(movement) * k2.get_frame_time() * 400

	k2.clear(k2.LIGHT_BLUE)

	// We use the current time to spin and move the texture.
	k2.draw_rect({10, 10, 60, 60}, k2.GREEN)
	k2.draw_rect({20, 20, 40, 40}, k2.LIGHT_GREEN)

	// These two circles are controlled using the arrow keys via the `pos` variable.
	k2.draw_circle(pos + {120, 40}, 30, k2.DARK_RED)
	k2.draw_circle(pos + {120, 40}, 20, k2.RED)

	dt := k2.get_frame_time()
	t := k2.get_time()
	msg1 := fmt.tprintf("Time since start: %.2f s", t)
	msg2 := fmt.tprintf("Last frame time: %.3f ms (%.2f fps)", dt*1000, dt == 0 ? 0 : 1/dt)
	msg2_width := k2.measure_text(msg2, 48).x

	// k2.color_alpha takes a pre-defined color and replaces the alpha (transparency).
	k2.draw_rect({4, 95, msg2_width+20, 162}, k2.color_alpha(k2.DARK_GRAY, 192))
	k2.draw_text("Hellöpe!", {15, 105}, 48, k2.LIGHT_RED)

	k2.draw_text(msg1, {15, 153}, 48, k2.ORANGE)
	k2.draw_text(msg2, {15, 201}, 48, k2.LIGHT_PURPLE)

	k2.draw_text("Move the red dot using arrow keys!", {10, f32(k2.get_screen_height()) - 50}, 40)

	k2.present()

	// The calls to `fmt.tprintf` above allocate using `context.temp_allocator`. Those allocations
	// are not needed for more than a frame, so they can be thrown away now.
	free_all(context.temp_allocator)

	return true
}

shutdown :: proc() {
	k2.shutdown()
}

// This is not run by the web version, but it makes this program also work on non-web!
main :: proc() {
	init()
	for step() {}
	shutdown()
}
