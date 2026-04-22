package space_cat

import k2 "../.."
import "core:math/linalg"
import "core:math"
import "core:encoding/json"
import "core:os"
import "core:fmt"

CLEAR_COLOR :: k2.Color{6, 6, 8, 255}
SKY_COLOR :: k2.Color{28, 38, 56, 255}
GROUND_COLOR :: k2.Color{35, 73, 93, 255}
WALL_COLOR :: k2.Color{28, 38, 56, 255}
HIGHLIGHT_COLOR :: k2.Color{149, 224, 204, 255}

SCREEN_WIDTH :: 240
SCREEN_HEIGHT :: 180
STATUS_BAR_HEIGHT :: 20

Vec2 :: k2.Vec2

Player :: struct {
	pos: Vec2,
	tex: k2.Texture,
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

Direction :: enum {
	East,
	West,
}

player: Player
current_room_idx: int
editing: bool
camera: k2.Camera
space_tileset: k2.Texture

WORLD_WIDTH :: 2
WORLD_HEIGHT :: 3

World :: struct {
	rooms: [WORLD_WIDTH*WORLD_HEIGHT]Room,
}

world: World

main :: proc() {
	k2.init(SCREEN_WIDTH*4, SCREEN_HEIGHT*4, "SPACE CAT", options = {window_mode = .Windowed_Resizable})
	current_room_idx = 4
	space_tileset = k2.load_texture_from_file("space_tileset.png")

	world_json_data, world_json_data_err := os.read_entire_file("world.json", context.temp_allocator)

	if world_json_data_err == nil {
		json.unmarshal(world_json_data, &world)
	}

	player = {
		pos = {30, 100},
		tex = k2.load_texture_from_file("cat.png"),
	}

	for k2.update() {
		if k2.key_went_down(.F2) {
			if editing {
				editor_save()
			}

			editing = !editing
		}

		camera = {
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
	}

	player.pos += movement * k2.get_frame_time() * 50

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

	player_mid_x := player.pos.x + f32(player.tex.width)/2

	if player_mid_x < 0 {
		room_move_x -= 1
	}

	if player_mid_x > ROOM_WIDTH {
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
	k2.clear(CLEAR_COLOR)

	k2.set_camera(camera)
	k2.draw_rect(
		{
			0,
			STATUS_BAR_HEIGHT,
			SCREEN_WIDTH,
			SCREEN_HEIGHT - STATUS_BAR_HEIGHT,
		},
		SKY_COLOR,
	)

	current_room := &world.rooms[current_room_idx]

	for tile, tile_idx in current_room.tiles {
		x := tile_idx % ROOM_TILE_WIDTH
		y := tile_idx / ROOM_TILE_WIDTH

		/*tile_type :: proc(x, y: int, cur: Tile_Type) -> Tile_Type {
			if x < 0 || y < 0 || x >= ROOM_WIDTH || y >= ROOM_WIDTH {
				return .Space
			}

			return current_room.tiles[y*ROOM_WIDTH+x]
		}

		mask := 0

		t := current_room.tiles[tile_idx]

		if tile_type(x-1, y-1, t) == .Space {
			mask |= 1 // TL
		}
		if tile_type(x, y-1, t) == .Space {
			mask |= 2 // TR
		}
		if tile_type(x, y, t) == .Space {
			mask |= 4 // BR
		}
		if tile_type(x-1, y, t) == .Space {
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
		}*/

		// Note the half-tile offset here: This is what "undoes" the half-tile offset that dual
		// tile grids need.
		pos := k2.Vec2 {
			f32(x) * TILE_SIZE,
			f32(y) * TILE_SIZE + STATUS_BAR_HEIGHT,
		}

		// Always draw "grass" below the tile, as they have transparent pixels.


		color := GROUND_COLOR

		if tile == .Space {
			color = SKY_COLOR
		}

		k2.draw_rect(k2.rect_from_pos_size(pos, {TILE_SIZE, TILE_SIZE}), color)
	}

	player_tex_rect := k2.get_texture_rect(player.tex)
	if player.dir == .West {
		player_tex_rect.w *= -1
	}
	k2.draw_texture_section(player.tex, player_tex_rect, player.pos)

	k2.draw_rect({0, 0, SCREEN_WIDTH, STATUS_BAR_HEIGHT}, CLEAR_COLOR)

	map_origin := Vec2{200, 2}

	for _, r_idx in world.rooms {
		x := r_idx % WORLD_WIDTH
		y := r_idx / WORLD_WIDTH

		pos := map_origin + Vec2{f32(x)*6,f32(y)*6}

		map_square_color := SKY_COLOR

		if r_idx == current_room_idx {
			map_square_color = HIGHLIGHT_COLOR
		}

		k2.draw_rect(k2.rect_from_pos_size(pos, {5, 5}), map_square_color)
	}

	k2.present()
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
	mouse_pos_world := k2.screen_to_world(k2.get_mouse_position(), camera)
	grid_x := int(math.floor(mouse_pos_world.x / TILE_SIZE))
	grid_y := int(math.floor(mouse_pos_world.y / TILE_SIZE))
	hovered_grid_rect: k2.Rect

	current_room := &world.rooms[current_room_idx]

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

	k2.clear(CLEAR_COLOR)
	k2.set_camera(camera)

	
	for tile, tile_idx in current_room.tiles {
		x := tile_idx % ROOM_TILE_WIDTH
		y := tile_idx / ROOM_TILE_WIDTH

		/*tile_type :: proc(x, y: int, cur: Tile_Type) -> Tile_Type {
			if x < 0 || y < 0 || x >= ROOM_WIDTH || y >= ROOM_WIDTH {
				return .Space
			}

			return current_room.tiles[y*ROOM_WIDTH+x]
		}

		mask := 0

		t := current_room.tiles[tile_idx]

		if tile_type(x-1, y-1, t) == .Space {
			mask |= 1 // TL
		}
		if tile_type(x, y-1, t) == .Space {
			mask |= 2 // TR
		}
		if tile_type(x, y, t) == .Space {
			mask |= 4 // BR
		}
		if tile_type(x-1, y, t) == .Space {
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
		}*/

		// Note the half-tile offset here: This is what "undoes" the half-tile offset that dual
		// tile grids need.
		pos := k2.Vec2 {
			f32(x) * TILE_SIZE,
			f32(y) * TILE_SIZE,
		}

		// Always draw "grass" below the tile, as they have transparent pixels.


		color := GROUND_COLOR

		if tile == .Space {
			color = SKY_COLOR
		}

		k2.draw_rect(k2.rect_from_pos_size(pos, {TILE_SIZE, TILE_SIZE}), color)
	}

	k2.draw_rect(hovered_grid_rect, {255, 255, 255, 128})
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