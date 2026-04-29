// This is a small example video game where you can shoot, pick up a key, open a door and get to the end.
// 
// Controls:
// - Move player: Arrows
// - Shoot: Space
// - F2: Level editor
// 
// Art by Gerry Mander: https://bsky.app/profile/mandelbaumski.bsky.social
// Code by Karl Zylinski: https://zylinski.se
//
// There is also a level editor, accessible using the F2 key.
//
// This file implements most of the game, while the editor is implemented in the `editor.odin` file.

package space_cat

import k2 "../.."
import "core:math/linalg"
import "core:encoding/json"
import "core:time"
import "core:math/rand"
import "core:math"
import "core:slice"
import "core:fmt"
import "core:mem"

_ :: fmt

CLEAR_COLOR :: k2.Color{6, 6, 8, 255}
SPACE_COLOR :: k2.Color{28, 38, 56, 255}
GROUND_COLOR :: k2.Color{35, 73, 93, 255}
HIGHLIGHT_COLOR :: k2.Color{149, 224, 204, 255}

// We zoom the game up to fit this size
SCREEN_WIDTH :: 240
SCREEN_HEIGHT :: 180
STATUS_BAR_HEIGHT :: 20

Vec2 :: k2.Vec2

Player :: struct {
	pos: Vec2,

	// Textures for walking in different directions
	tex_east_west: k2.Texture,
	tex_up: k2.Texture,
	tex_down: k2.Texture,

	dir: Direction,
}

// The things the player shoots
Plasma_Ball :: struct {
	pos: Vec2,
	dir: Vec2,
	age: f32,
}

// Counted in number of tiles
ROOM_TILE_WIDTH :: 15
ROOM_TILE_HEIGHT :: 10

// Pixel size of a tile
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

// How long until a star should twinkle
twinkle_timer: f32

player: Player
has_key: bool
plasma_balls: [dynamic]Plasma_Ball
current_room_idx: int
editing: bool
game_camera: k2.Camera
ui_camera: k2.Camera

// Dual-grid tileset
space_tileset: k2.Texture
space_tileset_version: time.Time

// The textures used by different kinds of objects in the level, filled in `init`
bg_object_textures: [6]k2.Texture
fg_object_textures: [7]k2.Texture
plasma_ball_textures: [3]k2.Texture

// We use audio buffers from which we create sounds when needed. This way multiple sounds can be
// played at once.
ab_shoot: k2.Audio_Buffer
ab_pickup: k2.Audio_Buffer
ab_hit: k2.Audio_Buffer

// For making a texture appear on the screen for a short period.
flash_texture: k2.Texture
flash_texture_pos: Vec2
flash_texture_timer: f32

game_finished: bool
show_controls: bool

WORLD_FILE_NAME :: "world.json"

// Conted in "number of rooms"
WORLD_WIDTH :: 2
WORLD_HEIGHT :: 3

World :: struct {
	rooms: [WORLD_WIDTH*WORLD_HEIGHT]Room,
}

Background_Object :: struct {
	texture_index: int,
	pos: Vec2,

	// We use the same structures for the serialized data and the in-game data. We don't want this
	// run-time value to get written into the JSON. Therefore we use the `json:"-"` tag.
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
	Wall_Down,
	The_Object,
}

Interactable :: struct {
	type: Interactable_Type,
	pos: Vec2,
	hurt_timer: f32 `json:"-"`,
}

interactable_type_texture: [Interactable_Type]k2.Texture
enemy_hidden_tex: k2.Texture

// There is an `editor_world` in `editor.odin` we keep the private and separate to avoid accidents.
// It's important that the editor has its own copy of the data. If runnin game and editor share the
// data, then you could pick up an object in the game, enter the editor and the object is gone in
// the editor. Not good!
@(private="file")
world: World

// Use by desktop builds. Web builds call `init` and `step` directly.
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

