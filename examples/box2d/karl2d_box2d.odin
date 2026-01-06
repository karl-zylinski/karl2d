// This example shows a stack of boxes and the player has a circle that can push the boxes.
//
// This example needs some cleaning up: It leaks lots of box2D things and can perhaps be done more
// compactly. Originally made during a 1h stream: https://www.youtube.com/watch?v=LYW7jdwEnaI
package karl2d_box2d_example

import b2 "vendor:box2d"
import k2 "../.."
import "core:math"

world_id: b2.WorldId
time_acc: f32
circle_body_id: b2.BodyId
bodies: [dynamic]b2.BodyId

GROUND :: k2.Rect {
	0, 600,
	1280, 120,
}

main :: proc() {
	init()
	for step() {}
	shutdown()
}

init :: proc() {
	k2.init(1280, 720, "Karl2D + Box2D example")

	b2.SetLengthUnitsPerMeter(40)
	world_def := b2.DefaultWorldDef()
	world_def.gravity = b2.Vec2{0, -900}
	world_id = b2.CreateWorld(world_def)
	
	ground_body_def := b2.DefaultBodyDef()
	ground_body_def.position = b2.Vec2{GROUND.x, -GROUND.y-GROUND.h}
	ground_body_id := b2.CreateBody(world_id, ground_body_def)

	ground_box := b2.MakeBox(GROUND.w, GROUND.h)
	ground_shape_def := b2.DefaultShapeDef()
	_ = b2.CreatePolygonShape(ground_body_id, ground_shape_def, ground_box)

	px: f32 = 400
	py: f32 = -400

	num_per_row := 10
	num_in_row := 0

	for _ in 0..<50 {
		b := create_box(world_id, {px, py})
		append(&bodies, b)
		num_in_row += 1

		if num_in_row == num_per_row {
			py += 30
			px = 200
			num_per_row -= 1
			num_in_row = 0
		}

		px += 30
	}

	body_def := b2.DefaultBodyDef()
	body_def.type = .dynamicBody
	body_def.position = b2.Vec2{0, 4}
	circle_body_id = b2.CreateBody(world_id, body_def)

	shape_def := b2.DefaultShapeDef()
	shape_def.density = 1000
	shape_def.material.friction = 0.3

	circle: b2.Circle
	circle.radius = 40
	_ = b2.CreateCircleShape(circle_body_id, shape_def, circle)
}

create_box :: proc(world_id: b2.WorldId, pos: b2.Vec2) -> b2.BodyId{
	body_def := b2.DefaultBodyDef()
	body_def.type = .dynamicBody
	body_def.position = pos
	body_id := b2.CreateBody(world_id, body_def)

	shape_def := b2.DefaultShapeDef()
	shape_def.density = 1
	shape_def.material.friction = 0.3

	box := b2.MakeBox(20, 20)
	box_def := b2.DefaultShapeDef()
	_ = b2.CreatePolygonShape(body_id, box_def, box)

	return body_id
}

step :: proc() -> bool {
	if !k2.update() {
		return false
	}

	dt := k2.get_frame_time()
	time_acc += dt
	k2.process_events()
	k2.clear(k2.LIGHT_BLUE)

	k2.draw_rect(GROUND, k2.GREEN)

	pos := k2.get_mouse_position()

	b2.Body_SetTransform(circle_body_id, {pos.x, -pos.y}, {})

	SUB_STEPS :: 4
	TIME_STEP :: 1.0 / 60

	for time_acc >= TIME_STEP {
		b2.World_Step(world_id, TIME_STEP, SUB_STEPS)
		time_acc -= TIME_STEP
	}

	for b in bodies {
		position := b2.Body_GetPosition(b)
		r := b2.Body_GetRotation(b)
		a := math.atan2(r.s, r.c)
		// Y position is flipped because raylib has Y down and box2d has Y up.
		k2.draw_rect_ex({position.x, -position.y, 40, 40}, {20, 20}, a*(180/3.14), k2.BROWN)
	}

	k2.draw_circle(pos, 40, k2.RED)
	k2.present()

	return true
}

shutdown :: proc() {
	b2.DestroyWorld(world_id)
	k2.shutdown()
}