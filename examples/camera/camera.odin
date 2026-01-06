package karl2d_camera_example

import k2 "../.."
import "core:fmt"
import "core:math/linalg"

Vec2 :: k2.Vec2

camera: k2.Camera // world camera

init :: proc() {
	k2.init(1280, 720, "Karl2D Camera Demo", {window_mode = .Windowed_Resizable})
}

step :: proc() -> bool {
	if !k2.update() {
		return false
	}
	
	screen_size := Vec2 { f32(k2.get_screen_width()), f32(k2.get_screen_height()) }
	mouse_screen_pos := k2.get_mouse_position()
	mouse_world_pos := k2.screen_to_world(k2.get_mouse_position(), camera)
	frame_time := k2.get_frame_time()

	// CAMERA PANNING

	camera_target_movement: Vec2 
	if k2.mouse_button_is_held(.Left) {
		camera_target_movement -= k2.get_mouse_delta() / camera.zoom
	}

	CAMERA_KEY_MOVE_SPEED :: 300 // in screen pixels/sec
	camera_key_move_delta := CAMERA_KEY_MOVE_SPEED*frame_time / camera.zoom
	if k2.key_is_held(.Right) { camera_target_movement.x += camera_key_move_delta }
	if k2.key_is_held(.Left)  { camera_target_movement.x -= camera_key_move_delta }
	if k2.key_is_held(.Down)  { camera_target_movement.y += camera_key_move_delta }
	if k2.key_is_held(.Up) 	  { camera_target_movement.y -= camera_key_move_delta }

	// Multiplying camera movement with rotation matrix makes it move like the player expects,
	// relative to the axes of the window, not the axes of the camera.
	rotation_matrix := linalg.matrix2_rotate(-camera.rotation)
	camera.target += rotation_matrix * camera_target_movement

	camera.target = {
		clamp(camera.target.x, -1000, 1000),
		clamp(camera.target.y, -1000, 1000),
	}

	// CAMERA RESET

	if k2.key_went_down(.R) { camera = { zoom = 1 } }

	// CAMERA ZOOM

	mouse_wheel_delta := k2.get_mouse_wheel_delta()
	if mouse_wheel_delta > 0 || k2.key_went_down(.NP_Add) { camera.zoom += .3 }
	if mouse_wheel_delta < 0 || k2.key_went_down(.NP_Subtract) { camera.zoom -= .3 }

	camera.zoom = clamp(camera.zoom, 1, 4)
	camera.offset = screen_size / 2

	// CAMERA ROTATION

	CAMERA_KEY_ROTATION_SPEED :: 1 // in rads/sec
	camera_key_rotation_delta := CAMERA_KEY_ROTATION_SPEED*frame_time
	if k2.key_is_held(.Z) { camera.rotation += camera_key_rotation_delta }
	if k2.key_is_held(.X) { camera.rotation -= camera_key_rotation_delta }

	// DRAW WORLD

	k2.set_camera(camera)
	k2.clear(k2.DARK_GRAY)

	for i in -10..=+10 {
		thick := camera.zoom * (i==0 ? 4 : 1)
		color := i==0 ? k2.LIGHT_GREEN : k2.GREEN
		k2.draw_line({100*f32(i),-1000}, {100*f32(i),1000}, thick, color)
		k2.draw_line({-1000,100*f32(i)}, {1000,100*f32(i)}, thick, color)

		if i == 0 {
			k2.draw_line({0,-1000}, {0,1000}, 1, k2.RED)
			k2.draw_line({-1000,0}, {1000,0}, 1, k2.RED)
		}
	}

	k2.draw_circle({}, 200, k2.color_alpha(k2.RED, 80))
	k2.draw_circle_outline({}, 200, 20, k2.color_alpha(k2.WHITE, 80))

	// DRAW STATS

	k2.set_camera(nil)

	font_size := f32(32)
	text_color := k2.WHITE
	text_pos := Vec2 { 20, 20 }

	frame_time_text := fmt.tprintf("frame time: %.3f ms", frame_time*1000)
	k2.draw_text(frame_time_text, text_pos, font_size, text_color)
	text_pos.y += font_size

	screen_size_text := fmt.tprintf("screen size: %v", screen_size)
	k2.draw_text(screen_size_text, text_pos, font_size, text_color)
	text_pos.y += font_size

	mouse_screen_pos_text := fmt.tprintf("mouse pos: %v", mouse_screen_pos)
	k2.draw_text(mouse_screen_pos_text, text_pos, font_size, text_color)
	text_pos.y += font_size

	camera_zoom_text := fmt.tprintf("camera zoom: x%.1f", camera.zoom)
	k2.draw_text(camera_zoom_text, text_pos, font_size, text_color)
	text_pos.y += font_size

	camera_rotation_text := fmt.tprintf("camera rotation: %.2f rad", camera.rotation)
	k2.draw_text(camera_rotation_text, text_pos, font_size, text_color)
	text_pos.y += font_size

	camera_target_text := fmt.tprintf("camera target: %.3f", camera.target)
	k2.draw_text(camera_target_text, text_pos, font_size, text_color)
	text_pos.y += font_size

	mouse_world_pos_text := fmt.tprintf("mouse world pos: %.3f", mouse_world_pos)
	k2.draw_text(mouse_world_pos_text, text_pos, font_size, text_color)
	text_pos.y += font_size

	// DRAW HINTS

	font_size = 24
	text_color = k2.YELLOW
	text_pos = Vec2 { 20, screen_size.y - 20 - font_size }

	k2.draw_text("use R to reset", text_pos, font_size, text_color)
	text_pos.y -= font_size

	k2.draw_text("use Z/X keys to rotate", text_pos, font_size, text_color)
	text_pos.y -= font_size

	k2.draw_text("use Plus/Minus keys or the mouse wheel to zoom", text_pos, font_size, text_color)
	text_pos.y -= font_size

	k2.draw_text("use arrow keys or the left mouse button to pan", text_pos, font_size, text_color)
	text_pos.y -= font_size

	// SHOW WHAT WE DREW TO PLAYER

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
