// Knock over a stack of boxes by shooting balls at it.
//
// Aim with the mouse and left click to fire. The dotted arc shows where the shot will go: it is the
// same projectile equation Box2D integrates, so it lines up with what actually happens.
package karl2d_box2d_example

import b2 "vendor:box2d"
import k2 "../.."
import "core:math"

// Box2D works in a Y up world, so this example uses a Y up camera. Therefore positions, angles
// and rectangles do not need to be converted.
WORLD_CAMERA :: k2.Camera { zoom = 1, flip_y = true }

SCREEN_WIDTH :: 1280
SCREEN_HEIGHT :: 720

// Box2D scales some of its tolerances by this, so it wants to know how big a metre is. Everything
// here is in pixels, and 40 pixels to the metre makes a 40x40 box a metre across.
PIXELS_PER_METER :: 40
GRAVITY :: -900

GROUND :: k2.Rect { 0, 0, SCREEN_WIDTH, 40 }
PLATFORM :: k2.Rect { 760, 220, 420, 40 }

// Where shots come from, over on the left.
CANNON :: k2.Vec2 { 140, 300 }
BARREL_LENGTH :: 70
BARREL_THICKNESS :: 22

BALL_RADIUS :: 14
BALL_SPEED :: 1250

BALL_DENSITY :: 7

BOX_SIZE :: 40
STACK_ROWS :: 8

world_id: b2.WorldId
time_acc: f32
boxes: [dynamic]b2.BodyId

// Balls live in a fixed ring. If full, then the oldest ball is replaced.
MAX_BALLS :: 16
balls: [MAX_BALLS]b2.BodyId
next_ball: int

main :: proc() {
	init()
	for step() {}
	shutdown()
}

init :: proc() {
	k2.init(SCREEN_WIDTH, SCREEN_HEIGHT, "Karl2D + Box2D example")

	b2.SetLengthUnitsPerMeter(PIXELS_PER_METER)
	world_def := b2.DefaultWorldDef()
	world_def.gravity = b2.Vec2 { 0, GRAVITY }
	world_id = b2.CreateWorld(world_def)

	create_static_box(GROUND)
	create_static_box(PLATFORM)
	build_stack()
}

step :: proc() -> bool {
	if !k2.update() {
		return false
	}

	// Convert the screen-space mouse position to the Y Up world space.
	target := k2.screen_to_camera(k2.get_mouse_position(), WORLD_CAMERA)

	// Shots start at the middle of the cannon and come out from behind the barrel, which is drawn
	// over them. Starting them at the end of the barrel instead would move the launch point every
	// time the barrel turned, and the angle is what turns it.
	aim_dir := launch_direction(CANNON, target)

	if k2.mouse_button_went_down(.Left) {
		// True if the current slot has been reused because `balls` got full.
		if b2.IS_NON_NULL(balls[next_ball]) {
			b2.DestroyBody(balls[next_ball])
		}

		body_def := b2.DefaultBodyDef()
		body_def.type = .dynamicBody
		body_def.position = { CANNON.x, CANNON.y }

		body_id := b2.CreateBody(world_id, body_def)

		shape_def := b2.DefaultShapeDef()
		shape_def.density = BALL_DENSITY
		shape_def.material = {
			friction = 0.3,
			restitution = 0.35,
			rollingResistance = 0.3,
		}

		circle := b2.Circle { radius = BALL_RADIUS }
		_ = b2.CreateCircleShape(body_id, shape_def, &circle)
		b2.Body_SetLinearVelocity(body_id, { aim_dir.x*BALL_SPEED, aim_dir.y*BALL_SPEED })

		balls[next_ball] = body_id
		next_ball = (next_ball + 1) % MAX_BALLS
	}

	if k2.key_went_down(.R) {
		for b in boxes {
			b2.DestroyBody(b)
		}

		for ball in balls {
			if b2.IS_NON_NULL(ball) {
				b2.DestroyBody(ball)
			}
		}

		clear(&boxes)
		balls = {}
		next_ball = 0
		build_stack()
	}

	SUB_STEPS :: 4
	TIME_STEP :: 1.0 / 60

	time_acc += k2.get_frame_time()

	for time_acc >= TIME_STEP {
		b2.World_Step(world_id, TIME_STEP, SUB_STEPS)
		time_acc -= TIME_STEP
	}

	// Balls that left the world would otherwise keep falling forever.
	for &ball in balls {
		if b2.IS_NULL(ball) {
			continue
		}

		position := b2.Body_GetPosition(ball)

		if position.y < -200 || position.x < -200 || position.x > SCREEN_WIDTH + 200 {
			b2.DestroyBody(ball)
			ball = b2.nullBodyId
		}
	}

	k2.clear(k2.LIGHT_BLUE)

	k2.set_camera(WORLD_CAMERA)
	k2.draw_rect(PLATFORM, k2.DARK_GRAY)
	k2.draw_rect(GROUND, k2.GREEN)

	// Where the shot will go. Same constant-acceleration path Box2D integrates, so it matches the
	// real flight until the ball hits something.
	AIM_DOTS :: 30
	AIM_INTERVAL :: 1.0 / 30.0

	for i in 1..=AIM_DOTS {
		t := f32(i)*AIM_INTERVAL
		p := CANNON + aim_dir*BALL_SPEED*t + 0.5*k2.Vec2{0, GRAVITY}*t*t

		if p.y < GROUND.y + GROUND.h {
			break
		}

		k2.draw_circle(p, 3, k2.color_alpha(k2.GRAY, 150), 8)
	}

	for b in boxes {
		position := b2.Body_GetPosition(b)
		r := b2.Body_GetRotation(b)

		// Positions and angles go straight from Box2D into Karl2D without any conversion, because
		// both are Y up here. In a Y down coordinate system both would have to be flipped.
		//
		// Box2D positions a body by its centre, and the origin makes the rect rotate around that
		// same point rather than around its corner.
		rot := math.atan2(r.s, r.c)
		box := k2.Rect { position.x, position.y, BOX_SIZE, BOX_SIZE }
		k2.draw_rect(box, k2.BROWN, { BOX_SIZE/2, BOX_SIZE/2 }, rot)
	}

	for ball in balls {
		if b2.IS_NULL(ball) {
			continue
		}

		position := b2.Body_GetPosition(ball)
		k2.draw_circle({position.x, position.y}, BALL_RADIUS, k2.RED)
	}

	// The barrel pivots on the middle of its near end, so it swings around the cannon rather than
	// around its own corner.
	barrel := k2.Rect { CANNON.x, CANNON.y, BARREL_LENGTH, BARREL_THICKNESS }
	k2.draw_rect(barrel, k2.DARK_GRAY, { 0, BARREL_THICKNESS/2 }, math.atan2(aim_dir.y, aim_dir.x))
	k2.draw_circle(CANNON, 20, k2.GRAY)

	k2.set_camera(nil)
	k2.draw_text("Shoot: Left click\nReset: R", {20, 20}, 24, k2.DARK_BLUE)
	k2.present()

	return true
}

