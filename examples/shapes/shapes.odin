package karl2d_shapes_example

import k2 "../.."
import "core:fmt"

init :: proc() {
	k2.init(1024, 1024, "Karl2D Shapes")
}

step :: proc() -> bool {
	if !k2.update() {
		return false
	}

	if k2.key_went_down(.M) {
		select_next_mode()	
	}

	if k2.key_went_down(.S) {
		select_next_segment()
	}

	if k2.key_went_down(.T) {
		select_next_thickness()
	}

	if k2.key_went_down(.R) {
		select_next_rotation()
	}

	k2.clear(k2.BLACK)

	k2.draw_text(fmt.tprintf("[M] mode: %s", mode_as_text[mode]), {10, 10}, 16, k2.RL_LIGHTGRAY)
	k2.draw_text(fmt.tprintf("[T] thickness: %.1f", thickness_list[thickness_index]), {10, 26}, 16, k2.RL_LIGHTGRAY)
	k2.draw_text(fmt.tprintf("[S] segment: %i", segment_list[segment_index]), {10, 42}, 16, k2.RL_LIGHTGRAY)
	k2.draw_text(fmt.tprintf("[R] rotation: %i", rotation_list[rotation_index]), {10, 58}, 16, k2.RL_LIGHTGRAY)
	
	switch mode {
		case .RectOutline: draw_rect_outline_view()
		case .CircleOutline: draw_circle_outline_view()
	}

	//draw_performance_test()
	
	k2.present()

	free_all(context.temp_allocator)

	return true
}

shutdown :: proc() {
	k2.shutdown()
}

// This is not run by the web version, but it makes this program also work on non-web!
main :: proc() {
	init()
	for step() {}
	shutdown()
}

Mode :: enum {
	RectOutline,
	CircleOutline,
}
mode := Mode.RectOutline
mode_as_text := [Mode]string{
	.RectOutline = "Rectangle outline",
	.CircleOutline = "Circle outline",
}
select_next_mode :: proc(){
	switch mode {
		case .RectOutline: mode = .CircleOutline
		case .CircleOutline: mode = .RectOutline
	}	
}



thickness_list := []f32{0.1, 1, 2, 4, 8, 16, 32}
thickness_index := 4

select_next_thickness :: proc(){
	thickness_index += 1
	if thickness_index >= len(thickness_list) {
		thickness_index = 0
	}
}


segment_list := []int{4, 8, 16, 32, 64}
segment_index := 3

select_next_segment :: proc(){
	segment_index += 1
	if segment_index >= len(segment_list) {
		segment_index = 0
	}
}


rotation_list := []int{0, 1, 2, 4, 8, 16, 32}
rotation_index := 2

select_next_rotation :: proc(){
	rotation_index += 1
	if rotation_index >= len(rotation_list) {
		rotation_index = 0
	}
}

draw_text_centered :: proc(text: string, position: k2.Vec2, font_size: f32, color: k2.Color){
	text_size := k2.measure_text(text, font_size)
	k2.draw_text(text, position - text_size / 2, font_size, color)
}


GRID_SIZE :: 100
GRID_PADDING :: 50
GRID_OFFSET :: 75
get_grid_position :: proc(x: f32, y: f32) -> k2.Vec2{
	return {
		GRID_OFFSET + x * (GRID_SIZE + GRID_PADDING),
		GRID_OFFSET + y * (GRID_SIZE + GRID_PADDING),
	}
}

get_grid_position_rect :: proc(x: f32, y: f32) -> k2.Vec2{
	return {
		GRID_OFFSET + x * (GRID_SIZE + GRID_PADDING) - GRID_SIZE / 2,
		GRID_OFFSET + y * (GRID_SIZE + GRID_PADDING) - GRID_SIZE / 2,
	}
}

get_grid_position_circle :: proc(x: f32, y: f32) -> k2.Vec2{
	return {
		GRID_OFFSET + x * (GRID_SIZE + GRID_PADDING),
		GRID_OFFSET + y * (GRID_SIZE + GRID_PADDING),
	}
}

