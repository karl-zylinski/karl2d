// Implements some a very basic Immediate Mode Graphical User Interface (IMGUI). Made during this
// stream, but modified afterwards: https://www.youtube.com/watch?v=F3dd2_XNEuM 
//
// There is a text input, a button and a resizable splitter.

package ui_playground

import k2 "../.."
import "core:strings"
import "core:unicode/utf8"

COLOR_MAIN_BG :: k2.Color { 22, 22, 22, 255 }
COLOR_PANEL_BG :: k2.Color { 44, 44, 44, 255 }
COLOR_LINES :: k2.Color { 144, 144, 144, 255 }
COLOR_CONTROL_BG :: k2.Color { 44, 44, 44, 255 }
COLOR_CONTROL_BG_HOVER :: k2.Color { 66, 66, 66, 255 }
COLOR_CONTROL_BG_ACTIVE :: k2.Color { 99, 99, 99, 255 }
COLOR_CONTROL_BG_DISABLED :: k2.Color { 111, 111, 111, 255 }
COLOR_TEXT_DISABLED :: k2.Color { 180, 180, 180, 255 }

INITIAL_SCREEN_WIDTH :: 1280 

added_texts: [dynamic]string
panel_splitter_x := f32(400)
text_field: string

main :: proc() {
	init()
	for step() {}
	shutdown()
}

init :: proc() {
	k2.init(INITIAL_SCREEN_WIDTH, 720, "UI Playground", { window_mode = .Windowed_Resizable })
}

step :: proc() -> bool {
	if !k2.update() {
		return false
	}

	k2.clear(COLOR_MAIN_BG)

	// Camera used to scale up the UI to the ui_scale, which is just equal to k2.get_window_scale().
	ui_cam := k2.Camera {
		zoom = ui_scale(),
	}

	k2.set_camera(ui_cam)
	ui_reset()

	// Full screen rectangle
	r := k2.rect_from_pos_size({0, 0}, k2.screen_to_camera(k2.get_screen_size(), ui_cam))
	left_panel, right_panel := ui_horizontal_splitter(r, &panel_splitter_x)

	left_panel = k2.rect_shrink(left_panel, 4, 4)
	right_panel = k2.rect_shrink(right_panel, 4, 4)

	row := k2.rect_cut_top(&right_panel, 30, 5)
	text_box_rect := k2.rect_shrink(row, 4, 4)
	new_text, has_new_text := ui_text_box(text_box_rect, text_field)

	if has_new_text {
		append(&added_texts, strings.clone(new_text))
		text_field = ""
	}

	any_texts := len(added_texts) > 0

	if !any_texts {
		row = k2.rect_shrink(k2.rect_cut_top(&right_panel, 30, 0), 2, 2)
		k2.draw_text("Type text into field and press enter...", {row.x, row.y}, 13, k2.WHITE)
	}

	for t in added_texts {
		row = k2.rect_shrink(k2.rect_cut_top(&left_panel, 30, 0), 2, 2)
		k2.draw_text(t, {row.x, row.y}, 26, k2.WHITE)
	}

	row = k2.rect_cut_top(&left_panel, 30, 0)
	button_rect := k2.rect_shrink(row, 4, 4)

	if ui_button(button_rect, "Remove!", disabled = !any_texts) {
		if any_texts {
			last_idx := len(added_texts) - 1
			delete(added_texts[last_idx])
			unordered_remove(&added_texts, last_idx)
		}
	}

	k2.present()
	return true
}

shutdown :: proc() {
	k2.shutdown()
}

UI_ID :: distinct u64

UI_ID_None :: UI_ID(0)

ACTIVE_STATE_MAX_SIZE :: 1024

UI :: struct {
	active_state: [ACTIVE_STATE_MAX_SIZE]byte,
	active_id: UI_ID,
	next_active_id: UI_ID,
	next_active_state: [ACTIVE_STATE_MAX_SIZE]byte,
	id_counter: UI_ID,
}

UI_State_Splitter :: struct {
	start_x: f32,
}

UI_State_Textbox :: struct {
	buf: [ACTIVE_STATE_MAX_SIZE - size_of(int)]byte,
	buf_len: int,
}

ui_scale :: proc() -> f32 {
	return k2.get_window_scale()
}

ui: UI

// Each control gets an ID from a counter. This design can be improved. If an element appears before
// another one due to dynamic UI, then the ui.active_id can start pointing at the wrong thing.
//
// Improvement suggestions: Some kind of ID based on #caller_location + a counter, or giving each
// control a name.
ui_next_id :: proc() -> UI_ID {
	ui.id_counter += 1
	return ui.id_counter
}

ui_reset :: proc() {
	ui.id_counter = 0

	if ui.active_id != ui.next_active_id {
		ui.active_id = ui.next_active_id
		ui.active_state = ui.next_active_state
	}
}

ui_clear_active :: proc() {
	ui.next_active_state = {}
	ui.next_active_id = UI_ID_None
}

