package karl2d_example_dual_grid_tilemap

import k2 "../.."
import "core:math"

TILE_SIZE :: 16
WORLD_WIDTH :: 20
UI_HEIGHT :: 16
tiles: [WORLD_WIDTH*WORLD_WIDTH]Tile_Type
tileset_path: k2.Texture
Vec2i :: [2]int

DUAL_GRID_MASK_TO_TXTY := [16]Vec2i {
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

main :: proc() {
	k2.init(1280, 1024, "Karl2D: Dual Grid Tilemap", options = { window_mode = .Windowed_Resizable })
	tileset_path = k2.load_texture_from_bytes(#load("tileset_path.png"))

	for k2.update() {
		k2.clear(k2.BLUE)

		camera := k2.Camera {
			zoom = f32(k2.get_screen_height())/(WORLD_WIDTH*TILE_SIZE+UI_HEIGHT),
			target = k2.Vec2{TILE_SIZE * WORLD_WIDTH, TILE_SIZE * WORLD_WIDTH + UI_HEIGHT} * 0.5 - {TILE_SIZE, TILE_SIZE} * 0.5,
			offset = k2.Vec2{f32(k2.get_screen_width()), f32(k2.get_screen_height())} * 0.5,
		}

		k2.set_camera(camera)
		mp := k2.get_mouse_position()
		mp_world := k2.screen_to_world(mp, camera)

		hovered_grid_idx := -1
		hovered_grid_rect: k2.Rect

		grid_x := int(math.floor(mp_world.x / TILE_SIZE))
		grid_y := int(math.floor(mp_world.y / TILE_SIZE))

		if grid_x >= 0 && grid_x < WORLD_WIDTH - 1 && grid_y >= 0 && grid_y < WORLD_WIDTH - 1{
			hovered_grid_idx = grid_y*WORLD_WIDTH+grid_x
			grid_pos := k2.Vec2 { f32(grid_x) * TILE_SIZE, f32(grid_y) *TILE_SIZE }
			hovered_grid_rect = k2.rect_from_pos_size(grid_pos, {TILE_SIZE, TILE_SIZE})

			if k2.mouse_button_is_held(.Left) {
				tiles[hovered_grid_idx] = .Path
			}

			if k2.mouse_button_is_held(.Right) {
				tiles[hovered_grid_idx] = .Grass
			}
		}

		for _, i in tiles {
			x := i % WORLD_WIDTH
			y := i / WORLD_WIDTH

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

			src := k2.Rect {
				x = f32(tx) * TILE_SIZE,
				y = f32(ty) * TILE_SIZE,
				w = TILE_SIZE,
				h = TILE_SIZE,
			}

			dst := k2.Rect {
				x = f32(x) * TILE_SIZE - TILE_SIZE/2,
				y = f32(y) * TILE_SIZE - TILE_SIZE/2,
				w = TILE_SIZE,
				h = TILE_SIZE,
			}

			k2.draw_rect(dst, k2.LIGHT_GREEN)

			k2.draw_texture_ex(
				tileset_path,
				src,
				dst,
				{},
				0,
			)
		}

		if hovered_grid_idx != -1 {
			k2.draw_rect(hovered_grid_rect, {255, 255, 255, 128})
		}

		// Camera with same zoom as game but without translation: Used for UI.
		ui_camera := k2.Camera {
			zoom = f32(k2.get_screen_height())/(WORLD_WIDTH*TILE_SIZE+UI_HEIGHT),
		}

		k2.set_camera(ui_camera)
		fullscreen_rect := k2.get_fullscreen_camera_rect(ui_camera)
		ui_bg := k2.rect_cut_bottom(&fullscreen_rect, UI_HEIGHT, 0)
		k2.draw_rect(ui_bg, k2.DARK_GRAY)
		ui_text_area := k2.rect_shrink(ui_bg, 2, 2)
		k2.draw_text("LMB: Paint path. RMB: Erase path.", k2.rect_top_left(ui_text_area), ui_text_area.h, k2.WHITE)
		k2.present()
	}

	k2.shutdown()
}