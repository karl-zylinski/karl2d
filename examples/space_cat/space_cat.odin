package space_cat

import k2 "../.."
import "core:math/linalg"
import "core:math"
import "core:encoding/json"
import "core:os"
import "core:fmt"
import "core:time"

CLEAR_COLOR :: k2.Color{6, 6, 8, 255}
SPACE_COLOR :: k2.Color{28, 38, 56, 255}
GROUND_COLOR :: k2.Color{35, 73, 93, 255}
HIGHLIGHT_COLOR :: k2.Color{149, 224, 204, 255}

SCREEN_WIDTH :: 240
SCREEN_HEIGHT :: 180
STATUS_BAR_HEIGHT :: 20

Vec2 :: k2.Vec2

Player :: struct {
	pos: Vec2,
	tex_east_west: k2.Texture,
	tex_up: k2.Texture,
	tex_down: k2.Texture,
	dir: Direction,
}

// Counted in tiles
ROOM_TILE_WIDTH :: 15
ROOM_TILE_HEIGHT :: 10
TILE_SIZE :: 16

Room :: struct {
	tiles: [ROOM_TILE_WIDTH*ROOM_TILE_HEIGHT]Tile_Type,
}

Tile_Type :: enum {
	Ground,
	Space,
}

tile_walkable_lookup := [Tile_Type]bool {
	.Ground = true,
	.Space = false,
}

Direction :: enum {
	East,
	West,
	North,
	South,
}

player: Player
current_room_idx: int
editing: bool
game_camera: k2.Camera
ui_camera: k2.Camera
space_tileset: k2.Texture
space_tileset_version: time.Time

bg_objects: [6]k2.Texture

Edit_Mode :: enum {
	Tiles,
	Background_Objects,
}

edit_mode: Edit_Mode

WORLD_WIDTH :: 2
WORLD_HEIGHT :: 3

World :: struct {
	rooms: [WORLD_WIDTH*WORLD_HEIGHT]Room,
	background_objects: []Background_Object,
}

Background_Object :: struct {
	texture_index: int,
	pos: Vec2,
}

world: World

main :: proc() {
	k2.init(SCREEN_WIDTH*4, SCREEN_HEIGHT*4, "SPACE CAT", options = {window_mode = .Windowed_Resizable})
	current_room_idx = 4
	space_tileset = k2.load_texture_from_file("space_tileset.png")
	bg_objects = {
		k2.load_texture_from_file("star_1.png"),
		k2.load_texture_from_file("star_2.png"),
		k2.load_texture_from_file("star_3.png"),
		k2.load_texture_from_file("star_4.png"),
		k2.load_texture_from_file("star_5.png"),
		k2.load_texture_from_file("moon.png"),
	}
	space_tileset_version, _ = os.modification_time_by_path("space_tileset.png")

	world_json_data, world_json_data_err := os.read_entire_file("world.json", context.temp_allocator)

	if world_json_data_err == nil {
		json.unmarshal(world_json_data, &world)
	}

	player = {
		pos = {30, 100},
		tex_east_west = k2.load_texture_from_file("cat_east_west.png"),
		tex_up = k2.load_texture_from_file("cat_up.png"),
		tex_down = k2.load_texture_from_file("cat_down.png"),
	}

	for k2.update() {
		space_tileset_new_version, _ := os.modification_time_by_path("space_tileset.png")

		if space_tileset_version != space_tileset_new_version {
			k2.destroy_texture(space_tileset)
			space_tileset = k2.load_texture_from_file("space_tileset.png")
		}

		if k2.key_went_down(.F2) {
			if editing {
				editor_save()
			}

			editing = !editing
		}

		game_camera = {
			zoom = f32(k2.get_screen_height())/SCREEN_HEIGHT,
			target = {0, -STATUS_BAR_HEIGHT},
		}

		ui_camera = {
			zoom = f32(k2.get_screen_height())/SCREEN_HEIGHT,
		}

		if editing {
			editor_update()
		} else {
			update()
			draw()
		}
	}

	k2.shutdown()
}

calc_player_collider :: proc(player_pos: Vec2) -> k2.Rect {
	return {
		player_pos.x - 5,
		player_pos.y - 3,
		10,
		6,
	}
}

