package karl2d_example_audio_positional

import k2 "../.."
import "core:math/linalg"
import "core:math"
import "core:slice"
import "core:mem"
import "core:fmt"

player_pos: k2.Vec2
sine_wave: k2.Audio_Buffer
spinning_audio_source: Audio_Source
stationary_audio_sources: [dynamic]Audio_Source

Audio_Source :: struct {
	sound: k2.Sound,
	pos: k2.Vec2,
}

SOUND_LENGTH :: 1

update_audio_source :: proc(as: ^Audio_Source) {
	player_to_snd := as.pos - player_pos
	pan := math.remap_clamped(player_to_snd.x, -100, 100, -1, 1)			
	k2.set_sound_pan(as.sound, pan)
	dist := linalg.length(player_to_snd) * 0.01
	intensity := dist < 1 ? 1 : 1/(dist*dist) // inverse square falloff
	k2.set_sound_volume(as.sound, intensity)
}

draw_audio_source :: proc(as: Audio_Source) {
	r := k2.Rect {
		as.pos.x - 10,
		as.pos.y - 10,
		20,
		20,
	}
	k2.draw_rect(r, k2.LIGHT_YELLOW)
}

init :: proc() {
	k2.init(1000, 536, "Audio Positional", options = { window_mode = .Windowed_Resizable })
	sine_wave = make_sine_wave(200, SOUND_LENGTH, 44100)
	player_pos = {200, 200}

	spinning_audio_source = {
		sound = k2.create_sound_from_audio_buffer(sine_wave),
	}

	k2.set_sound_loop(spinning_audio_source.sound, true)
	k2.play_sound(spinning_audio_source.sound)

	stationary_1 := Audio_Source {
		sound = k2.create_sound_from_audio_buffer(sine_wave),
		pos = {50, 50},
	}

	k2.set_sound_loop(stationary_1.sound, true)
	k2.play_sound(stationary_1.sound)
	k2.set_sound_pitch(stationary_1.sound, 0.5)
	append(&stationary_audio_sources, stationary_1)

	stationary_2 := Audio_Source {
		sound = k2.create_sound_from_audio_buffer(sine_wave),
		pos = {450, 50},
	}

	k2.set_sound_loop(stationary_2.sound, true)
	k2.play_sound(stationary_2.sound)
	k2.set_sound_pitch(stationary_2.sound, 0.45)
	append(&stationary_audio_sources, stationary_2)

	stationary_3 := Audio_Source {
		sound = k2.create_sound_from_audio_buffer(sine_wave),
		pos = {450, 450},
	}

	k2.set_sound_loop(stationary_3.sound, true)
	k2.play_sound(stationary_3.sound)
	k2.set_sound_pitch(stationary_3.sound, 0.55)
	append(&stationary_audio_sources, stationary_3)

	stationary_4 := Audio_Source {
		sound = k2.create_sound_from_audio_buffer(sine_wave),
		pos = {50, 450},
	}
	
	k2.set_sound_loop(stationary_4.sound, true)
	k2.play_sound(stationary_4.sound)
	k2.set_sound_pitch(stationary_4.sound, 0.6)
	append(&stationary_audio_sources, stationary_4)
}

step :: proc() -> bool {
	if !k2.update() {
		return false
	}

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
	t := k2.get_time()

	{
		spinning_audio_source.pos = player_pos + {f32(math.cos(t*3)), f32(math.sin(t*3))*0.5} * 150
		update_audio_source(&spinning_audio_source)
	}

	for &as in stationary_audio_sources {
		update_audio_source(&as)
	}

	k2.clear(k2.GREEN)

	draw_audio_source(spinning_audio_source)
	for &as in stationary_audio_sources {
		draw_audio_source(as)
	}

	k2.draw_circle(player_pos, 10, k2.LIGHT_RED)


	//
	// BOTTOM BAR
	//

	k2.set_camera(nil)
	screen_rect := k2.rect_from_pos_size({}, k2.get_screen_size())
	bottom_bar := k2.rect_cut_bottom(&screen_rect, 36, 0)
	k2.draw_rect(bottom_bar, k2.DARK_GRAY)
	bottom_bar = k2.rect_shrink(bottom_bar, 4, 4)
	k2.draw_text("Move circle using arrow keys. The squares emit sound.", k2.rect_top_left(bottom_bar), bottom_bar.h, k2.WHITE)
	source_code_rect := k2.rect_cut_right(&bottom_bar, k2.ui_button_width("Source Code", bottom_bar.h) + 50, 0)

	if k2.ui_button(source_code_rect, "Source Code") {
		k2.open_url("https://github.com/karl-zylinski/karl2d/blob/master/examples/positional_audio/positional_audio.odin")
	}

	k2.present()

	return true
}

shutdown :: proc() {
	k2.destroy_sound(spinning_audio_source.sound)

	for s in stationary_audio_sources {
		k2.destroy_sound(s.sound)
	}

	delete(stationary_audio_sources)
	k2.destroy_audio_buffer(sine_wave)
	k2.shutdown()
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
