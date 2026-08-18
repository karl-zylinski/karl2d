package karl2d_audio_example

import k2 "../.."
import "core:math"
import "core:mem"
import "core:fmt"
import "core:slice"

pos: k2.Vec2
sine_clip_200: k2.Audio_Clip
sine_sound: k2.Sound
sine_clip_440: k2.Audio_Clip
sine_clip_700: k2.Audio_Clip
chord_clip: k2.Audio_Clip

music: k2.Audio_Stream
music_sound: k2.Sound

// True while the left mouse button is dragging the seek bar.
seeking: bool

// How far along the seek bar the drag currently is, from 0 to 1.
seek_fraction: f32

// Where the seek bar is drawn. Clicking anywhere in it jumps to that spot in the song.
SEEK_BAR :: k2.Rect { 20, 330, 800, 30 }

snd_volume: f32
snd_pan: f32
snd_pitch: f32 = 1

MUSIC_FILE :: "brahms.ogg"
HAS_MUSIC :: #exists(MUSIC_FILE)

init :: proc() {
	k2.init(1280, 720, "Karl2D Audio")

	sine_clip_200 = make_sine_wave(200, 0.5, 44100)
	snd_volume = 1
	snd_pitch = 1
	sine_clip_440 = make_sine_wave(440, 1, 44100)
	sine_clip_700 = make_sine_wave(700, 1, 22050)
	chord_clip = k2.load_audio_clip_from_bytes(#load("chord.wav"))

	when HAS_MUSIC {
		when ODIN_OS == .JS {
			// You could do this on non-JS (web) as well, I just try both so we get test coverage of
			// these different modes of operation.
			music = k2.load_audio_stream_from_bytes(#load(MUSIC_FILE))
		} else {
			music = k2.load_audio_stream_from_file(MUSIC_FILE)
		}
		music_sound = k2.play_audio_stream(music, loop = true)
	} else {
		sine_sound = k2.play_audio_clip(sine_clip_200, loop = true)
	}
}

// Makes a sine wave of min_length rounded up to so that it ends at the end of a period. This makes
// it possible to loop cleanly.
make_sine_wave :: proc(freq: int, min_length: f32, sample_rate: int) -> k2.Audio_Clip {
	period_num_samples := f32(sample_rate) / f32(freq)
	num_periods := math.ceil(f32(sample_rate) * min_length)
	sine_data := make([]k2.Audio_Sample, int(num_periods), allocator = context.temp_allocator)
	inc := (2.0*math.PI) / period_num_samples

	for &samp, i in sine_data {
		sf := math.sin(f32(i) * inc)*0.25
		samp = sf
	}

	return k2.load_audio_clip_from_bytes_raw(slice.reinterpret([]u8, sine_data), .Float32, sample_rate, .Mono)
}

step :: proc() -> bool {
	if !k2.update() {
		return false
	}

	if k2.key_went_down(.Enter) {
		k2.play_audio_clip(sine_clip_440)
	}

	if k2.key_went_down(.N3) {
		k2.play_audio_clip(sine_clip_700)
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


	if k2.key_went_down(.Space) {
		k2.play_audio_clip(chord_clip)
	}

	if k2.key_went_down(.T)	{
		k2.play_audio_clip(chord_clip, pitch = 2, pan = -1)
		k2.play_audio_clip(chord_clip, pitch = 0.5, pan = 1)
	}
	
	snd_pan = clamp(snd_pan, -1, 1)
	snd_volume = clamp(snd_volume, 0, 1)
	snd_pitch = math.max(snd_pitch, 0.01)
	
	when HAS_MUSIC {
		k2.update_audio_stream(music)

		// Home starts the music. End stops it, which also rewinds the stream. P pauses and
		// resumes, keeping the position.
		if k2.key_went_down(.Home) {
			music_sound = k2.play_audio_stream(
				music,
				volume = snd_volume,
				pan = snd_pan,
				pitch = snd_pitch,
				loop = true,
			)
		}

		if k2.key_went_down(.End) {
			k2.stop_sound(music_sound)
		}

		if k2.key_went_down(.P) {
			k2.set_sound_paused(music_sound, k2.sound_is_playing(music_sound))
		}

		// SEEK BAR
		//
		// Press inside the bar to start dragging it, then release to jump to that spot. The drag
		// continues even if the mouse leaves the bar, which is what you'd expect from a scrub bar.
		//
		// We only set the position when the button is released, not every frame of the drag.
		// Seeking backwards in a stream that was loaded from file has to decode the file from the
		// start, so doing it every frame would make the dragging stutter.
		if k2.mouse_button_went_down(.Left) && k2.point_in_rect(k2.get_mouse_position(), SEEK_BAR) {
			seeking = true
		}

		if seeking {
			seek_fraction = clamp((k2.get_mouse_position().x - SEEK_BAR.x) / SEEK_BAR.w, 0, 1)

			if !k2.mouse_button_is_held(.Left) {
				seeking = false
				music_length := k2.get_sound_length(music_sound)

				if music_length > 0 {
					k2.set_sound_position(music_sound, seek_fraction * music_length)
				}
			}
		}

		k2.set_sound_pitch(music_sound, snd_pitch)
		k2.set_sound_pan(music_sound, snd_pan)
		k2.set_sound_volume(music_sound, snd_volume)
	} else {
		k2.set_sound_volume(sine_sound, snd_volume)
		k2.set_sound_pan(sine_sound, snd_pan)
		k2.set_sound_pitch(sine_sound, snd_pitch)
	}
	
	k2.clear(k2.WHITE)

	playing_label := "Playing a looping 200 hz sine wave."

	when HAS_MUSIC {
		playing_label = "Playing music from file: " + MUSIC_FILE
	}

	k2.draw_text(
		fmt.tprintf(
			"%s\nVolume: %.3f (change with up/down)\nPan: %.3f (change with left/right)\nPitch: %.3f (change with W/S)",
			playing_label,
			snd_volume,
			snd_pan,
			snd_pitch,
		),
		{20, 20},
		40,
		k2.BLACK,
	)
	k2.draw_text("Press Space to play a familiar sound.", {20, 200}, 40, k2.BLACK)
	k2.draw_text("Press Enter to also play a 1 second 440 hz sine wave.", {20, 240}, 40, k2.BLACK)

	when HAS_MUSIC {
		k2.draw_text(
			"Home plays the music, End stops it, P pauses. Drag the bar to seek.",
			{20, 280},
			40,
			k2.BLACK,
		)

		position := k2.get_sound_position(music_sound)
		length := k2.get_sound_length(music_sound)
		fraction: f32

		if length > 0 {
			fraction = clamp(position/length, 0, 1)
		}

		// While dragging, the bar follows the mouse instead of the music. The music catches up
		// when the button is released.
		if seeking {
			fraction = seek_fraction
		}

		k2.draw_rect(SEEK_BAR, k2.LIGHT_GRAY)

		played := SEEK_BAR
		played.w = SEEK_BAR.w * fraction
		k2.draw_rect(played, seeking ? k2.LIGHT_BLUE : k2.DARK_GRAY)
		k2.draw_rect_outline(SEEK_BAR, 1, k2.BLACK)

		k2.draw_text(
			fmt.tprintf("%.1f / %.1f s", fraction*length, length),
			{SEEK_BAR.x, SEEK_BAR.y + SEEK_BAR.h + 8},
			30,
			k2.BLACK,
		)
	}

	k2.present()
	free_all(context.temp_allocator)

	return true
}

shutdown :: proc() {
	k2.destroy_audio_clip(sine_clip_200)
	k2.destroy_audio_clip(sine_clip_440)
	k2.destroy_audio_clip(sine_clip_700)
	k2.destroy_audio_clip(chord_clip)

	when HAS_MUSIC {
		k2.destroy_audio_stream(music)
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