init :: proc() {
	k2.init(SCREEN_WIDTH*4, SCREEN_HEIGHT*4, "SPACE CAT", options = {window_mode = .Windowed_Resizable})
	show_controls = true
	current_room_idx = 4

	// ----
	// Here you'll see lots of `load_texture_from_bytes(#load(blabla))`. Using #load bakes the
	// resources into the executable at compile-time. The result of it is a slice of bytes `[]u8`.
	//
	// We do this because web builds can't load files from disk (there is no "OS"). In the future
	// Karl2D may get some kind of async file loading for web, or similar... For now, you can do
	// stuff like this. You can also generate an `assets.odin` file and `#load` files in there based
	// on what existed on disk when the file was generated.
	//

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
		.Wall_Down = k2.load_texture_from_bytes(#load("wall_down.png")),
		.The_Object = k2.load_texture_from_bytes(#load("the_object.png")),
	}

	enemy_hidden_tex = k2.load_texture_from_bytes(#load("enemy_hidden.png"))

	ab_shoot = k2.load_audio_buffer_from_bytes(#load("laser_shoot.wav"))
	ab_hit = k2.load_audio_buffer_from_bytes(#load("hit_hurt.wav"))
	ab_pickup = k2.load_audio_buffer_from_bytes(#load("power_up.wav"))

	space_tileset_version = file_version("space_tileset.png")

	world_json_data, world_json_data_ok := get_file_contents(WORLD_FILE_NAME)

	if world_json_data_ok {
		json.unmarshal(world_json_data, &world)
	}

	editor_init(world_json_data)

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

	when ODIN_OS != .JS && ODIN_DEBUG {
		// Hot reload of the tileset. This makes it possible to edit the tileset and see changes to
		// it live as you re-save the file.
		space_tileset_new_version := file_version("space_tileset.png")

		if space_tileset_version != space_tileset_new_version {
			k2.destroy_texture(space_tileset)
			space_tileset = k2.load_texture_from_file("space_tileset.png")
		}
	}

	if k2.key_went_down(.F2) {
		if editing {
			editor_save()
			destroy_world(world)

			world_json_data, world_json_data_ok := get_file_contents(WORLD_FILE_NAME)

			if world_json_data_ok {
				json.unmarshal(world_json_data, &world)
			}
		}

		editing = !editing
	}

	// These cameras zoom everything so the height of the screen fits SCREEN_HEIGHT number of world-
	// space pixels.
	game_camera = {
		zoom = f32(k2.get_screen_height())/SCREEN_HEIGHT,
		target = {0, -STATUS_BAR_HEIGHT},
	}

	ui_camera = {
		zoom = f32(k2.get_screen_height())/SCREEN_HEIGHT,
	}

	k2.set_scissor_rect(k2.Rect{
		0, 0,
		SCREEN_WIDTH*game_camera.zoom,
		SCREEN_HEIGHT*game_camera.zoom,
	})

	if editing {
		editor_update()
	} else {
		update()
		draw()
	}

	return true
}

shutdown :: proc() {
	destroy_world(world)
	editor_shutdown()

	for bgo in bg_object_textures {
		k2.destroy_texture(bgo)	
	}

	for fgo in fg_object_textures {
		k2.destroy_texture(fgo)	
	}

	for t, _ in interactable_type_texture {
		k2.destroy_texture(t)	
	}

	for t in plasma_ball_textures {
		k2.destroy_texture(t)	
	}

	k2.destroy_audio_buffer(ab_hit)
	k2.destroy_audio_buffer(ab_pickup)
	k2.destroy_audio_buffer(ab_shoot)
	k2.destroy_texture(space_tileset)
	k2.destroy_texture(player.tex_east_west)
	k2.destroy_texture(player.tex_up)
	k2.destroy_texture(player.tex_down)
	k2.destroy_texture(enemy_hidden_tex)
	delete(plasma_balls)
	
	k2.shutdown()
}

destroy_world :: proc(w: World) {
	for r in w.rooms {
		delete(r.background_objects)
		delete(r.foreground_objects)
		delete(r.interactables)
	}
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
	if game_finished {
		return
	}

	if show_controls {
		if k2.key_went_down(.Space) {
			show_controls = false
		}

		return
	}

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

	current_room := &world.rooms[current_room_idx]

	// Generate a temporary list of colliders in the room. This is fine for a game with so few
	// colliders per room.
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
		if inter.hurt_timer > 0 {
			inter.hurt_timer -= dt
		}

		// Only some interactables have "blocks colliders"

		// hurt_timer > 0 means that this enemy has recently been hit and therefore hidden in the
		// ground.
		if inter.type == .Enemy && inter.hurt_timer <= 0 {
			r := k2.get_texture_rect(interactable_type_texture[inter.type])
			r.x = inter.pos.x - r.w/2
			r.y = inter.pos.y - r.h
			append(&colliders, r)
		}

		if inter.type == .Wall {
			r := k2.get_texture_rect(interactable_type_texture[inter.type])
			r.x = inter.pos.x - r.w/2
			r.y = inter.pos.y - r.h
			append(&colliders, r)
		}
	}

	// --
	// We do the collision between player and colliders first in X and then in Y. This makes the
	// collision handling stable. It's perhaps not very efficient in a game where lots of things
	// collide with lots of other things. In that case you may need some kind "broadphase".

	player.pos.x += to_move.x

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

	// Shoot
	if k2.key_went_down(.Space) {
		offset: Vec2

		#partial switch player.dir {
		case .East: offset = {6, -4}
		case .West: offset = {-6, -4}
		}

		append(&plasma_balls, Plasma_Ball {
			pos = player.pos + offset,
			dir = vec2_from_direction[player.dir],
		})

		// The shoot sound has pitch randomization and spatial panning.
		shoot_snd := k2.create_sound_from_audio_buffer(ab_shoot)
		k2.set_sound_pitch(shoot_snd, rand.float32_range(0.8, 1.2))
		pan := math.remap_clamped(player.pos.x, 0, SCREEN_WIDTH, -0.5, 0.5)
		k2.set_sound_pan(shoot_snd, pan)
		k2.set_sound_volume(shoot_snd, rand.float32_range(0.7, 0.9))
		k2.play_sound(shoot_snd)
	}

	// Make stars twinkle. It's just a timer that makes a single star, picked at random, twinkle.
	twinkle_timer -= dt

	if twinkle_timer <= 0 {
		twinkle_timer = rand.float32_range(0.05, 0.1)
		to_twinkle_idx := rand.int_max(len(current_room.background_objects))
		to_twinkle := &current_room.background_objects[to_twinkle_idx]

		// Don't twinkle moon. I know, using an index here feels hacky. We could use an enumerated
		// array or have a "type" enum on each background object.
		if to_twinkle.texture_index != 5 {
			to_twinkle.dim_timer = rand.float32_range(0.2, 0.3)
		}
	}

	for &bgo in current_room.background_objects {
		if bgo.dim_timer > 0 {
			bgo.dim_timer -= dt
		}
	}

	world_rect := k2.rect_from_pos_size(
		{0, 0},
		k2.get_screen_size()/game_camera.zoom,
	)

	// Despawn plasma balls that have left screen.
	for pidx := 0; pidx < len(plasma_balls); pidx += 1 {
		p := &plasma_balls[pidx]
		p.pos += p.dir * dt * 120
		p.age += dt

		if !k2.point_in_rect(p.pos, k2.rect_expand(world_rect, 20, 20)) {
			unordered_remove(&plasma_balls, pidx)
			pidx -= 1
		}
	}

	// -------------
	// Interactables are stuff like enemies, keys and walls. In this loop we'll see lots of overlap
	// checks between the player/plasma_balls and the interactables, which results in the 
	// interactivity of the game.

	for inter_idx := 0; inter_idx < len(current_room.interactables); inter_idx += 1 {
		inter := &current_room.interactables[inter_idx]
		r := k2.get_texture_rect(interactable_type_texture[inter.type])
		r.x = inter.pos.x - r.w/2
		r.y = inter.pos.y - r.h

		switch inter.type {
		case .Enemy:
			for pidx := 0; pidx < len(plasma_balls); pidx += 1 {
				p := &plasma_balls[pidx]

				plasma_ball_rect := k2.Rect {
					p.pos.x - 3,
					p.pos.y - 3,
					6, 6,
				}

				if inter.hurt_timer <= 0 && k2.rect_overlapping(plasma_ball_rect, r) {
					inter.hurt_timer = 5
					unordered_remove(&plasma_balls, pidx)
					flash_texture = plasma_ball_textures[2]
					flash_texture_timer = 0.2
					flash_texture_pos = p.pos
					pidx -= 1
					k2.play_sound(k2.create_sound_from_audio_buffer(ab_hit))
				}
			}

		case .Key:
			if k2.rect_overlapping(calc_player_collider(player.pos), r) {
				unordered_remove(&current_room.interactables, inter_idx)
				inter_idx -= 1
				has_key = true
				k2.play_sound(k2.create_sound_from_audio_buffer(ab_pickup))
			}

		case .Wall:
			for pidx := 0; pidx < len(plasma_balls); pidx += 1 {
				p := &plasma_balls[pidx]
				if k2.point_in_rect(p.pos, r) {
					unordered_remove(&plasma_balls, pidx)
					pidx -= 1
				}
			}

			// expand to be sure player can hit
			expanded_wall_collider := k2.rect_expand(r, 4, 4)

			if has_key && k2.rect_overlapping(calc_player_collider(player.pos), expanded_wall_collider) {
				inter.type = .Wall_Down
				flash_texture = interactable_type_texture[.Key]
				flash_texture_pos = inter.pos
				flash_texture_timer = 0.5
			}

		case .Wall_Down:

		case .The_Object:
			rr := r
			rr.h -= 3
			if k2.rect_overlapping(calc_player_collider(player.pos), rr) {
				game_finished = true
			}
		}
	}

	if flash_texture_timer > 0 {
		flash_texture_timer -= dt
	}

	// ----
	// Move between rooms
	//

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
	if game_finished {
		k2.clear(SPACE_COLOR)
		k2.set_camera(game_camera)
		tex := interactable_type_texture[.The_Object]
		src := k2.get_texture_rect(tex)
		dst := k2.Rect {
			x = SCREEN_WIDTH/2 - (src.w*5)/2,
			y = 20,
			w = src.w*5,
			h = src.h*5,
		}
		k2.draw_texture_fit(tex, src, dst)
		END_TEXT :: "Thank you - This is the end"
		thanks_size := k2.measure_text(END_TEXT, 10)
		k2.draw_text(END_TEXT, {SCREEN_WIDTH/2-thanks_size.x/2, dst.y + dst.h + 3}, 10, k2.WHITE)


		button_width := k2.measure_text("Source code", 10).x

		if ui_button({SCREEN_WIDTH/2-button_width/2, dst.y + dst.h + 20, 50, 10}, "Source code", game_camera) {
			k2.open_url("https://github.com/karl-zylinski/karl2d/blob/master/examples/space_cat/space_cat.odin")
		}

		k2.present()
		return
	}

	k2.clear(CLEAR_COLOR)
	k2.set_camera(game_camera)
	k2.draw_rect({0, 0, SCREEN_WIDTH, SCREEN_HEIGHT}, SPACE_COLOR)
	
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
			dual_grid_draw(world, x, y)
		}
	}

	// ----
	// Some things should be drawn behind player when player is below them on screen, and vice versa
	// However, some things, such as dirt on the ground, should always be under the player. This
	// code implements both.
	//

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

		if inter.type == .Wall_Down {
			tex := interactable_type_texture[.Wall_Down]
			k2.draw_texture(
				tex,
				inter.pos,
				origin = k2.rect_bottom_middle(k2.get_texture_rect(tex)),
			)

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

		k2.draw_texture_rect(
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

	if flash_texture_timer > 0 {
		k2.draw_texture(flash_texture, flash_texture_pos, origin = k2.rect_middle(k2.get_texture_rect(flash_texture)))
	}

	k2.set_camera(ui_camera)
	k2.draw_rect({0, 0, SCREEN_WIDTH, STATUS_BAR_HEIGHT}, CLEAR_COLOR)

	if has_key {
		k2.draw_texture(interactable_type_texture[.Key], {5, 5})
	}

	// -------
	// Minimap

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

	if show_controls {
		k2.draw_rect({50, 50, SCREEN_WIDTH-120, SCREEN_HEIGHT-110}, CLEAR_COLOR)
		k2.draw_text("Move: Arrows", { 60, 60}, 10, k2.WHITE)
		k2.draw_text("Shoot: Space", { 60, 80}, 10, k2.WHITE)
		k2.draw_text("Shoot to start!", { 60, 100}, 10, k2.WHITE)
	}

	if ui_button({100, 3, 60, (STATUS_BAR_HEIGHT)/2}, "Source code", ui_camera) {
		k2.open_url("https://github.com/karl-zylinski/karl2d/blob/master/examples/space_cat/space_cat.odin")
	}

	k2.present()
}

// There is a separate example called dual_grid_tilemap that explains this technique in more detail.
dual_grid_draw :: proc(world: World, x, y: int) {
	tile_type :: proc(world: World, x, y: int) -> Tile_Type {
		if x < 0 {
			return tile_type(world, x + 1, y)
		}

		if x >= ROOM_TILE_WIDTH {
			return tile_type(world, x - 1, y)
		}

		if y < 0 {
			return tile_type(world, x, y + 1)
		}

		if y >= ROOM_TILE_HEIGHT {
			return tile_type(world, x, y - 1)
		}

		return world.rooms[current_room_idx].tiles[y*ROOM_TILE_WIDTH+x]
	}

	mask := 0

	if tile_type(world, x-1, y-1) == .Space {
		mask |= 1 // TL
	}
	if tile_type(world, x, y-1) == .Space {
		mask |= 2 // TR
	}
	if tile_type(world, x, y) == .Space {
		mask |= 4 // BR
	}
	if tile_type(world, x-1, y) == .Space {
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

	k2.draw_texture_rect(space_tileset, tile_rect, pos)
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

ui_button :: proc(r: k2.Rect, text: string, camera: k2.Camera) -> bool {
	in_rect := k2.point_in_rect(k2.screen_to_world(k2.get_mouse_position(), camera), r)
	bg_color := k2.DARK_GRAY
	border_color := k2.WHITE
	text_color := k2.WHITE
	res := false

	if in_rect {
		bg_color = k2.GRAY
		text_color = k2.WHITE

		if k2.mouse_button_went_down(.Left) {
			res = true
			bg_color = k2.BLACK
		}
	}
	
	k2.draw_rect(r, bg_color)
	k2.draw_rect_outline(r, 1/camera.zoom, border_color)

	text_width := k2.measure_text(text, r.h).x
	k2.draw_text(text, {r.x + r.w/2 - text_width/2, r.y}, r.h, k2.WHITE)
	return res
}