update :: proc() {
	movement: Vec2

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

	movement = linalg.normalize0(movement)

	if movement.x > 0 {
		player.dir = .East
	} else if movement.x < 0 {
		player.dir = .West
	} else if movement.y > 0 {
		player.dir = .South
	} else if movement.y < 0 {
		player.dir = .North
	}

	to_move := movement * k2.get_frame_time() * 50

	player.pos.x += to_move.x

	current_room := world.rooms[current_room_idx]

	for tile_type, tile_idx in current_room.tiles {
		if tile_walkable_lookup[tile_type] {
			continue
		}

		tile_pos := k2.Vec2 {
			f32(tile_idx % ROOM_TILE_WIDTH) * TILE_SIZE,
			f32(tile_idx / ROOM_TILE_WIDTH) * TILE_SIZE,
		}

		tile_rect := k2.rect_from_pos_size(tile_pos, {TILE_SIZE, TILE_SIZE})
		pc := calc_player_collider(player.pos)
		overlap, overlapping := k2.rect_overlap(pc, tile_rect)

		if overlapping && overlap.w != 0 {
			sign: f32 = pc.x + pc.w / 2 < (tile_rect.x + tile_rect.w / 2) ? -1 : 1
			fix := overlap.w * sign
			player.pos.x += fix
		}
	}

	player.pos.y += to_move.y

	for tile_type, tile_idx in current_room.tiles {
		if tile_walkable_lookup[tile_type] {
			continue
		}
		
		tile_pos := k2.Vec2 {
			f32(tile_idx % ROOM_TILE_WIDTH) * TILE_SIZE,
			f32(tile_idx / ROOM_TILE_WIDTH) * TILE_SIZE,
		}

		tile_rect := k2.rect_from_pos_size(tile_pos, {TILE_SIZE, TILE_SIZE})
		pc := calc_player_collider(player.pos)
		overlap, overlapping := k2.rect_overlap(pc, tile_rect)

		if overlapping && overlap.h != 0 {
			sign: f32 = pc.y + pc.h / 2 < (tile_rect.y + tile_rect.h / 2) ? -1 : 1
			fix := overlap.h * sign
			player.pos.y += fix
		}
	}

	ROOM_HEIGHT :: ROOM_TILE_HEIGHT * TILE_SIZE
	ROOM_WIDTH :: ROOM_TILE_WIDTH * TILE_SIZE

	room_move_x := 0
	room_move_y := 0

	if player.pos.y < 0 {
		room_move_y -= 1
	}

	if player.pos.y > ROOM_HEIGHT {
		room_move_y += 1
	}

	if player.pos.x < 0 {
		room_move_x -= 1
	}

	if player.pos.x > ROOM_WIDTH {
		room_move_x += 1
	}

	if room_move_x != 0 || room_move_y != 0 {
		room_x := current_room_idx % WORLD_WIDTH + room_move_x
		room_y := current_room_idx / WORLD_WIDTH + room_move_y

		if (
			room_x >= 0 &&
			room_x < WORLD_WIDTH &&
			room_y >= 0 &&
			room_y < WORLD_HEIGHT
		) {
			new_idx := room_y * WORLD_WIDTH + room_x
			assert(new_idx >= 0 && new_idx < len(world.rooms))
			current_room_idx = new_idx
			player.pos -= {
				f32(room_move_x * ROOM_WIDTH),
				f32(room_move_y * ROOM_HEIGHT),
			}
		}
	}
}

draw :: proc() {
	k2.clear(SPACE_COLOR)

	k2.set_camera(game_camera)
	
	STARS_PER_DIR :: 4

	for bgo in world.background_objects {
		tex_idx := bgo.texture_index

		if tex_idx < 0 || tex_idx >= len(bg_objects) {
			continue
		}

		tex := bg_objects[tex_idx]
		k2.draw_texture(tex, bgo.pos, origin = k2.rect_middle(k2.get_texture_rect(tex)))
	}

	for x in 0..<(ROOM_TILE_WIDTH+1) {
		for y in 0..<(ROOM_TILE_HEIGHT+1) {
			dual_grid_draw(x, y)
		}
	}

	player_tex: k2.Texture
	flip_x := false
	
	switch player.dir {
	case .East:
		player_tex = player.tex_east_west
	case .West:
		player_tex = player.tex_east_west
		flip_x = true
	case .North:
		player_tex = player.tex_up
	case .South:
		player_tex = player.tex_down
	}

	player_tex_rect := k2.get_texture_rect(player_tex)

	if flip_x {
		player_tex_rect.w *= -1
	}

	k2.draw_texture_section(
		player_tex,
		player_tex_rect,
		player.pos,
		origin = {f32(player_tex.width/2), f32(player_tex.height)-2},
	)

	k2.set_camera(ui_camera)
	k2.draw_rect({0, 0, SCREEN_WIDTH, STATUS_BAR_HEIGHT}, CLEAR_COLOR)

	map_origin := Vec2{200, 2}

	for _, r_idx in world.rooms {
		x := r_idx % WORLD_WIDTH
		y := r_idx / WORLD_WIDTH

		pos := map_origin + Vec2{f32(x)*6,f32(y)*6}

		map_square_color := SPACE_COLOR

		if r_idx == current_room_idx {
			map_square_color = HIGHLIGHT_COLOR
		}

		k2.draw_rect(k2.rect_from_pos_size(pos, {5, 5}), map_square_color)
	}

	k2.present()
}

