package dual_grid_tilemap_example

import k2 "../.."
import "core:fmt"
import "core:math/linalg"

Vec2 :: k2.Vec2
Vec3 :: k2.Vec3
Vec4 :: k2.Vec4

Rect :: k2.Rect

Camera :: k2.Camera
CameraBounds :: struct {
	min_x:  f32,
	min_y:  f32,
	max_x:  f32,
	max_y:  f32,
	width:  f32,
	height: f32,
}

TilemapGrid :: struct {
	width:    int,
	height:   int,
	position: Vec2,
	cell_size: Vec2,
	data:     []u8,
}

camera: k2.Camera
tilemap_grid: TilemapGrid
tilemap_texture: k2.Texture

init :: proc() {
	k2.init(1200, 900, "Karl2D Dual Grid Tilemap Demo", {window_mode = .Windowed_Resizable})

	tilemap_texture = k2.load_texture_from_file("./tilemap.png")

	grid_size := 16
	cell_size := Vec2{16, 16}
	tilemap_grid = {grid_size, grid_size, cell_size * 2, cell_size, make([]u8, grid_size * grid_size)}

	reset_camera()
}

step :: proc() -> bool {
	if !k2.update() {
		return false
	}

	screen_size := Vec2{f32(k2.get_screen_width()), f32(k2.get_screen_height())}
	mouse_screen_pos := k2.get_mouse_position()
	mouse_world_pos := k2.screen_to_world(k2.get_mouse_position(), camera)
	frame_time := k2.get_frame_time()

	update_camera(&camera, screen_size)
	update_tilemap_grid(&tilemap_grid, mouse_world_pos)

	if k2.key_went_down(.T) do increment_texture_option()

	// DRAW WORLD
	k2.set_camera(camera)
	k2.clear(k2.DARK_GRAY)

	// DRAW GRID LINES
	draw_grid_lines_inside_camera_bounds(&camera, screen_size)


	// DRAW TILEMAP GRID
	render_grid(&tilemap_grid)
	
	render_dual_grid(&tilemap_grid, tilemap_texture, texture_options[texture_option_index].index)

	render_grid_selection(&tilemap_grid, mouse_world_pos)

	k2.set_camera(nil)

	
	// GUI
	text := fmt.tprint("-[LFM] Add   -[RMB] Remove   -[MMB] Pan   -[Z/X] Rotate   -[R] Reset   -[T] Texture: ", texture_options[texture_option_index].text)
	
	text_padding := f32(4)
	text_size := k2.measure_text(text, 22) + {text_padding, text_padding} * 2
	k2.draw_rect({0, 0, text_size.x, text_size.y}, k2.Color{0, 0, 0, 128})
	k2.draw_text(text, {text_padding, text_padding}, 22, k2.WHITE)

	k2.present()
	free_all(context.temp_allocator)
	return true
}

shutdown :: proc() {
	k2.shutdown()
}

main :: proc() {
	init()
	for step() {}
	shutdown()
}

update_camera :: proc(camera: ^k2.Camera, screen_size: Vec2) {
	frame_time := k2.get_frame_time()

	// CAMERA PANNING

	camera_target_movement: Vec2
	if k2.mouse_button_is_held(.Middle) || (k2.mouse_button_is_held(.Left) && k2.key_is_held(.Left_Control)) {
		camera_target_movement -= k2.get_mouse_delta() / camera.zoom
	}

	CAMERA_KEY_MOVE_SPEED :: 300 // in screen pixels/sec
	camera_key_move_delta := CAMERA_KEY_MOVE_SPEED * frame_time / camera.zoom
	if k2.key_is_held(.Right) {camera_target_movement.x += camera_key_move_delta}
	if k2.key_is_held(.Left) {camera_target_movement.x -= camera_key_move_delta}
	if k2.key_is_held(.Down) {camera_target_movement.y += camera_key_move_delta}
	if k2.key_is_held(.Up) {camera_target_movement.y -= camera_key_move_delta}

	// Multiplying camera movement with rotation matrix makes it move like the player expects,
	// relative to the axes of the window, not the axes of the camera.
	rotation_matrix := linalg.matrix2_rotate(-camera.rotation)
	camera.target += rotation_matrix * camera_target_movement

	camera.target = {clamp(camera.target.x, -1000, 1000), clamp(camera.target.y, -1000, 1000)}


	// CAMERA ZOOM

	mouse_wheel_delta := k2.get_mouse_wheel_delta()
	if mouse_wheel_delta > 0 || k2.key_went_down(.NP_Add) {camera.zoom += .3}
	if mouse_wheel_delta < 0 || k2.key_went_down(.NP_Subtract) {camera.zoom -= .3}

	camera.zoom = clamp(camera.zoom, 1, 4)
	camera.offset = screen_size / 2


	// CAMERA ROTATION

	CAMERA_KEY_ROTATION_SPEED :: 1 // in rads/sec
	camera_key_rotation_delta := CAMERA_KEY_ROTATION_SPEED * frame_time
	if k2.key_is_held(.Z) {camera.rotation += camera_key_rotation_delta}
	if k2.key_is_held(.X) {camera.rotation -= camera_key_rotation_delta}


	// CAMERA RESET

	if k2.key_went_down(.R) do reset_camera()
}

