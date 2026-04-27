package space_cat

import k2 "../.."
import "core:math/linalg"
import "core:encoding/json"
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
	background_objects: [dynamic]Background_Object,
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

WORLD_FILE_NAME :: "world.json"
WORLD_WIDTH :: 2
WORLD_HEIGHT :: 3

World :: struct {
	rooms: [WORLD_WIDTH*WORLD_HEIGHT]Room,
}

Background_Object :: struct {
	texture_index: int,
	pos: Vec2,
}

world: World

main :: proc() {
	init()
	for step() {}
	shutdown()
}

init :: proc() {
	k2.init(SCREEN_WIDTH*4, SCREEN_HEIGHT*4, "SPACE CAT", options = {window_mode = .Windowed_Resizable})
	current_room_idx = 4
	space_tileset = k2.load_texture_from_bytes(#load("space_tileset.png"))
	bg_objects = {
		k2.load_texture_from_bytes(#load("star_1.png")),
		k2.load_texture_from_bytes(#load("star_2.png")),
		k2.load_texture_from_bytes(#load("star_3.png")),
		k2.load_texture_from_bytes(#load("star_4.png")),
		k2.load_texture_from_bytes(#load("star_5.png")),
		k2.load_texture_from_bytes(#load("moon.png")),
	}
	space_tileset_version = file_version("space_tileset.png")

	world_json_data, world_json_data_ok := get_file_contents(WORLD_FILE_NAME)

	if world_json_data_ok {
		json.unmarshal(world_json_data, &world)
	}

	player = {
		pos = {30, 100},
		tex_east_west = k2.load_texture_from_bytes(#load("cat_east_west.png")),
		tex_up = k2.load_texture_from_bytes(#load("cat_up.png")),
		tex_down = k2.load_texture_from_bytes(#load("cat_down.png")),
	}
}

step :: proc() -> bool {
	if !k2.update() {
		return false
	}

	when ODIN_OS != .JS {
		space_tileset_new_version := file_version("space_tileset.png")

		if space_tileset_version != space_tileset_new_version {
			k2.destroy_texture(space_tileset)
			space_tileset = k2.load_texture_from_file("space_tileset.png")
		}
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

	return true
}

shutdown :: proc() {
	for r in world.rooms {
		delete(r.background_objects)
	}

	for bgo in bg_objects {
		k2.destroy_texture(bgo)	
	}

	k2.destroy_texture(space_tileset)
	k2.destroy_texture(player.tex_east_west)
	k2.destroy_texture(player.tex_up)
	k2.destroy_texture(player.tex_down)
	
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

	for bgo in world.rooms[current_room_idx].background_objects {
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