// Shows how to use audio buses. A bus is a group of sounds that are mixed together before they
// reach the master bus. You can set the volume and the pan of the whole group at once, and you can
// run your own effect on it.
//
// This example puts some sound effects on a bus and leaves a tone on the master bus, so you can
// hear that the bus volume only affects the things routed to it.
//
// Compile using command-line by going to the Karl2D repository root folder and executing:
// `odin run build_web -- examples/audio_bus`
package karl2d_audio_bus_example

import k2 "../.."
import "core:math"
import "core:math/rand"
import "core:mem"
import "core:fmt"
import "core:slice"

sfx_bus: k2.Audio_Bus
sfx_bus_destroyed: bool

// Played as one-shots on the sfx bus. Several of these can overlap.
blip: k2.Audio_Clip

// A drone on the sfx bus, so you can hear the bus volume and pan without pressing anything.
drone: k2.Sound
drone_buffer: k2.Audio_Clip

// This one stays on the master bus. It is what the sfx bus volume does NOT affect.
tone: k2.Sound
tone_buffer: k2.Audio_Clip

sfx_volume: f32 = 1
sfx_pan: f32
master_volume: f32 = 1
filter_enabled: bool

// The filter needs to remember the previous output to do its job. That is what `user_data` is for:
// the effect is called once per mixed chunk, so anything it wants to carry across the chunks has to
// live outside of it.
Low_Pass :: struct {
	prev: [2]f32,
}

low_pass: Low_Pass

// A one pole low pass filter. Each output sample is nudged from the previous output towards the
// input, which smooths the waveform out and takes the high frequencies with it.
low_pass_effect :: proc(samples: [][2]k2.Audio_Sample, user_data: rawptr) {
	lp := (^Low_Pass)(user_data)

	// How much of the way to the input we move each sample. Lower value, darker sound.
	CUTOFF :: 0.05

	for &samp in samples {
		lp.prev += (samp - lp.prev) * CUTOFF
		samp = lp.prev
	}
}

init :: proc() {
	k2.init(1280, 720, "Karl2D Audio Bus")

	sfx_bus = k2.create_audio_bus()

	blip = make_sine_wave(600, 0.12, 44100)
	drone_buffer = make_sine_wave(80, 1, 44100)
	tone_buffer = make_sine_wave(220, 1, 44100)

	// The drone goes on the sfx bus. The tone is left alone, so it plays on the master bus.
	drone = k2.play_audio_clip(drone_buffer, volume = 0.3, loop = true, bus = sfx_bus)
	tone = k2.play_audio_clip(tone_buffer, volume = 0.15, loop = true)
}

// Makes a sine wave that is a whole number of periods long, so that it loops cleanly.
make_sine_wave :: proc(freq: int, min_length: f32, sample_rate: int) -> k2.Audio_Clip {
	period_num_samples := f32(sample_rate) / f32(freq)
	num_periods := math.ceil(f32(sample_rate) * min_length)
	sine_data := make([]k2.Audio_Sample, int(num_periods), allocator = context.temp_allocator)
	inc := (2.0*math.PI) / period_num_samples

	for &samp, i in sine_data {
		samp = math.sin(f32(i) * inc) * 0.25
	}

	bytes := slice.reinterpret([]u8, sine_data)
	return k2.load_audio_clip_from_bytes_raw(bytes, .Float32, sample_rate, .Mono)
}

step :: proc() -> bool {
	if !k2.update() {
		return false
	}

	// SOUNDS

	// Each press starts a separate playback, so pressing quickly overlaps them. The pitch is
	// randomized to make that easier to hear.
	if k2.key_went_down(.Space) {
		k2.play_audio_clip(blip, pitch = rand.float32_range(0.8, 1.6), bus = sfx_bus)
	}

	// BUS SETTINGS

	if k2.key_is_held(.Up) {
		sfx_volume += k2.get_frame_time()
	}

	if k2.key_is_held(.Down) {
		sfx_volume -= k2.get_frame_time()
	}

	if k2.key_is_held(.Left) {
		sfx_pan -= k2.get_frame_time()
	}

	if k2.key_is_held(.Right) {
		sfx_pan += k2.get_frame_time()
	}

	if k2.key_is_held(.W) {
		master_volume += k2.get_frame_time()
	}

	if k2.key_is_held(.S) {
		master_volume -= k2.get_frame_time()
	}

	sfx_volume = clamp(sfx_volume, 0, 1)
	sfx_pan = clamp(sfx_pan, -1, 1)
	master_volume = clamp(master_volume, 0, 1)

	// After the sfx bus is destroyed, `sfx_bus` points at the master bus, so these setters would
	// start controlling the master bus. Not what the sfx keys are for, hence the guard.
	if !sfx_bus_destroyed {
		k2.set_audio_bus_volume(sfx_bus, sfx_volume)
		k2.set_audio_bus_pan(sfx_bus, sfx_pan)

		if k2.key_went_down(.F) {
			filter_enabled = !filter_enabled

			if filter_enabled {
				k2.set_audio_bus_effect(sfx_bus, low_pass_effect, &low_pass)
			} else {
				k2.set_audio_bus_effect(sfx_bus, nil)
			}
		}
	}

	// The master bus is just a bus like the others. This is how you make a master volume slider.
	k2.set_audio_bus_volume(k2.AUDIO_BUS_MASTER, master_volume)

	// Destroying a bus moves everything on it back to the master bus. The drone keeps playing, it
	// just stops listening to the sfx volume. We point our own handle at the master bus afterwards,
	// since the old one is dead. That keeps the blips playable.
	if k2.key_went_down(.D) && !sfx_bus_destroyed {
		k2.destroy_audio_bus(sfx_bus)
		sfx_bus = k2.AUDIO_BUS_MASTER
		sfx_bus_destroyed = true

		// The effect died with the bus.
		filter_enabled = false
	}

	// DRAW

	k2.clear(k2.WHITE)

	bus_label := "The drone and the blips are on the sfx bus."

	if sfx_bus_destroyed {
		bus_label = "The sfx bus is destroyed. Everything is on the master bus now."
	}

	k2.draw_text(
		fmt.tprintf(
			"%s\n" +
			"Sfx bus volume: %.2f (up/down)\n" +
			"Sfx bus pan: %.2f (left/right)\n" +
			"Master volume: %.2f (W/S)\n" +
			"Sfx bus filter: %v (F to toggle)",
			bus_label,
			sfx_volume,
			sfx_pan,
			master_volume,
			filter_enabled ? "on" : "off",
		),
		{20, 20},
		36,
		k2.BLACK,
	)

	k2.draw_text("Press Space to play a blip on the sfx bus.", {20, 240}, 36, k2.BLACK)
	k2.draw_text("Press D to destroy the sfx bus.", {20, 280}, 36, k2.BLACK)
	k2.draw_text("The 220 hz tone stays on the master bus the whole time.", {20, 320}, 36, k2.BLACK)
	k2.present()
	free_all(context.temp_allocator)

	return true
}

shutdown :: proc() {
	k2.destroy_audio_clip(blip)
	k2.destroy_audio_clip(drone_buffer)
	k2.destroy_audio_clip(tone_buffer)

	if !sfx_bus_destroyed {
		k2.destroy_audio_bus(sfx_bus)
	}

	k2.shutdown()
}

// This is not run by the web version, but it makes this program also work on non-web!
main :: proc() {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	context.allocator = mem.tracking_allocator(&track)

	init()
	for step() {}
	shutdown()

	if len(track.allocation_map) > 0 {
		fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
		for _, entry in track.allocation_map {
			fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
		}
	}
	mem.tracking_allocator_destroy(&track)
}
