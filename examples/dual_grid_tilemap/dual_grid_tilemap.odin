package karl2d_example_dual_grid_tilemap

import k2 "../.."
import "core:math"

// 16x16 pixel tiles
TILE_SIZE :: 16

// World is 20x20 tiles (or 16*20x16*20 pixels large)
WORLD_WIDTH :: 20

// The height of the toolbar at the bottom
UI_HEIGHT :: 16

// By default, everything is of .Grass type. We just store what kind of ground each tile has, the
// actual selection of tile is done at runtime based on the values of the neighboring tiles.
tiles: [WORLD_WIDTH*WORLD_WIDTH]Tile_Type

// This texture contains the pieces that look like a "road" or "path"
tileset_path_texture: k2.Texture

// Maps a bitmask to a coordinate within the tileset. The bits mean:
// Bit 4: Top-left neighbor exists
// Bit 3: Top-right neighbor exists
// Bit 2: Bottom-right neighbor exists
// Bit 1: Bottom-left neighbor exists
//
// Look at how the `tileset_path.png` looks in order to better understand why we map to these
// specific coordinates.
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

Tile_Type :: enum {
	Grass,
	Path,
}

init :: proc() {
	k2.init(800, 640, "Karl2D: Dual Grid Tilemap", options = { window_mode = .Windowed_Resizable })
	tileset_path_texture = k2.load_texture_from_bytes(#load("tileset_path.png"))
}

step :: proc() -> bool {
	if !k2.update() {
		return false
	}

	camera := k2.Camera {
		// Fit the whole world, but also zoom out a little so the UI fits
		zoom = f32(k2.get_screen_height())/(WORLD_WIDTH*TILE_SIZE+UI_HEIGHT),
		// Make the game look in the middle of the world (middle of the tiles). The half tile offset
		// is here because the dual-grid tiles are offset by half a tile.
		target = k2.Vec2{
			TILE_SIZE * WORLD_WIDTH,
			TILE_SIZE * WORLD_WIDTH + UI_HEIGHT,
		} * 0.5 - {TILE_SIZE, TILE_SIZE} * 0.5,
		offset = k2.Vec2{f32(k2.get_screen_width()), f32(k2.get_screen_height())} * 0.5,
	}

	mouse_pos_world := k2.screen_to_world(k2.get_mouse_position(), camera)
	grid_x := int(math.floor(mouse_pos_world.x / TILE_SIZE))
	grid_y := int(math.floor(mouse_pos_world.y / TILE_SIZE))
	hovered_grid_rect: k2.Rect

	// This does the editing of the tiles, given that we are hovering within the area of the tiles.
	if grid_x >= 0 && grid_x < WORLD_WIDTH - 1 && grid_y >= 0 && grid_y < WORLD_WIDTH - 1 {
		hovered_grid_idx := grid_y*WORLD_WIDTH+grid_x
		grid_pos := k2.Vec2 { f32(grid_x) * TILE_SIZE, f32(grid_y) *TILE_SIZE }
		hovered_grid_rect = k2.rect_from_pos_size(grid_pos, {TILE_SIZE, TILE_SIZE})

		modifiers := k2.get_held_modifiers()

		if modifiers == k2.MODIFIERS_NONE && k2.mouse_button_is_held(.Left) {
			tiles[hovered_grid_idx] = .Path
		}

		if (
			(modifiers == { .Control } && k2.mouse_button_is_held(.Left)) ||
			k2.mouse_button_is_held(.Right)
		) {
			tiles[hovered_grid_idx] = .Grass
		}
	}

	k2.clear(k2.BLUE)
	k2.set_camera(camera)

	for tile_idx in 0..<len(tiles) {
		x := tile_idx % WORLD_WIDTH
		y := tile_idx / WORLD_WIDTH

		tile_type :: proc(x, y: int) -> Tile_Type {
			if x < 0 || y < 0 || x >= WORLD_WIDTH - 1 || y >= WORLD_WIDTH - 1 {
				return .Grass
			}

			return tiles[y*WORLD_WIDTH+x]
		}

		mask := 0

		if tile_type(x-1, y-1) == .Path {
			mask |= 1 // TL
		}
		if tile_type(x, y-1) == .Path {
			mask |= 2 // TR
		}
		if tile_type(x, y) == .Path {
			mask |= 4 // BR
		}
		if tile_type(x-1, y) == .Path {
			mask |= 8 // BL
		}

		txty := DUAL_GRID_MASK_TO_TXTY[mask]
		tx := txty.x
		ty := txty.y

		crop := k2.Rect {
			x = f32(tx) * TILE_SIZE,
			y = f32(ty) * TILE_SIZE,
			w = TILE_SIZE,
			h = TILE_SIZE,
		}

		// Note the half-tile offset here: This is what "undoes" the half-tile offset that dual
		// tile grids need.
		pos := k2.Vec2 {
			f32(x) * TILE_SIZE - TILE_SIZE/2,
			f32(y) * TILE_SIZE - TILE_SIZE/2,
		}

		// Always draw "grass" below the tile, as they have transparent pixels.
		k2.draw_rect(k2.rect_from_pos_size(pos, {TILE_SIZE, TILE_SIZE}), k2.LIGHT_GREEN)

		k2.draw_texture(
			tileset_path_texture,
			pos,
			crop,
		)
	}

	k2.draw_rect(hovered_grid_rect, {255, 255, 255, 128})

	k2.set_camera(nil)
	fullscreen_rect := k2.get_fullscreen_rect()
	ui_bg := k2.rect_cut_bottom(&fullscreen_rect, UI_HEIGHT * camera.zoom, 0)
	k2.draw_rect(ui_bg, k2.DARK_GRAY)
	ui_text_area := k2.rect_shrink(ui_bg, 2*camera.zoom, 2*camera.zoom)

	if ui_button(k2.rect_cut_right(&ui_text_area, ui_button_width("Source Code", ui_text_area.h) + 50, 0), "Source Code") {
		k2.open_url("https://github.com/karl-zylinski/karl2d/blob/master/examples/dual_grid_tilemap/dual_grid_tilemap.odin")
	}

	k2.draw_text("Paint path: LMB | Erase path: RMB or Ctrl + LMB", k2.rect_top_left(ui_text_area), ui_text_area.h, k2.WHITE)
	k2.present()
	free_all(context.temp_allocator)

	return true
}

shutdown :: proc() {
	k2.destroy_texture(tileset_path_texture)
	k2.shutdown()
}

// This is not run by the web version, but it makes this program also work on non-web!
main :: proc() {
	init()
	for step() {}
	shutdown()
}

// --------------------------
// These UI things are experiments that may get moved to some official KarlUI package
//

ui_button_width :: proc(text: string, button_height: f32) -> f32 {
	return k2.measure_text(text, button_height).x
}

ui_button :: proc(r: k2.Rect, text: string) -> bool {
	in_rect := k2.point_in_rect(k2.get_mouse_position(), r)
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
	k2.draw_rect_outline(r, 1, border_color)

	text_width := k2.measure_text(text, r.h).x
	k2.draw_text(text, {r.x + r.w/2 - text_width/2, r.y}, r.h, k2.WHITE)
	return res
}
