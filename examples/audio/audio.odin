// AUDIO IS WORK IN PROGRESS -- I use this file to test things as I work on it. Do not use it yet.
package karl2d_audio_example

import k2 "../.."
import "core:math"

pos: k2.Vec2
snd: k2.Sound
snd2: k2.Sound

init :: proc() {
	k2.init(1280, 720, "Karl2D Audio")

	snd = make_sine_wave(200, 0.5, true)
	snd2 = make_sine_wave(440, 1, false)

	k2.play_sound(snd)
}

// Makes a sine wave of min_length rounded up to so that it ends at the end of a period. This makes
// it possible to loop cleanly.
make_sine_wave :: proc(freq: int, min_length: f32, loop: bool) -> k2.Sound {
	period_num_samples := k2.AUDIO_MIX_SAMPLE_RATE / f32(freq)
	num_periods := math.ceil(k2.AUDIO_MIX_SAMPLE_RATE * min_length)
	sine_data := make([]k2.Audio_Sample, int(num_periods))
	inc := (2.0*math.PI) / period_num_samples

	for &samp, i in sine_data {
		sf := math.sin(f32(i) * inc)
		sf *= f32(max(i16)/4)
		samp.x = u16(sf)
		samp.y = u16(sf)
	}

	return {
		data = sine_data,
		loop = loop,
	}
}

step :: proc() -> bool {
	if !k2.update() {
		return false
	}

	if k2.key_went_down(.Space) || k2.key_went_down(.S) {
		k2.play_sound(snd2)
	}

	k2.clear(k2.WHITE)
	k2.draw_text("Playing a looping 200 hz sine wave.", {20, 20}, 50)
	k2.draw_text("Press SPACE to also play a 1 second 440 hz sine wave.", {20, 80}, 50)
	k2.present()
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
