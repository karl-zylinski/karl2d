package space_cat

import "core:fmt"
import k2 "../.."
import "core:encoding/json"
import "core:math"
import "core:math/linalg"

Edit_Mode :: enum {
	Tiles,
	Background_Objects,
	Foreground_Objects,
	Interactables,
}

edit_mode: Edit_Mode
editor_bg_current_idx: int
editor_fg_current_idx: int
editor_interactable_current_type: Interactable_Type

@(private="file")
editor_world: World

editor_init :: proc(world_data: []u8) {
	json.unmarshal(world_data, &editor_world)
}

editor_shutdown :: proc() {
	destroy_world(editor_world)
}

editor_update :: proc() {
	k2.clear(CLEAR_COLOR)
	k2.set_camera(game_camera)
	k2.draw_rect({0, 0, SCREEN_WIDTH, SCREEN_HEIGHT}, SPACE_COLOR)

	mouse_pos_world := k2.screen_to_world(k2.get_mouse_position(), game_camera)
	current_room := &editor_world.rooms[current_room_idx]

	if edit_mode == .Tiles {
		hovered_grid_rect: k2.Rect
		grid_x := int(math.floor(mouse_pos_world.x / TILE_SIZE))
		grid_y := int(math.floor(mouse_pos_world.y / TILE_SIZE))

		if grid_x >= 0 && grid_x < ROOM_TILE_WIDTH && grid_y >= 0 && grid_y < ROOM_TILE_HEIGHT {
			hovered_grid_idx := grid_y*ROOM_TILE_WIDTH+grid_x
			grid_pos := k2.Vec2 { f32(grid_x) * TILE_SIZE, f32(grid_y) *TILE_SIZE}
			hovered_grid_rect = k2.rect_from_pos_size(grid_pos, {TILE_SIZE, TILE_SIZE})

			modifiers := k2.get_held_modifiers()

			if modifiers == k2.MODIFIERS_NONE && k2.mouse_button_is_held(.Left) {
				current_room.tiles[hovered_grid_idx] = .Space
			}

			if (
				(modifiers == { .Control } && k2.mouse_button_is_held(.Left)) ||
				k2.mouse_button_is_held(.Right)
			) {
				current_room.tiles[hovered_grid_idx] = .Ground
			}
		}

		k2.draw_rect(hovered_grid_rect, {255, 255, 255, 128})
	} else if edit_mode == .Background_Objects {
		mwm := k2.get_mouse_wheel_delta()

		if mwm > 0 {
			editor_bg_current_idx += 1
		} else if mwm < 0 {
			editor_bg_current_idx -= 1
		}

		editor_bg_current_idx = clamp(editor_bg_current_idx, 0, len(bg_object_textures) - 1)

		if k2.mouse_button_went_down(.Left) {
			pos := linalg.floor(mouse_pos_world)

			append(&current_room.background_objects, Background_Object {
				texture_index = editor_bg_current_idx,
				pos = pos,
			})
		}

		hovered_existing := -1

		for bgo, bgo_idx in current_room.background_objects {
			bg_tex := bg_object_textures[bgo.texture_index]
			tex_rect := k2.get_texture_rect(bg_tex)
			tex_rect.x = bgo.pos.x - tex_rect.w/2
			tex_rect.y = bgo.pos.y - tex_rect.h/2

			if k2.point_in_rect(mouse_pos_world, tex_rect) {
				k2.draw_rect(tex_rect, k2.color_alpha(k2.RED, 128))
				hovered_existing = bgo_idx

				if k2.mouse_button_went_down(.Right) {
					unordered_remove(&current_room.background_objects, bgo_idx)
					break
				}
			}
		}

		if hovered_existing == -1 {
			bg_tex := bg_object_textures[editor_bg_current_idx]
			k2.draw_texture(bg_tex, linalg.floor(mouse_pos_world), k2.rect_middle(k2.get_texture_rect(bg_tex)))
		}
	}

	for bgo in current_room.background_objects {
		tex_idx := bgo.texture_index

		if tex_idx < 0 || tex_idx >= len(bg_object_textures) {
			continue
		}

		tex := bg_object_textures[tex_idx]
		k2.draw_texture(tex, bgo.pos, origin = k2.rect_middle(k2.get_texture_rect(tex)))
	}

	for x in 0..<(ROOM_TILE_WIDTH+1) {
		for y in 0..<(ROOM_TILE_HEIGHT+1) {
			dual_grid_draw(editor_world, x, y)
		}
	}

	for fgo in current_room.foreground_objects {
		tex_idx := fgo.texture_index

		if tex_idx < 0 || tex_idx >= len(fg_object_textures) {
			continue
		}

		tex := fg_object_textures[tex_idx]
		k2.draw_texture(tex, fgo.pos, origin = k2.rect_bottom_middle(k2.get_texture_rect(tex)))
	}

	for interactable in current_room.interactables {
		tex := interactable_type_texture[interactable.type]
		k2.draw_texture(tex, interactable.pos, origin = k2.rect_bottom_middle(k2.get_texture_rect(tex)))
	}

	if edit_mode == .Foreground_Objects {
		mwm := k2.get_mouse_wheel_delta()

		if mwm > 0 {
			editor_fg_current_idx += 1
		} else if mwm < 0 {
			editor_fg_current_idx -= 1
		}

		editor_fg_current_idx = clamp(editor_fg_current_idx, 0, len(fg_object_textures) - 1)

		if k2.mouse_button_went_down(.Left) {
			pos := linalg.floor(mouse_pos_world)

			append(&current_room.foreground_objects, Foreground_Object {
				texture_index = editor_fg_current_idx,
				pos = pos,
			})
		}

		hovered_existing := -1

		for fgo, fgo_idx in current_room.foreground_objects {
			fg_tex := fg_object_textures[fgo.texture_index]
			tex_rect := k2.get_texture_rect(fg_tex)
			tex_rect.x = fgo.pos.x - tex_rect.w/2
			tex_rect.y = fgo.pos.y - tex_rect.h

			if k2.point_in_rect(mouse_pos_world, tex_rect) {
				k2.draw_rect(tex_rect, k2.color_alpha(k2.RED, 128))
				hovered_existing = fgo_idx

				if k2.mouse_button_went_down(.Right) {
					unordered_remove(&current_room.foreground_objects, fgo_idx)
					break
				}
			}
		}

		if hovered_existing == -1 {
			fg_tex := fg_object_textures[editor_fg_current_idx]
			k2.draw_texture(fg_tex, linalg.floor(mouse_pos_world), k2.rect_bottom_middle(k2.get_texture_rect(fg_tex)))
		}
	}

	if edit_mode == .Interactables {
		mwm := k2.get_mouse_wheel_delta()

		type := int(editor_interactable_current_type)

		if mwm > 0 {
			type += 1
		} else if mwm < 0 {
			type -= 1
		}

		type = clamp(type, 0, len(Interactable_Type) - 1)
		editor_interactable_current_type = Interactable_Type(type)

		if k2.mouse_button_went_down(.Left) {
			pos := linalg.floor(mouse_pos_world)

			append(&current_room.interactables, Interactable {
				type = editor_interactable_current_type,
				pos = pos,
			})
		}

		hovered_existing := -1

		for interactable, interactable_idx in current_room.interactables {
			i_tex := interactable_type_texture[interactable.type]
			tex_rect := k2.get_texture_rect(i_tex)
			tex_rect.x = interactable.pos.x - tex_rect.w/2
			tex_rect.y = interactable.pos.y - tex_rect.h

			if k2.point_in_rect(mouse_pos_world, tex_rect) {
				k2.draw_rect(tex_rect, k2.color_alpha(k2.RED, 128))
				hovered_existing = interactable_idx

				if k2.mouse_button_went_down(.Right) {
					unordered_remove(&current_room.interactables, interactable_idx)
					break
				}
			}
		}

		if hovered_existing == -1 {
			i_tex := interactable_type_texture[editor_interactable_current_type]
			k2.draw_texture(i_tex, linalg.floor(mouse_pos_world), k2.rect_bottom_middle(k2.get_texture_rect(i_tex)))
		}
	}

	k2.set_camera(ui_camera)

	ui_mp := k2.screen_to_world(k2.get_mouse_position(), ui_camera)
	top_bar := k2.Rect {0, 0, SCREEN_WIDTH, STATUS_BAR_HEIGHT}
	k2.draw_rect(top_bar, CLEAR_COLOR)
	top_bar = k2.rect_shrink(top_bar, 1, 1)

	edit_mode_names := [len(Edit_Mode)]string {
		"Tiles",
		"BG",
		"FG",
		"Interact",
	}

	edit_modes: [len(Edit_Mode)]Edit_Mode
	
	for m in Edit_Mode {
		edit_modes[m] = m
	}

	edit_mode_selector_rect := k2.rect_cut_left(&top_bar, editor_ui_state_selector_width(edit_mode_names[:]), 3)
	edit_mode_selector_rect = k2.rect_shrink(edit_mode_selector_rect, 0, 3)

	new_mode, mode_changed := editor_ui_state_selector(
		edit_mode_selector_rect,
		edit_modes[:],
		edit_mode_names[:],
		edit_mode,
	)

	if mode_changed {
		edit_mode = new_mode
	}

	switch edit_mode {
	case .Tiles:

	case .Background_Objects:
		tex := bg_object_textures[editor_bg_current_idx]
		src := k2.get_texture_rect(tex)
		dst := k2.rect_shrink(k2.rect_cut_left(&top_bar, top_bar.h, 5), 4, 4)
		k2.draw_texture_fit(tex, src, dst)
		k2.draw_text("Wheel ^v", k2.rect_top_left(top_bar) + EDITOR_FONT_SIZE/2, EDITOR_FONT_SIZE, k2.WHITE)

	case .Foreground_Objects:
		tex := fg_object_textures[editor_fg_current_idx]
		src := k2.get_texture_rect(tex)
		dst := k2.rect_shrink(k2.rect_cut_left(&top_bar, top_bar.h, 5), 4, 4)
		k2.draw_texture_fit(tex, src, dst)
		k2.draw_text("Wheel ^v", k2.rect_top_left(top_bar) + EDITOR_FONT_SIZE/2, EDITOR_FONT_SIZE, k2.WHITE)

	case .Interactables:
		tex := interactable_type_texture[editor_interactable_current_type]
		src := k2.get_texture_rect(tex)
		dst := k2.rect_shrink(k2.rect_cut_left(&top_bar, top_bar.h, 5), 4, 4)
		k2.draw_texture_fit(tex, src, dst)
		k2.draw_text("Wheel ^v", k2.rect_top_left(top_bar) + EDITOR_FONT_SIZE/2, EDITOR_FONT_SIZE, k2.WHITE)
	}

	map_origin := Vec2{200, 2}

	for _, r_idx in editor_world.rooms {
		x := r_idx % WORLD_WIDTH
		y := r_idx / WORLD_WIDTH

		pos := map_origin + Vec2{f32(x)*6,f32(y)*6}

		map_square_color := SPACE_COLOR

		if r_idx == current_room_idx {
			map_square_color = HIGHLIGHT_COLOR
		}

		r := k2.rect_from_pos_size(pos, {5, 5})

		if k2.point_in_rect(ui_mp, r) {
			map_square_color = k2.YELLOW

			if k2.mouse_button_went_down(.Left) {
				current_room_idx = r_idx
			}
		}

		k2.draw_rect(r, map_square_color)
	}

	k2.present()
}

