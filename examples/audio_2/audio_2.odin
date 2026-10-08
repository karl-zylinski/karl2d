// Work-in-progress audio example that has audio buses that you can drag n drop sounds between.

package karl2d_audio_example

import k2 "../.."

Playable_Sound :: struct {
	bus: k2.Audio_Bus,

	source: union {
		k2.Audio_Stream,
		k2.Audio_Clip,
	},

	playing_sound: k2.Sound,
	dragging: bool,
}

playable_sounds: [dynamic]Playable_Sound

Bus :: struct {
	volume: f32,
	bus: k2.Audio_Bus,
}

buses: [dynamic]Bus

main :: proc() {
	k2.init(1280, 720, "Audio")

	append(&playable_sounds, {
		source = k2.load_audio_stream_from_file("../audio/brahms.ogg"),
	})

	append(&playable_sounds, {
		source = k2.load_audio_clip_from_file("../audio/chord.ogg"),
	})

	append(&buses, { volume = 1, bus = k2.AUDIO_BUS_MASTER })
	append(&buses, { volume = 1, bus = k2.create_audio_bus() })

	for k2.update() {
		ui_cam := k2.Camera {
			zoom = k2.get_window_scale(),
		}

		mp := k2.screen_to_camera(k2.get_mouse_position(), ui_cam)
		k2.set_camera(ui_cam)
		k2.clear(k2.DARK_GRAY)

		Bus_Sounds :: struct {
			bus: k2.Audio_Bus,
			playable_sounds: [dynamic]int,
		}

		bus_sounds := make([dynamic]Bus_Sounds, context.temp_allocator)
		bus_sounds_lookup := make(map[k2.Audio_Bus]int, context.temp_allocator)

		make_bus_rect :: proc(idx: int) -> k2.Rect {
			return {
				10 + 310*f32(idx), 200,
				300, 80,
			}
		}

		for b, b_idx in buses {
			k2.set_audio_bus_volume(b.bus, b.volume)

			bus_sounds_lookup[b.bus] = len(bus_sounds)

			append(&bus_sounds, {
				bus = b.bus,
			})

			k2.draw_rect(make_bus_rect(b_idx), k2.LIGHT_PURPLE)
		}

		for ps, ps_idx in playable_sounds {
			bidx := bus_sounds_lookup[ps.bus]
			append(&bus_sounds[bidx].playable_sounds, ps_idx)
		}

		for &bs, b_idx in bus_sounds {
			br := make_bus_rect(b_idx)
			next_psr := k2.Rect {
				br.x + 5, br.y + 5, 40, 60,
			}

			for psi, psi_idx in &bs.playable_sounds {
				ps := &playable_sounds[psi]
				
				if k2.sound_is_playing(ps.playing_sound) {
					if as, is_as := ps.source.(k2.Audio_Stream); is_as {
						k2.update_audio_stream(as)
					}
				}

				psr := next_psr

				if ps.dragging {
					psr.x = mp.x
					psr.y = mp.y

					if !k2.mouse_button_is_held(.Left) {
						ps.dragging = false

						for &bs_check, bs_check_idx in bus_sounds {
							if bs_check_idx == b_idx {
								continue
							}

							bs_check_rect := make_bus_rect(bs_check_idx)

							if k2.point_in_rect(k2.rect_middle(psr), bs_check_rect) {
								ordered_remove(&bs.playable_sounds, psi_idx)
								append(&bs_check.playable_sounds, psi)
								ps.bus = bs_check.bus
								k2.set_sound_bus(ps.playing_sound, ps.bus)
							}
						}
					}
				}

				play_rect := k2.Rect {
					psr.x + psr.w - 25,
					psr.y + psr.h - 25,
					20, 20,
				}


				play_button_color := k2.BLUE

				hover_in_psr := k2.point_in_rect(mp, psr)
				hover_play_button := k2.point_in_rect(mp, play_rect)

				if hover_play_button {
					hover_in_psr = false
					play_button_color = k2.YELLOW

					if k2.mouse_button_went_down(.Left) {
						switch s in ps.source {
						case k2.Audio_Clip:
							ps.playing_sound = k2.play_audio_clip(s)
						case k2.Audio_Stream:
							ps.playing_sound = k2.play_audio_stream(s)
						}
					}
				}

				if k2.sound_is_playing(ps.playing_sound) {
					play_button_color = k2.GREEN
				}

				if hover_in_psr {
					if k2.mouse_button_went_down(.Left) {
						ps.dragging = true
					}
				}

				k2.draw_rect(psr, hover_in_psr ? k2.LIGHT_GREEN : k2.LIGHT_GRAY)
				k2.draw_rect(play_rect, play_button_color)

				next_psr.x += psr.w + 5
			}
		}


		k2.present()
		free_all(context.temp_allocator)
	}

	k2.shutdown()
}