ui_set_next_active :: proc(id: UI_ID, state: $T) {
	assert(id != UI_ID_None, "Use ui_clear_active")	
	assert(size_of(T) <= ACTIVE_STATE_MAX_SIZE)
	ui.next_active_id = id
	ui.next_active_state = {}
	state_ptr := (^T)(raw_data(&ui.next_active_state))
	state_ptr^ = state
}

ui_get_active_state :: proc(id: UI_ID, $T: typeid) -> (^T, bool) #optional_ok {
	assert(size_of(T) <= ACTIVE_STATE_MAX_SIZE)

	if id == ui.active_id {
		return (^T)(raw_data(&ui.active_state)), true
	}

	return nil, false
}

ui_mouse_pos :: proc() -> k2.Vec2 {
	scl := ui_scale()
	mp := k2.get_mouse_position()

	if scl == 0 {
		return mp
	}

	return mp / scl
}

ui_horizontal_splitter :: proc(
	r: k2.Rect,
	x: ^f32,
) -> (
	_left: k2.Rect,
	_right: k2.Rect,
) {
	id := ui_next_id()

	left, right := k2.rect_split_left(r, x^, 0)
	drag_handle_rect := k2.rect_from_pos_size(
		{right.x - 5, right.y},
		{10, right.h},
	)

	k2.draw_rect(right, COLOR_PANEL_BG)
	mp := ui_mouse_pos()
	k2.set_cursor(.Default)

	state, is_active := ui_get_active_state(id, UI_State_Splitter)
	hovering_drag_handle := k2.point_in_rect(mp, drag_handle_rect)

	if hovering_drag_handle {
		k2.draw_rect(k2.rect_shrink(drag_handle_rect, 1, 0), {120, 120, 200, 120})
	}

	if is_active {
		k2.set_cursor(.Resize_EW)
		x^ = mp.x

		if k2.key_went_down(.Escape) {
			x^ = state.start_x
			ui_clear_active()
		}

		if k2.mouse_button_went_up(.Left) {
			ui_clear_active()
		}
	} else {
		if hovering_drag_handle {
			k2.set_cursor(.Resize_EW)

			if k2.mouse_button_went_down(.Left) {
				ui_set_next_active(id, UI_State_Splitter {
					start_x = mp.x,
				})
			}
		}
	}

	return left, right
}

ui_text_box :: proc(r: k2.Rect, initial_text: string) -> (string, bool) {
	bg_color := k2.WHITE
	border_color := COLOR_LINES

	id := ui_next_id()
	state, is_active := ui_get_active_state(id, UI_State_Textbox)
	text := initial_text
	commit := false

	if is_active {
		border_color = k2.BLACK
		typed_runes := k2.get_typed_runes()

		for r in typed_runes {
			bytes, len := utf8.encode_rune(r)

			if len > 0 {
				copy(state.buf[state.buf_len:], bytes[:len])
				state.buf_len += len
			}
		}

		text = string(state.buf[:state.buf_len])

		if k2.key_went_down(.Backspace, allow_repeat = true) {
			if state.buf_len > 0 {
				_, r_len := utf8.decode_last_rune(text)
				state.buf_len -= r_len
			}
		}

		if k2.key_went_down(.Enter) {
			ui_clear_active()
			commit = true
		}
	} else {
		mp := ui_mouse_pos()

		if k2.point_in_rect(mp, r) {
			border_color = k2.BLACK

			if k2.mouse_button_went_down(.Left) {
				new_state: UI_State_Textbox
				copy(new_state.buf[:], transmute([]u8)(text))
				new_state.buf_len = len(text)
				ui_set_next_active(id, new_state)
			}
		}

		if text == "" {
			text = "Type..."
		}
	}

	k2.draw_rect(r, bg_color)
	k2.draw_rect_outline(r, 1, border_color)
	k2.draw_text(text, {r.x + 2, r.y + 2}, r.h - 4, k2.BLACK)

	return text, commit
}

ui_button :: proc(r: k2.Rect, text: string, disabled: bool) -> bool {
	mp := ui_mouse_pos()
	in_rect := k2.point_in_rect(mp, r)

	bg_color := COLOR_CONTROL_BG
	border_color := COLOR_LINES
	text_color := k2.WHITE
	clicked: bool

	if disabled {
		bg_color = COLOR_CONTROL_BG_DISABLED
		text_color = COLOR_TEXT_DISABLED
	} else {
		if in_rect {
			bg_color = COLOR_CONTROL_BG_HOVER

			if in_rect && k2.mouse_button_is_held(.Left) {
				bg_color = COLOR_CONTROL_BG_ACTIVE
			}

			clicked = k2.mouse_button_went_down(.Left)
		}
	}
	
	k2.draw_rect(r, bg_color)
	k2.draw_rect_outline(r, 1, border_color)

	text_width := k2.measure_text(text, r.h).x
	k2.draw_text(text, {r.x + r.w/2 - text_width/2, r.y}, r.h, text_color)
	return clicked
}
