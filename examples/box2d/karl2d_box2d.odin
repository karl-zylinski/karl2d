package karl2d_box2d_example

import b2 "vendor:box2d"
import k2 "../.."
import "core:math"
import "core:time"
import "core:log"

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

main :: proc() {
	context.logger = log.create_console_logger()
	k2.init(1280, 720, "Karl2D + Box2D example")

	b2.SetLengthUnitsPerMeter(40)
	world_def := b2.DefaultWorldDef()
	world_def.gravity = b2.Vec2{0, -900}
	world_id := b2.CreateWorld(world_def)
	defer b2.DestroyWorld(world_id)

	ground := k2.Rect {
		0, 600,
		1280, 120,
	}

	ground_body_def := b2.DefaultBodyDef()
	ground_body_def.position = b2.Vec2{ground.x, -ground.y-ground.h}
	ground_body_id := b2.CreateBody(world_id, ground_body_def)

	ground_box := b2.MakeBox(ground.w, ground.h)
	ground_shape_def := b2.DefaultShapeDef()
	_ = b2.CreatePolygonShape(ground_body_id, ground_shape_def, ground_box)

	bodies: [dynamic]b2.BodyId

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
	body_id := b2.CreateBody(world_id, body_def)

	shape_def := b2.DefaultShapeDef()
	shape_def.density = 1000
	shape_def.material.friction = 0.3

	circle: b2.Circle
	circle.radius = 40
	_ = b2.CreateCircleShape(body_id, shape_def, circle)

	time_step: f32 = 1.0 / 60
	sub_steps: i32 = 4

	prev_time := time.now()

	time_acc: f32

	for !k2.shutdown_wanted() {
		cur_time := time.now()
		dt := f32(time.duration_seconds(time.diff(prev_time, cur_time)))
		prev_time = cur_time

		time_acc += dt
		k2.process_events()
		k2.clear(k2.BLACK)

		k2.draw_rect(ground, k2.RL_RED)
		mouse_pos := k2.get_mouse_position()

		b2.Body_SetTransform(body_id, {mouse_pos.x, -mouse_pos.y}, {})

		for time_acc >= time_step {
			b2.World_Step(world_id, time_step, sub_steps)
			time_acc -= time_step
		}

		for b in bodies {
			position := b2.Body_GetPosition(b)
			r := b2.Body_GetRotation(b)
			a := math.atan2(r.s, r.c)
			// Y position is flipped because raylib has Y down and box2d has Y up.
			k2.draw_rect_ex({position.x, -position.y, 40, 40}, {20, 20}, a*(180/3.14), k2.RL_YELLOW)
		}

		k2.draw_circle(mouse_pos, 40, k2.RL_MAGENTA)
		k2.present()

		free_all(context.temp_allocator)
	}

	k2.shutdown()
}