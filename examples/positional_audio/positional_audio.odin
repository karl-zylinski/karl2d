package karl2d_example_audio_positional

import k2 "../.."
import "core:math/linalg"
import "core:math"
import "core:slice"
import "core:mem"
import "core:fmt"

player_pos: k2.Vec2
sine_wave: k2.Audio_Buffer

Positioned_Sound :: struct {
	sound: k2.Sound,
	pos: k2.Vec2,
}

playing_sounds: [dynamic; 256]Positioned_Sound

SOUND_LENGTH :: 20

main :: proc() {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	context.allocator = mem.tracking_allocator(&track)

	k2.init(1280, 720, "Audio Positional", options = { window_mode = .Windowed_Resizable })
	sine_wave = make_sine_wave(440, SOUND_LENGTH, 44100)
	player_pos = {200, 200}

	for k2.update() {
		movement: k2.Vec2

		if k2.key_is_held(.Up) {
			movement.y -= 1
		}

		if k2.key_is_held(.Down) {
			movement.y += 1
		}

		if k2.key_is_held(.Left) {
			movement.x -= 1
		}

		if k2.key_is_held(.Right) {
			movement.x += 1
		}

		dt := k2.get_frame_time()

		player_pos += linalg.normalize0(movement) * dt * 200

		if k2.key_went_down(.Space) {
			s := k2.create_sound_from_audio_buffer(sine_wave)
			k2.play_sound(s)

			ps := Positioned_Sound {
				pos = player_pos,
				sound = s,
			}

			append(&playing_sounds, ps)
		}

		for sound_idx := 0; sound_idx < len(playing_sounds); sound_idx += 1 {
			s := playing_sounds[sound_idx]

			if !k2.sound_is_playing(s.sound) {
				unordered_remove(&playing_sounds, sound_idx)
				sound_idx -= 1
				continue
			}

			player_to_snd := s.pos - player_pos
			pan := math.remap_clamped(player_to_snd.x, -200, 200, -1, 1)			
			k2.set_sound_pan(s.sound, pan)
			dist := linalg.length(player_to_snd) * 0.015
			intensity := dist < 1 ? 1 : 1/(dist*dist) // inverse square falloff
			k2.set_sound_volume(s.sound, intensity)
		}

		k2.clear(k2.GREEN)

		for s in playing_sounds {
			r := k2.Rect {
				s.pos.x - 10,
				s.pos.y - 10,
				20,
				20,
			}
			k2.draw_rect(r, k2.LIGHT_YELLOW)
		}

		k2.draw_circle(player_pos, 10, k2.LIGHT_RED)

		k2.present()
	}

	k2.destroy_audio_buffer(sine_wave)

	k2.shutdown()



	if len(track.allocation_map) > 0 {
		fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
		for _, entry in track.allocation_map {
			fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
		}
	}
	mem.tracking_allocator_destroy(&track)
}

make_sine_wave :: proc(freq: int, min_length: f32, sample_rate: int) -> k2.Audio_Buffer {
	period_num_samples := f32(sample_rate) / f32(freq)
	num_periods := math.ceil(f32(sample_rate) * min_length)
	sine_data := make([]k2.Audio_Sample, int(num_periods), allocator = context.temp_allocator)
	inc := (2.0*math.PI) / period_num_samples

	for &samp, i in sine_data {
		sf := math.sin(f32(i) * inc)*0.25
		samp = sf
	}

	return k2.load_audio_buffer_from_bytes_raw(slice.reinterpret([]u8, sine_data), .Float, sample_rate, .Mono)
}