// AUDIO IS WORK IN PROGRESS -- I use this file to test things as I work on it. Do not use it yet.
package karl2d_audio_example

import k2 "../.."
import "core:math"
import "core:mem"
import "core:fmt"
import "core:slice"

pos: k2.Vec2
snd: k2.Sound
snd_volume: f32
snd_pan: f32
snd_pitch: f32
snd2: k2.Sound  
snd3: k2.Sound
wav: k2.Sound
wav_inst: k2.Sound

init :: proc() {
	k2.init(1280, 720, "Karl2D Audio")

	snd = make_sine_wave(200, 0.5, 44100)
	snd_volume = 1
	snd_pitch = 1
	snd2 = make_sine_wave(440, 1, 44100)
	snd3 = make_sine_wave(700, 1, 22050)
	wav = k2.load_sound_from_bytes(#load("chord.wav"))
	wav_inst = k2.create_sound_instance(wav)
	k2.play_sound(snd, loop = true)
}

// Makes a sine wave of min_length rounded up to so that it ends at the end of a period. This makes
// it possible to loop cleanly.
make_sine_wave :: proc(freq: int, min_length: f32, sample_rate: int) -> k2.Sound {
	period_num_samples := f32(sample_rate) / f32(freq)
	num_periods := math.ceil(f32(sample_rate) * min_length)
	sine_data := make([]k2.Audio_Sample, int(num_periods), allocator = context.temp_allocator)
	inc := (2.0*math.PI) / period_num_samples

	for &samp, i in sine_data {
		sf := math.sin(f32(i) * inc)*0.25
		samp.x = sf
		samp.y = sf
	}

	return k2.load_sound_from_bytes_raw(slice.reinterpret([]u8, sine_data), .Float, sample_rate)
}

step :: proc() -> bool {
	if !k2.update() {
		return false
	}

	if k2.key_went_down(.Space) {
		k2.play_sound(wav)
	}

	if k2.key_went_down(.Enter) {
		k2.play_sound(snd2)
	}

	if k2.key_went_down(.N3) {
		k2.play_sound(snd3)
	}
	
	if k2.key_is_held(.Up) {
		snd_volume += k2.get_frame_time() * 2
	}

	if k2.key_is_held(.Down) {
		snd_volume -= k2.get_frame_time() * 2
	}
	
	if k2.key_is_held(.Left) {
		snd_pan -= k2.get_frame_time() * 2
	}

	if k2.key_is_held(.Right) {
		snd_pan += k2.get_frame_time() * 2
	}
	
	if k2.key_is_held(.W) {
		snd_pitch += k2.get_frame_time() * 0.5
	}
	
	if k2.key_is_held(.S) {
		snd_pitch -= k2.get_frame_time() * 0.5
	}

	if k2.key_went_down(.T)	{
		k2.set_sound_pitch(wav, 2)
		k2.set_sound_pan(wav, -1)
		k2.play_sound(wav)
		k2.set_sound_pitch(wav_inst, 0.5)
		k2.set_sound_pan(wav_inst, 1)
		k2.play_sound(wav_inst)
	}
	
	snd_pan = clamp(snd_pan, -1, 1)
	snd_volume = clamp(snd_volume, 0, 1)
	snd_pitch = math.max(snd_pitch, 0.01)
	
	k2.set_sound_volume(snd, snd_volume)
	k2.set_sound_pan(snd, snd_pan)
	k2.set_sound_pitch(snd, snd_pitch)
	
	k2.clear(k2.WHITE)
	k2.draw_text(
		fmt.tprintf(
			"Playing a looping 200 hz sine wave.\nVolume: %.3f (change with up/down)\nPan: %.3f (change with left/right)\nPitch: %.3f (change with W/S)",
			snd_volume,
			snd_pan,
			snd_pitch,
		),
		{20, 20},
		40,
	)
	k2.draw_text("Press Space to play a familiar sound.", {20, 200}, 40)
	k2.draw_text("Press Enter to also play a 1 second 440 hz sine wave.", {20, 240}, 40)
	k2.present()
	free_all(context.temp_allocator)

	return true
}

shutdown :: proc() {
	k2.destroy_sound(snd)
	k2.destroy_sound(snd2)
	k2.destroy_sound(snd3)
	k2.destroy_sound(wav)
	k2.destroy_sound(wav_inst)
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
