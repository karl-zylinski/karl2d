package karl2d

import rl "raylib"
import "raylib/rlgl"
import "core:log"
import "core:strings"
import "base:runtime"

_init :: proc(width: int, height: int, title: string,
              allocator := context.allocator, loc := #caller_location) -> ^State {
	s = new(State, allocator, loc)
	s.textures = make([dynamic]rl.Texture, allocator, loc)
	s.allocator = allocator
	rl.SetConfigFlags({.WINDOW_RESIZABLE, .VSYNC_HINT})
	rl.InitWindow(i32(width), i32(height), temp_cstring(title))
	return s
}

_shutdown :: proc() {
	rl.CloseWindow()

	if s != nil {
		delete(s.textures)
		a := s.allocator
		free(s, a)
		s = nil
	}
}

_set_internal_state :: proc(new_state: ^State) {
	s = new_state
}

_clear :: proc(color: Color) {
	rl.ClearBackground(rl.Color(color))
}

s: ^State

State :: struct {
	textures: [dynamic]rl.Texture,
	allocator: runtime.Allocator,
	implicitly_created: bool,
}

_load_texture :: proc(filename: string) -> Texture {
	tex := rl.LoadTexture(temp_cstring(filename))

	if tex.id == 0 {
		return {}
	}

	if len(s.textures) == 0 {
		append(&s.textures, rl.Texture{})
	}

	tex_id := Texture_Handle(len(s.textures))
	append(&s.textures, tex)

	return {
		id = tex_id,
		width = int(tex.width),
		height = int(tex.height),
	}
}

_destroy_texture :: proc(tex: Texture) {
	if tex.id < 1 || int(tex.id) >= len(s.textures) {
		return
	}

	rl.UnloadTexture(s.textures[tex.id])
	s.textures[tex.id] = {}
}

_draw_texture :: proc(tex: Texture, pos: Vec2, tint := WHITE) {
	_draw_texture_ex(
		tex,
		{0, 0, f32(tex.width), f32(tex.height)},
		{pos.x, pos.y, f32(tex.width), f32(tex.height)},
		{},
		0,
		tint,
	)
}

_draw_texture_rect :: proc(tex: Texture, rect: Rect, pos: Vec2, tint := WHITE) {
	_draw_texture_ex(
		tex,
		rect,
		{pos.x, pos.y, rect.w, rect.h},
		{},
		0,
		tint,
	)
}

_draw_texture_ex :: proc(tex: Texture, src: Rect, dst: Rect, origin: Vec2, rot: f32, tint := WHITE) {
	if tex.id == 0 {
		log.error("Invalid texture.")
		return
	}

	rl.DrawTexturePro(
		s.textures[tex.id],
		transmute(rl.Rectangle)(src),
		transmute(rl.Rectangle)(dst),
		origin,
		rot,
		rl.Color(tint),
	)
}

_draw_rectangle :: proc(rect: Rect, color: Color) {
	rl.DrawRectangleRec(rl_rect(rect), rl_color(color))
}

_draw_rectangle_outline :: proc(rect: Rect, thickness: f32, color: Color) {
	rl.DrawRectangleLinesEx(rl_rect(rect), thickness, rl_color(color))
}

_draw_circle :: proc(center: Vec2, radius: f32, color: Color) {
	rl.DrawCircleV(center, radius, rl_color(color))
}

_draw_line :: proc(start: Vec2, end: Vec2, thickness: f32, color: Color) {
	rl.DrawLineEx(start, end, thickness, rl_color(color))
}

_get_screen_width :: proc() -> int {
	return int(rl.GetScreenWidth())
}

_get_screen_height :: proc() -> int {
	return int(rl.GetScreenHeight())
}

_key_pressed :: proc(key: Keyboard_Key) -> bool {
	return rl.IsKeyPressed(rl.KeyboardKey(key))
}

_key_released :: proc(key: Keyboard_Key) -> bool {
	return rl.IsKeyReleased(rl.KeyboardKey(key))
}

_key_held :: proc(key: Keyboard_Key) -> bool {
	return rl.IsKeyDown(rl.KeyboardKey(key))
}

_window_should_close :: proc() -> bool {
	return rl.WindowShouldClose()
}

rl_texture :: proc(tex: Texture) -> rl.Texture {
	if tex.id < 1 || int(tex.id) >= len(s.textures) {
		return {}
	}

	return s.textures[tex.id]
}

rl_rect :: proc(r: Rect) -> rl.Rectangle {
	return transmute(rl.Rectangle)(r)
}

rl_color :: proc(c: Color) -> rl.Color {
	return (rl.Color)(c)
}

_draw_text :: proc(text: string, pos: Vec2, font_size: f32, color: Color) {
	rl.DrawTextEx(rl.GetFontDefault(), temp_cstring(text), pos, font_size, 1, rl_color(color))
}

_mouse_button_pressed  :: proc(button: Mouse_Button) -> bool {
	return rl.IsMouseButtonPressed(rl.MouseButton(button))
}

_mouse_button_released :: proc(button: Mouse_Button) -> bool {
	return rl.IsMouseButtonReleased(rl.MouseButton(button))
}

_mouse_button_held     :: proc(button: Mouse_Button) -> bool {
	return rl.IsMouseButtonDown(rl.MouseButton(button))
}

_mouse_wheel_delta :: proc() -> f32 {
	return rl.GetMouseWheelMove()
}

_mouse_position :: proc() -> Vec2 {
	return rl.GetMousePosition()
}

_enable_scissor :: proc(x, y, w, h: int) {
	rl.BeginScissorMode(i32(x), i32(y), i32(w), i32(h))
}

_disable_scissor :: proc() {
	rl.EndScissorMode()
}

_set_window_size :: proc(width: int, height: int) {
	rl.SetWindowSize(i32(width), i32(height))
}

_set_window_position :: proc(x: int, y: int) {
	rl.SetWindowPosition(i32(x), i32(y))
}

_screen_to_world :: proc(pos: Vec2, camera: Camera) -> Vec2 {
	return rl.GetScreenToWorld2D(pos, rl_camera(camera))
}

rl_camera :: proc(camera: Camera) -> rl.Camera2D {
	return {
		offset = camera.origin,
		target = camera.target,
		rotation = camera.rotation,
		zoom = camera.zoom,
	}
}

_set_camera :: proc(camera: Maybe(Camera)) {
	// TODO: Only do something if the camera is actually different.

	rlgl.DrawRenderBatchActive()
	rlgl.LoadIdentity()

	if c, c_ok := camera.?; c_ok {
		camera_mat := rl.MatrixToFloatV(rl.GetCameraMatrix2D(rl_camera(c)))
		rlgl.MultMatrixf(&camera_mat[0])
	}
}

_set_scissor_rect :: proc(scissor_rect: Maybe(Rect)) {
	// TODO: Only do something if the scissor rect is actually different

	rlgl.DrawRenderBatchActive()

	if s, s_ok := scissor_rect.?; s_ok {
		rl.BeginScissorMode(i32(s.x), i32(s.y), i32(s.w), i32(s.h))
	} else {
		rlgl.DisableScissorTest()
	}
}

_process_events :: proc() {
	rl.PollInputEvents()
}

_flush :: proc() {
	rlgl.DrawRenderBatchActive()
}

_present :: proc(do_flush := true) {
	if do_flush {
		rlgl.DrawRenderBatchActive()
	}
	rl.SwapScreenBuffer()
}

temp_cstring :: proc(str: string) -> cstring {
	return strings.clone_to_cstring(str, context.temp_allocator)
}