draw_rect_outline_view :: proc(){
	thickness := thickness_list[thickness_index]
	rotation :=  f32(k2.get_time()) * f32(rotation_list[rotation_index])
	color :=  k2.RL_LIGHTGRAY
	font_size := f32(14)
	size : f32 = 100
	half_size := size / 2
	origin_zero := k2.Vec2{0, 0};
	origin_center := k2.Vec2{size / 2, size / 2};

	draw_text_centered("Normal", get_grid_position(1, 0), font_size, color)
	draw_text_centered("Large thickness", get_grid_position(2,0), font_size, color)
	draw_text_centered("Negative thickness", get_grid_position(3,0), font_size, color)
	draw_text_centered("Wide", get_grid_position(4,0), font_size, color)

	draw_text_centered("rect_outline", get_grid_position(0,1), font_size, color)
	y := get_grid_position_rect(1,1).y
	k2.draw_rect_outline({ get_grid_position_rect(1,1).x, y, size, size}, thickness, color);
	k2.draw_rect_outline({ get_grid_position_rect(2,1).x, y, size, size}, size + thickness, color);
	k2.draw_rect_outline({ get_grid_position_rect(3,1).x, y, size, size}, -thickness, color);
	k2.draw_rect_outline({ get_grid_position_rect(4,1).x, y, size * 2, size}, thickness, color);
	
	draw_text_centered("rect_outline_vec", get_grid_position(0, 2), font_size, color)
	k2.draw_rect_outline_vec(get_grid_position_rect(1,2), {size, size}, thickness, color);
	k2.draw_rect_outline_vec(get_grid_position_rect(2,2), {size, size}, size + thickness, color);
	k2.draw_rect_outline_vec(get_grid_position_rect(3,2), {size, size}, -thickness, color);
	k2.draw_rect_outline_vec(get_grid_position_rect(4,2), {size * 2, size}, thickness, color);
	
	draw_text_centered("rect_outline_ex\n   (rotation)", get_grid_position(0,3), font_size, color)
	y = get_grid_position_rect(1,3).y
	k2.draw_rect_outline_ex({get_grid_position_rect(1,3).x, y, size, size}, origin_zero, rotation, thickness, color);
	k2.draw_rect_outline_ex({get_grid_position_rect(2,3).x, y, size, size}, origin_zero, rotation, size + thickness, color);
	k2.draw_rect_outline_ex({get_grid_position_rect(3,3).x, y, size, size}, origin_zero, rotation, -thickness, color);
	k2.draw_rect_outline_ex({get_grid_position_rect(4,3).x, y, size * 2, size}, origin_zero, rotation, thickness, color);

	draw_text_centered("    rect_outline_ex\n(origin and rotation)", get_grid_position(0,4), font_size, color)
	y = get_grid_position_rect(1,4).y + half_size
	k2.draw_rect_outline_ex({get_grid_position_rect(1,4).x + half_size, y, size, size}, origin_center, rotation, thickness, color);
	k2.draw_rect_outline_ex({get_grid_position_rect(2,4).x + half_size, y, size, size}, origin_center, rotation, size + thickness, color);
	k2.draw_rect_outline_ex({get_grid_position_rect(3,4).x + half_size, y, size, size}, origin_center, rotation, -thickness, color);
	k2.draw_rect_outline_ex({get_grid_position_rect(4,4).x + size, y, size * 2, size}, {size, size / 2}, rotation, thickness, color);
}

draw_circle_outline_view :: proc(){
	thickness := thickness_list[thickness_index]
	rotation :=  f32(k2.get_time()) * f32(rotation_list[rotation_index])
	radius : f32 = 100 / 2
	half_radius := radius / 2

	segments := segment_list[segment_index]

	font_size := f32(14)

	draw_text_centered("Normal", get_grid_position(1, 0), font_size, k2.RL_LIGHTGRAY)
	draw_text_centered("Large thickness", get_grid_position(2,0), font_size, k2.RL_LIGHTGRAY)
	draw_text_centered("Negative thickness", get_grid_position(3,0), font_size, k2.RL_LIGHTGRAY)

	draw_text_centered("circle_outline", get_grid_position(0, 1), font_size, k2.RL_LIGHTGRAY)
	k2.draw_circle_outline(get_grid_position_circle(1, 1), radius, thickness, k2.RL_LIGHTGRAY, segments)
	k2.draw_circle_outline(get_grid_position_circle(2, 1), radius, radius * 2, k2.RL_LIGHTGRAY, segments)
	k2.draw_circle_outline(get_grid_position_circle(3, 1), radius, -thickness, k2.RL_LIGHTGRAY, segments)

	draw_text_centered("circle_outline_ex\n    (rotation)", get_grid_position(0, 2), font_size, k2.RL_LIGHTGRAY)
	k2.draw_circle_outline_ex(get_grid_position_circle(1, 2), radius, {0, 0}, rotation, thickness, k2.RL_LIGHTGRAY, segments)
	k2.draw_circle_outline_ex(get_grid_position_circle(2, 2), radius, {0, 0}, rotation, radius * 2, k2.RL_LIGHTGRAY, segments)
	k2.draw_circle_outline_ex(get_grid_position_circle(3, 2), radius, {0, 0}, rotation, -thickness, k2.RL_LIGHTGRAY, segments)

	draw_text_centered("    circle_outline_ex\n(origin and rotation)",  get_grid_position(0, 3), font_size, k2.RL_LIGHTGRAY)
	k2.draw_circle_outline_ex(get_grid_position_circle(1, 3), radius, {half_radius, half_radius}, rotation, thickness, k2.RL_LIGHTGRAY, segments)
	k2.draw_circle_outline_ex(get_grid_position_circle(2, 3), radius, {half_radius, half_radius}, rotation, radius * 2, k2.RL_LIGHTGRAY, segments)
	k2.draw_circle_outline_ex(get_grid_position_circle(3, 3), radius, {half_radius, half_radius}, rotation, -thickness, k2.RL_LIGHTGRAY, segments)
}