dual_grid_draw :: proc(x, y: int) {
	tile_type :: proc(x, y: int) -> Tile_Type {
		if x < 0 {
			return tile_type(x + 1, y)
		}

		if x >= ROOM_TILE_WIDTH {
			return tile_type(x - 1, y)
		}

		if y < 0 {
			return tile_type(x, y + 1)
		}

		if y >= ROOM_TILE_HEIGHT {
			return tile_type(x, y - 1)
		}

		return world.rooms[current_room_idx].tiles[y*ROOM_TILE_WIDTH+x]
	}

	mask := 0

	if tile_type(x-1, y-1) == .Space {
		mask |= 1 // TL
	}
	if tile_type(x, y-1) == .Space {
		mask |= 2 // TR
	}
	if tile_type(x, y) == .Space {
		mask |= 4 // BR
	}
	if tile_type(x-1, y) == .Space {
		mask |= 8 // BL
	}

	txty := DUAL_GRID_MASK_TO_TXTY[mask]
	tx := txty.x
	ty := txty.y

	tile_rect := k2.Rect {
		x = f32(tx) * TILE_SIZE,
		y = f32(ty) * TILE_SIZE,
		w = TILE_SIZE,
		h = TILE_SIZE,
	}

	pos := k2.Vec2 {
		f32(x) * TILE_SIZE - TILE_SIZE/2,
		f32(y) * TILE_SIZE - TILE_SIZE/2,
	}

	k2.draw_texture_section(space_tileset, tile_rect, pos)
}

DUAL_GRID_MASK_TO_TXTY := [16][2]int {
	{0, 3}, // 0000
	{3, 3}, // 0001
	{0, 2}, // 0010
	{1, 2}, // 0011
	{1, 3}, // 0100
	{0, 1}, // 0101
	{1, 0}, // 0110
	{2, 2}, // 0111
	{0, 0}, // 1000
	{3, 2}, // 1001
	{2, 3}, // 1010
	{3, 1}, // 1011
	{3, 0}, // 1100
	{2, 0}, // 1101
	{1, 1}, // 1110
	{2, 1}, // 1111
}

editor_update :: proc() {
	mouse_pos_world := k2.screen_to_world(k2.get_mouse_position(), game_camera)
	grid_x := int(math.floor(mouse_pos_world.x / TILE_SIZE))
	grid_y := int(math.floor(mouse_pos_world.y / TILE_SIZE))
	hovered_grid_rect: k2.Rect

	current_room := &world.rooms[current_room_idx]

	switch edit_mode {
	case .Tiles:
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

	case .Background_Objects:
	}


	k2.clear(SPACE_COLOR)
	k2.set_camera(game_camera)
	
	for x in 0..<(ROOM_TILE_WIDTH+1) {
		for y in 0..<(ROOM_TILE_HEIGHT+1) {
			dual_grid_draw(x, y)
		}
	}

	k2.draw_rect(hovered_grid_rect, {255, 255, 255, 128})

	k2.set_camera(ui_camera)

	ui_mp := k2.screen_to_world(k2.get_mouse_position(), ui_camera)
	top_bar := k2.Rect {0, 0, SCREEN_WIDTH, STATUS_BAR_HEIGHT}
	k2.draw_rect(top_bar, CLEAR_COLOR)
	top_bar = k2.rect_shrink(top_bar, 1, 1)

	edit_mode_names := [len(Edit_Mode)]string {
		"Tiles",
		"BG",
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

	map_origin := Vec2{200, 2}

	for _, r_idx in world.rooms {
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
	world_json, world_json_error := json.marshal(world, opt = {sort_maps_by_key = true, pretty = true}, allocator = context.temp_allocator)

	if world_json_error != nil {
		fmt.eprintln(world_json_error)
		return
	}

	write_world_err := os.write_entire_file("world.json", world_json)

	if write_world_err != nil {
		fmt.eprintln(write_world_err)
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
	//rect = editor_ui_property_label(rect, label)

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