editor_save :: proc() {
	world_json, world_json_error := json.marshal(editor_world, opt = {sort_maps_by_key = true, pretty = true}, allocator = context.temp_allocator)

	if world_json_error != nil {
		fmt.eprintln(world_json_error)
		return
	}

	write_world_ok := write_file(WORLD_FILE_NAME, world_json)

	if !write_world_ok {
		when ODIN_OS != .JS {
			fmt.eprintln("Failed writing 'world.json'")
		}
		return
	}
}

editor_ui_state_selector_width :: proc(state_names: []string) -> f32 {
	total_width: f32

	for s in state_names {
		total_width += k2.measure_text(s, EDITOR_FONT_SIZE).x + 2 * STATE_SELECTOR_TEXT_MARGIN
	}

	return total_width
}

EDITOR_FONT_SIZE :: 10

STATE_SELECTOR_TEXT_MARGIN :: 5

editor_ui_state_selector :: proc(
	rect: k2.Rect,
	states: []$T,
	state_names: []string,
	cur_state: T,
	label: string = ""
) -> (T, bool) {
	rect := rect

	if len(states) == 0 {
		return cur_state, false
	}

	if len(states) != len(state_names) {
		return cur_state, false
	}
	
	r := rect
	k2.draw_rect(r, k2.GRAY)
	new_state := cur_state
	changed := false

	needed_width := editor_ui_state_selector_width(state_names)

	extra_button_width: f32
	if rect.w > needed_width {
		extra_button_width = (rect.w - needed_width)/f32(len(states))
	}

	for s, s_idx in states {
		button_size := k2.measure_text(state_names[s_idx], EDITOR_FONT_SIZE)
		button_rect := k2.rect_cut_left(&r, button_size.x + STATE_SELECTOR_TEXT_MARGIN * 2 + extra_button_width, 0)

		if k2.point_in_rect(k2.get_mouse_position() / ui_camera.zoom, button_rect) {
			k2.draw_rect(button_rect, k2.BLUE)

			if k2.mouse_button_went_down(.Left) {
				if new_state != s {
					changed = true
					new_state = s   
				}
			}
		}

		if cur_state == s || new_state == s {
			k2.draw_rect(button_rect, k2.GREEN)
		}

		k2.draw_text(
			state_names[s_idx],
			{button_rect.x + button_rect.w/2 - k2.measure_text(state_names[s_idx], EDITOR_FONT_SIZE).x/2, button_rect.y + button_rect.h/2 - EDITOR_FONT_SIZE/2},
			EDITOR_FONT_SIZE,
			k2.WHITE,
		)
	}

	k2.draw_rect_outline(rect, 1, k2.WHITE)
	return new_state, changed
}