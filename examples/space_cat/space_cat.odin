package space_cat

import k2 "../.."
import "core:math/linalg"
import "core:encoding/json"
import "core:time"
import "core:math/rand"
import "core:math"
import "core:slice"
import "core:fmt"

_ :: fmt

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

Plasma_Ball :: struct {
	pos: Vec2,
	dir: Vec2,
	age: f32,
}

// Counted in tiles
ROOM_TILE_WIDTH :: 15
ROOM_TILE_HEIGHT :: 10
TILE_SIZE :: 16

Room :: struct {
	tiles: [ROOM_TILE_WIDTH*ROOM_TILE_HEIGHT]Tile_Type,
	background_objects: [dynamic]Background_Object,
	foreground_objects: [dynamic]Foreground_Object,
	interactables: [dynamic]Interactable,
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

vec2_from_direction := [Direction]Vec2 {
	.East = {1, 0},
	.West = {-1, 0},
	.North = {0, -1},
	.South = {0, 1},
}

twinkle_timer: f32
player: Player
plasma_balls: [dynamic]Plasma_Ball
current_room_idx: int
editing: bool
game_camera: k2.Camera
ui_camera: k2.Camera
space_tileset: k2.Texture
space_tileset_version: time.Time
bg_object_textures: [6]k2.Texture
fg_object_textures: [7]k2.Texture
plasma_ball_textures: [3]k2.Texture
ab_shoot: k2.Audio_Buffer

WORLD_FILE_NAME :: "world.json"
WORLD_WIDTH :: 2
WORLD_HEIGHT :: 3

World :: struct {
	rooms: [WORLD_WIDTH*WORLD_HEIGHT]Room,
}

Background_Object :: struct {
	texture_index: int,
	pos: Vec2,
	dim_timer: f32 `json:"-"`,
}

Foreground_Object :: struct {
	texture_index: int,
	pos: Vec2,
}

Interactable_Type :: enum {
	Enemy,
	Key,
	Wall,
}

Interactable :: struct {
	type: Interactable_Type,
	pos: Vec2,
	hurt_timer: f32 `json:"-"`,
}

interactable_type_texture: [Interactable_Type]k2.Texture
enemy_hidden_tex: k2.Texture

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
	bg_object_textures = {
		k2.load_texture_from_bytes(#load("star_1.png")),
		k2.load_texture_from_bytes(#load("star_2.png")),
		k2.load_texture_from_bytes(#load("star_3.png")),
		k2.load_texture_from_bytes(#load("star_4.png")),
		k2.load_texture_from_bytes(#load("star_5.png")),
		k2.load_texture_from_bytes(#load("moon.png")),
	}

	fg_object_textures = {
		k2.load_texture_from_bytes(#load("grass.png")),
		k2.load_texture_from_bytes(#load("stone_1.png")),
		k2.load_texture_from_bytes(#load("stone_2.png")),
		k2.load_texture_from_bytes(#load("stone_3.png")),
		k2.load_texture_from_bytes(#load("ground_texture_1.png")),
		k2.load_texture_from_bytes(#load("ground_texture_2.png")),
		k2.load_texture_from_bytes(#load("ground_texture_3.png")),
	}

	plasma_ball_textures = {
		k2.load_texture_from_bytes(#load("plasma_1.png")),
		k2.load_texture_from_bytes(#load("plasma_2.png")),
		k2.load_texture_from_bytes(#load("plasma_3.png")),
	}
	
	interactable_type_texture = {
		.Enemy = k2.load_texture_from_bytes(#load("enemy.png")),
		.Key = k2.load_texture_from_bytes(#load("key.png")),
		.Wall = k2.load_texture_from_bytes(#load("wall.png")),
	}

	enemy_hidden_tex = k2.load_texture_from_bytes(#load("enemy_hidden.png"))

	ab_shoot = k2.load_audio_buffer_from_bytes(#load("laser_shoot.wav"))

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

	for bgo in bg_object_textures {
		k2.destroy_texture(bgo)	
	}

	for fgo in fg_object_textures {
		k2.destroy_texture(fgo)	
	}

	k2.destroy_texture(space_tileset)
	k2.destroy_texture(player.tex_east_west)
	k2.destroy_texture(player.tex_up)
	k2.destroy_texture(player.tex_down)
	delete(plasma_balls)
	
	k2.shutdown()
}

calc_player_collider :: proc(player_pos: Vec2) -> k2.Rect {
	return {
		player_pos.x - 5,
		player_pos.y - 6,
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

	dt := k2.get_frame_time()
	to_move := movement * dt * 50

	player.pos.x += to_move.x

	current_room := &world.rooms[current_room_idx]

	colliders := make([dynamic]k2.Rect, context.temp_allocator)

	for tile_type, tile_idx in current_room.tiles {
		if tile_walkable_lookup[tile_type] {
			continue
		}

		tile_pos := k2.Vec2 {
			f32(tile_idx % ROOM_TILE_WIDTH) * TILE_SIZE,
			f32(tile_idx / ROOM_TILE_WIDTH) * TILE_SIZE,
		}

		tile_rect := k2.rect_from_pos_size(tile_pos, {TILE_SIZE, TILE_SIZE})
		append(&colliders, tile_rect)
	}

	for &inter in current_room.interactables {
		inter.hurt_timer -= dt
		if inter.type == .Enemy && inter.hurt_timer <= 0 {
			r := k2.get_texture_rect(interactable_type_texture[inter.type])
			r.x = inter.pos.x - r.w/2
			r.y = inter.pos.y - r.h
			append(&colliders, r)
		}
	}

	for c in colliders {
		pc := calc_player_collider(player.pos)
		overlap, overlapping := k2.rect_overlap(pc, c)

		if overlapping && overlap.w != 0 {
			sign: f32 = pc.x + pc.w / 2 < (c.x + c.w / 2) ? -1 : 1
			fix := overlap.w * sign
			player.pos.x += fix
		}
	}

	player.pos.y += to_move.y

	for c in colliders {
		pc := calc_player_collider(player.pos)
		overlap, overlapping := k2.rect_overlap(pc, c)

		if overlapping && overlap.h != 0 {
			sign: f32 = pc.y + pc.h / 2 < (c.y + c.h / 2) ? -1 : 1
			fix := overlap.h * sign
			player.pos.y += fix
		}
	}

	if k2.key_went_down(.Space) {
		offset: Vec2

		#partial switch player.dir {
		case .East: offset = {6, -2}
		case .West: offset = {-6, -2}
		}

		append(&plasma_balls, Plasma_Ball {
			pos = player.pos + offset,
			dir = vec2_from_direction[player.dir],
		})

		shoot_snd := k2.create_sound_from_audio_buffer(ab_shoot)
		k2.set_sound_pitch(shoot_snd, rand.float32_range(0.8, 1.2))
		pan := math.remap_clamped(player.pos.x, 0, SCREEN_WIDTH, -0.5, 0.5)
		k2.set_sound_pan(shoot_snd, pan)
		k2.set_sound_volume(shoot_snd, rand.float32_range(0.7, 0.9))
		k2.play_sound(shoot_snd)
	}

	twinkle_timer -= dt

	if twinkle_timer <= 0 {
		twinkle_timer = rand.float32_range(0.05, 0.1)
		to_twinkle_idx := rand.int_max(len(current_room.background_objects))
		to_twinkle := &current_room.background_objects[to_twinkle_idx]

		// Don't twinkle moon
		if to_twinkle.texture_index != 5 {
			to_twinkle.dim_timer = rand.float32_range(0.2, 0.3)
		}
	}

	for &bgo in current_room.background_objects {
		bgo.dim_timer -= dt
	}

	world_rect := k2.rect_from_pos_size(
		{0, -STATUS_BAR_HEIGHT},
		k2.get_screen_size()/game_camera.zoom,
	)

	for pidx := 0; pidx < len(plasma_balls); pidx += 1 {
		p := &plasma_balls[pidx]
		p.pos += p.dir * dt * 120
		p.age += dt

		if !k2.point_in_rect(p.pos, k2.rect_expand(world_rect, 20, 20)) {
			unordered_remove(&plasma_balls, pidx)
			pidx -= 1
		}
	}

	for inter_idx := 0; inter_idx < len(current_room.interactables); inter_idx += 1 {
		inter := &current_room.interactables[inter_idx]
		r := k2.get_texture_rect(interactable_type_texture[inter.type])
		r.x = inter.pos.x - r.w/2
		r.y = inter.pos.y - r.h

		switch inter.type {
		case .Enemy:
			for pidx := 0; pidx < len(plasma_balls); pidx += 1 {
				p := &plasma_balls[pidx]
				if k2.point_in_rect(p.pos, r) {
					inter.hurt_timer = 5
					unordered_remove(&plasma_balls, pidx)
					pidx -= 1
				}
			}
		case .Key:
			if k2.rect_overlapping(calc_player_collider(player.pos), r) {
				unordered_remove(&current_room.interactables, inter_idx)
				inter_idx -= 1
			}
		case .Wall:
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
			clear(&plasma_balls)
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

		if tex_idx < 0 || tex_idx >= len(bg_object_textures) {
			continue
		}

		tint := k2.WHITE

		if bgo.dim_timer > 0 {
			tint = {
				210,
				210,
				255,
				230,
			}
		}

		tex := bg_object_textures[tex_idx]
		k2.draw_texture(tex, bgo.pos, origin = k2.rect_middle(k2.get_texture_rect(tex)), tint = tint)
	}

	for x in 0..<(ROOM_TILE_WIDTH+1) {
		for y in 0..<(ROOM_TILE_HEIGHT+1) {
			dual_grid_draw(x, y)
		}
	}

	Sorted_Draw :: struct {
		tex: k2.Texture,
		pos: Vec2,
		origin: Vec2,
		flip_x: bool,
	}

	sorted_draws := make([dynamic]Sorted_Draw, context.temp_allocator)

	for fgo in world.rooms[current_room_idx].foreground_objects {
		tex_idx := fgo.texture_index

		if tex_idx < 0 || tex_idx >= len(fg_object_textures) {
			continue
		}

		tex := fg_object_textures[tex_idx]
		always_behind := tex_idx == 4 || tex_idx == 5 || tex_idx == 6

		if always_behind {
			k2.draw_texture(
				tex,
				fgo.pos,
				origin = k2.rect_bottom_middle(k2.get_texture_rect(tex)),
			)

			continue
		}

		append(&sorted_draws, Sorted_Draw {
			tex = tex,
			pos = fgo.pos,
			origin = k2.rect_bottom_middle(k2.get_texture_rect(tex)),
		})
	}

	for inter in world.rooms[current_room_idx].interactables {
		if inter.hurt_timer > 0 {
			if inter.type == .Enemy {
				tex := enemy_hidden_tex

				k2.draw_texture(
					tex,
					inter.pos,
					origin = k2.rect_bottom_middle(k2.get_texture_rect(tex)),
				)
			}

			continue
		}

		tex := interactable_type_texture[inter.type]

		append(&sorted_draws, Sorted_Draw {
			tex = tex,
			pos = inter.pos,
			origin = k2.rect_bottom_middle(k2.get_texture_rect(tex)),
		})
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

	append(&sorted_draws, Sorted_Draw {
		tex = player_tex,
		pos = player.pos,
		origin = {f32(player_tex.width/2), f32(player_tex.height)},
		flip_x = flip_x,
	})

	slice.sort_by(sorted_draws[:], proc(i, j: Sorted_Draw) -> bool {
		return i.pos.y < j.pos.y
	})

	for s in sorted_draws {
		r := k2.get_texture_rect(s.tex)

		if s.flip_x {
			r.w *= -1
		}

		k2.draw_texture_section(
			s.tex,
			r,
			s.pos,
			origin = s.origin,
		)
	}

	for &p in plasma_balls {
		tex_idx := 2

		if p.age < 0.3 {
			tex_idx = 1
		}

		if p.age < 0.2 {
			tex_idx = 0
		}

		tex := plasma_ball_textures[tex_idx]
		k2.draw_texture(tex, p.pos, origin = k2.rect_middle(k2.get_texture_rect(tex)))
	}

	k2.draw_rect(calc_player_collider(player.pos), k2.color_alpha(k2.RED, 128))

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