reset_camera :: proc(){
	camera.target = tilemap_grid.position + tilemap_grid.cell_size * {f32(tilemap_grid.width), f32(tilemap_grid.height)} * 0.5;
	camera.zoom = 3
	camera.rotation = 0
}

get_camera_bounds :: proc(camera: ^Camera, screen_size: Vec2) -> CameraBounds {

	points := []Vec2 {
		k2.screen_to_world({0, 0}, camera^),
		k2.screen_to_world({screen_size.x, 0}, camera^),
		k2.screen_to_world({0, screen_size.y}, camera^),
		k2.screen_to_world(screen_size, camera^),
	}

	min_x := points[0].x
	max_x := points[0].x
	min_y := points[0].y
	max_y := points[0].y

	for point in points {
		if point.x < min_x do min_x = point.x
		if point.x > max_x do max_x = point.x
		if point.y < min_y do min_y = point.y
		if point.y > max_y do max_y = point.y
	}

	return {min_x, min_y, max_x, max_y, max_x - min_x, max_y - min_y}
}

draw_grid_lines_inside_camera_bounds :: proc(camera: ^Camera, screen_size: Vec2) {

	camera_bounds := get_camera_bounds(camera, screen_size)

	GRID_LINE_THICKNESS :: 1
	COLOR :: k2.Color { 88, 88, 88, 255 }
	cell_size := f32(16)

	lines_y := camera_bounds.height / cell_size
	start_y := f32(int(camera_bounds.min_y) / int(cell_size)) * cell_size
	if camera_bounds.min_y > 0 do start_y += cell_size

	for y in 0 ..< lines_y {
		k2.draw_line(
			{camera_bounds.min_x, start_y + cell_size * y},
			{camera_bounds.max_x, start_y + cell_size * y},
			GRID_LINE_THICKNESS / camera.zoom,
			COLOR,
		)
	}

	lines_x := camera_bounds.width / cell_size
	start_x := f32(int(camera_bounds.min_x) / int(cell_size)) * cell_size
	if camera_bounds.min_x > 0 do start_x += cell_size

	for x in 0 ..< lines_x {
		k2.draw_line(
			{start_x + cell_size * x, camera_bounds.min_y},
			{start_x + cell_size * x, camera_bounds.max_y},
			GRID_LINE_THICKNESS / camera.zoom,
			COLOR,
		)
	}
}

update_tilemap_grid :: proc(grid: ^TilemapGrid, mouse_world_position: Vec2){

	NONE : u8 : 255
	REMOVE : u8 : 0
	ADD : u8 : 1

	action := NONE
	if k2.mouse_button_is_held(.Left) && !k2.key_is_held(.Left_Control) do action = ADD
	if k2.mouse_button_is_held(.Right) do action = REMOVE

	if action != NONE {
		position := mouse_world_position - grid.position
		if position.x < 0 || position.y < 0 do return

		cell_position := position / grid.cell_size
		x := int(cell_position.x)
		y := int(cell_position.y)

		if x >= grid.width || y >= grid.height do return

		grid.data[grid.width * y + x] = action
	}
}

render_grid :: proc(grid: ^TilemapGrid) {

	size := grid.cell_size * {f32(grid.width), f32(grid.height)}
	k2.draw_rect_outline({grid.position.x, grid.position.y, size.x, size.y}, 2, k2.YELLOW)
}

render_grid_selection :: proc(grid: ^TilemapGrid, mouse_world_position: Vec2) {
	
	position := mouse_world_position - grid.position
	if position.x < 0 || position.y < 0 do return

	cell_position := position / grid.cell_size
	x := int(cell_position.x)
	y := int(cell_position.y)

	if x >= grid.width || y >= grid.height do return

	k2.draw_rect_vec(grid.position + grid.cell_size * Vec2{f32(x), f32(y)}, grid.cell_size, k2.Color{0, 0, 0, 128})
}

render_dual_grid :: proc(grid: ^TilemapGrid, texture: k2.Texture, row: int) {

	rect := k2.Rect{0, f32(row) * grid.cell_size.y, grid.cell_size.x, grid.cell_size.y}
	
	for y in 0..<(grid.height - 1) {
		for x in 0..<(grid.width - 1) {
			
			texture_index := grid.data[grid.width * y + x] != 0 ? 1 : 0
			texture_index <<= 1
			texture_index += grid.data[grid.width * y + x + 1] != 0 ? 1 : 0
			texture_index <<= 1
			texture_index += grid.data[grid.width * (y + 1) + x] != 0 ? 1 : 0
			texture_index <<= 1
			texture_index += grid.data[grid.width * (y + 1) + x + 1] != 0 ? 1 : 0

			rect.x = f32(texture_index) * grid.cell_size.x

			k2.draw_texture_rect(texture, rect, grid.position + {f32(x), f32(y)} * grid.cell_size + grid.cell_size / 2)
		}
	}
}

TextureOption :: struct {
	index: int,
	text: string
}

texture_options := []TextureOption {
	{0, "Basic"},
	{1, "Rounded"},
	{2, "3D"},
	{3, "3DWithGrid"},
	{4, "Bevel"},
}

texture_option_index := 0

increment_texture_option :: proc(){
	texture_option_index += 1
	if texture_option_index >= len(texture_options) {
		texture_option_index = 0
	}
}