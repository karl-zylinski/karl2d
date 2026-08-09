// This example shows a stack of boxes and the player has a circle that can push the boxes.
//
// This example needs some cleaning up: It leaks lots of box2D things and can perhaps be done more
// compactly. Originally made during a 1h stream: https://www.youtube.com/watch?v=LYW7jdwEnaI
package karl2d_box2d_example

import b2 "vendor:box2d"
import k2 "../.."
import "core:math"

// Box2D works in a Y up world: gravity pulls towards negative Y and positive angles turn
// counter-clockwise. This example keeps all of its own positions in that world, and converts at the
// point where it hands them to Karl2D.
//
// Compile with `-define:KARL2D_Y_UP=true` and every conversion below becomes the identity, which is
// the whole point of the Y up coordinate system. Without it the conversions do the flipping that any
// Y down 2D library needs when it talks to a physics engine.

// Convert a point from the Box2D world into Karl2D's coordinate system.
world_to_k2 :: proc(p: b2.Vec2) -> k2.Vec2 {
	when k2.Y_UP {
		return { p.x, p.y }
	} else {
		// Y down: flip, and put the Box2D origin at the bottom-left corner of the window.
		return { p.x, f32(k2.get_screen_height()) - p.y }
	}
}

// Convert a point from Karl2D's coordinate system back into the Box2D world.
k2_to_world :: proc(p: k2.Vec2) -> b2.Vec2 {
	when k2.Y_UP {
		return { p.x, p.y }
	} else {
		return { p.x, f32(k2.get_screen_height()) - p.y }
	}
}

// Convert a rectangle from the Box2D world, where `y` is its bottom edge, into a Karl2D rectangle.
world_to_k2_rect :: proc(r: k2.Rect) -> k2.Rect {
	when k2.Y_UP {
		return r
	} else {
		return { r.x, f32(k2.get_screen_height()) - r.y - r.h, r.w, r.h }
	}
}

// Convert an angle. Positive is counter-clockwise on screen in Y up, clockwise in Y down.
world_to_k2_rotation :: proc(radians: f32) -> f32 {
	when k2.Y_UP {
		return radians
	} else {
		return -radians
	}
}

world_id: b2.WorldId
time_acc: f32
circle_body_id: b2.BodyId
bodies: [dynamic]b2.BodyId

// In Box2D world coordinates: sitting on the ground plane, extending upwards.
GROUND :: k2.Rect {
	0, 0,
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
	ground_body_def.position = b2.Vec2{GROUND.x, GROUND.y}
	ground_body_id := b2.CreateBody(world_id, ground_body_def)

	ground_box := b2.MakeBox(GROUND.w, GROUND.h)
	ground_shape_def := b2.DefaultShapeDef()
	_ = b2.CreatePolygonShape(ground_body_id, ground_shape_def, &ground_box)

	px: f32 = 400
	py: f32 = 400

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
	_ = b2.CreateCircleShape(circle_body_id, shape_def, &circle)
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
	_ = b2.CreatePolygonShape(body_id, box_def, &box)

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

	k2.draw_rect(world_to_k2_rect(GROUND), k2.GREEN)

	pos := k2.get_mouse_position()

	b2.Body_SetTransform(circle_body_id, k2_to_world(pos), {})

	SUB_STEPS :: 4
	TIME_STEP :: 1.0 / 60

	for time_acc >= TIME_STEP {
		b2.World_Step(world_id, TIME_STEP, SUB_STEPS)
		time_acc -= TIME_STEP
	}

	for b in bodies {
		position := b2.Body_GetPosition(b)
		r := b2.Body_GetRotation(b)
		rot := math.atan2(r.s, r.c)

		// The origin of half the size makes the box sit centred on its Box2D position and spin
		// around that same point.
		c := world_to_k2(position)
		k2.draw_rect({c.x, c.y, 40, 40}, k2.BROWN, {20, 20}, world_to_k2_rotation(rot))
	}

	k2.draw_circle(pos, 40, k2.RED)
	k2.present()

	return true
}

shutdown :: proc() {
	b2.DestroyWorld(world_id)
	k2.shutdown()
}