// The direction to fire in so that a ball launched at BALL_SPEED lands on `target`. The speed and
// the gravity are fixed, which leaves the angle as the only unknown.
//
// Two angles reach any target within range, a flat one and a lobbed one. This picks the flat one.
// Targets out of range get the 45 degree shot, which is the furthest the cannon can throw.
launch_direction :: proc(from: k2.Vec2, target: k2.Vec2) -> k2.Vec2 {
	g := f32(-GRAVITY)
	v := f32(BALL_SPEED)
	d := target - from

	// Solved as if the target is to the right, then mirrored, so one formula covers both ways.
	to_the_left := d.x < 0
	dx := abs(d.x)
	angle: f32

	if dx < 1 {
		// Straight above or below, where the formula below would divide by zero.
		angle = math.PI/2 if d.y >= 0 else -math.PI/2
		to_the_left = false
	} else {
		v2 := v*v

		// Negative when no angle gets there.
		discriminant := v2*v2 - g*(g*dx*dx + 2*d.y*v2)

		if discriminant < 0 {
			angle = math.PI/4
		} else {
			angle = math.atan((v2 - math.sqrt(discriminant))/(g*dx))
		}
	}

	if to_the_left {
		angle = math.PI - angle
	}

	return { math.cos(angle), math.sin(angle) }
}

// Puts the pyramid of boxes on top of the platform.
build_stack :: proc() {
	middle := PLATFORM.x + PLATFORM.w/2
	bottom := PLATFORM.y + PLATFORM.h

	for row in 0..<STACK_ROWS {
		count := STACK_ROWS - row
		left := middle - f32(count)*BOX_SIZE/2

		for i in 0..<count {
			body_def := b2.DefaultBodyDef()
			body_def.type = .dynamicBody

			// Box2D places a body by its centre, so aim at the middle of where the box goes.
			body_def.position = {
				left + (f32(i) + 0.5)*BOX_SIZE,
				bottom + (f32(row) + 0.5)*BOX_SIZE,
			}

			body_id := b2.CreateBody(world_id, body_def)

			shape_def := b2.DefaultShapeDef()
			shape_def.density = 1
			shape_def.material.friction = 0.5

			// `MakeBox` takes half extents, measured from the centre of the body.
			box := b2.MakeBox(BOX_SIZE/2, BOX_SIZE/2)
			_ = b2.CreatePolygonShape(body_id, shape_def, &box)

			append(&boxes, body_id)
		}
	}
}

create_static_box :: proc(r: k2.Rect) {
	body_def := b2.DefaultBodyDef()
	body_def.position = { r.x + r.w/2, r.y + r.h/2 }
	body_id := b2.CreateBody(world_id, body_def)

	shape_def := b2.DefaultShapeDef()
	shape_def.material.friction = 0.6

	box := b2.MakeBox(r.w/2, r.h/2)
	_ = b2.CreatePolygonShape(body_id, shape_def, &box)
}

shutdown :: proc() {
	b2.DestroyWorld(world_id)
	delete(boxes)
	k2.shutdown()
}
