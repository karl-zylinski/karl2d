// Knock over a stack of boxes by shooting balls at it.
//
// Aim with the mouse and left click to fire. The dotted arc shows where the shot will go: it is the
// same projectile equation Box2D integrates, so it lines up with what actually happens.
//
// Originally made during a 1h stream: https://www.youtube.com/watch?v=LYW7jdwEnaI
package karl2d_box2d_example

import b2 "vendor:box2d"
import k2 "../.."
import "core:math"
import "core:math/linalg"

// Box2D works in a Y up world, so this example uses Karl2D's Y up coordinate system too. That way
// positions and angles pass between the two without any conversion. Everything below is in Box2D
// world coordinates, which here are also screen coordinates: one unit is one pixel.
#assert(k2.Y_UP, "This example assumes Y up. Compile it with -define:KARL2D_Y_UP=true")

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

// Older balls are removed once there are this many, so a long session doesn't keep piling up
// bodies that are no longer interesting.
MAX_BALLS :: 16

BOX_SIZE :: 40
STACK_ROWS :: 6

world_id: b2.WorldId
time_acc: f32
boxes: [dynamic]b2.BodyId
balls: [dynamic]b2.BodyId

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

shutdown :: proc() {
	// The world owns every body in it, so this is all the physics cleanup there is.
	b2.DestroyWorld(world_id)
	delete(boxes)
	delete(balls)
	k2.shutdown()
}

step :: proc() -> bool {
	// `update` processes this frame's events, so the "went down" checks below see them. Calling
	// `process_events` again here would clear them before anything got to look.
	if !k2.update() {
		return false
	}

	// The mouse position is already in the same coordinate system as the physics world, so it can
	// be used to aim without converting anything.
	aim_from := barrel_tip()
	aim_dir := linalg.normalize0(k2.get_mouse_position() - CANNON)

	if k2.mouse_button_went_down(.Left) {
		fire(aim_from, aim_dir)
	}

	if k2.key_went_down(.R) {
		reset()
	}

	SUB_STEPS :: 4
	TIME_STEP :: 1.0 / 60

	time_acc += k2.get_frame_time()

	for time_acc >= TIME_STEP {
		b2.World_Step(world_id, TIME_STEP, SUB_STEPS)
		time_acc -= TIME_STEP
	}

	remove_fallen_balls()

	k2.clear(k2.LIGHT_BLUE)
	k2.draw_rect(PLATFORM, k2.DARK_GRAY)
	k2.draw_rect(GROUND, k2.GREEN)

	draw_aim(aim_from, aim_dir)

	for b in boxes {
		draw_body_rect(b, BOX_SIZE, k2.BROWN)
	}

	for b in balls {
		position := b2.Body_GetPosition(b)
		k2.draw_circle({position.x, position.y}, BALL_RADIUS, k2.RED)
	}

	draw_cannon(aim_dir)

	k2.draw_text("Left click to shoot, R to reset", {20, SCREEN_HEIGHT - 44}, 24, k2.DARK_BLUE)
	k2.present()

	return true
}

// Puts the pyramid of boxes on top of the platform.
build_stack :: proc() {
	middle := PLATFORM.x + PLATFORM.w/2
	bottom := PLATFORM.y + PLATFORM.h

	for row in 0..<STACK_ROWS {
		count := STACK_ROWS - row
		left := middle - f32(count)*BOX_SIZE/2

		for i in 0..<count {
			// Box2D places a body by its centre, so aim at the middle of where the box goes.
			centre := b2.Vec2 {
				left + (f32(i) + 0.5)*BOX_SIZE,
				bottom + (f32(row) + 0.5)*BOX_SIZE,
			}

			append(&boxes, create_box(centre))
		}
	}
}

// Destroys everything that moves and builds the stack again.
reset :: proc() {
	for b in boxes {
		b2.DestroyBody(b)
	}

	for b in balls {
		b2.DestroyBody(b)
	}

	clear(&boxes)
	clear(&balls)
	build_stack()
}

fire :: proc(from: k2.Vec2, dir: k2.Vec2) {
	if len(balls) >= MAX_BALLS {
		b2.DestroyBody(balls[0])
		ordered_remove(&balls, 0)
	}

	body_def := b2.DefaultBodyDef()
	body_def.type = .dynamicBody
	body_def.position = { from.x, from.y }

	// Shots are fast and small, so ask Box2D not to let them pass through thin things.
	body_def.isBullet = true
	body_id := b2.CreateBody(world_id, body_def)

	// Heavy enough to knock a good part of the stack over, light enough that one shot doesn't
	// level the whole thing.
	shape_def := b2.DefaultShapeDef()
	shape_def.density = 5
	shape_def.material.friction = 0.3
	shape_def.material.restitution = 0.35

	circle := b2.Circle { radius = BALL_RADIUS }
	_ = b2.CreateCircleShape(body_id, shape_def, &circle)

	b2.Body_SetLinearVelocity(body_id, { dir.x*BALL_SPEED, dir.y*BALL_SPEED })
	append(&balls, body_id)
}

// Balls that leave the world would otherwise fall forever.
remove_fallen_balls :: proc() {
	for i := len(balls) - 1; i >= 0; i -= 1 {
		position := b2.Body_GetPosition(balls[i])

		if position.y < -200 || position.x < -200 || position.x > SCREEN_WIDTH + 200 {
			b2.DestroyBody(balls[i])
			ordered_remove(&balls, i)
		}
	}
}

create_box :: proc(centre: b2.Vec2) -> b2.BodyId {
	body_def := b2.DefaultBodyDef()
	body_def.type = .dynamicBody
	body_def.position = centre
	body_id := b2.CreateBody(world_id, body_def)

	shape_def := b2.DefaultShapeDef()
	shape_def.density = 1
	shape_def.material.friction = 0.5

	// `MakeBox` takes half extents, measured from the centre of the body.
	box := b2.MakeBox(BOX_SIZE/2, BOX_SIZE/2)
	_ = b2.CreatePolygonShape(body_id, shape_def, &box)

	return body_id
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

// Where the ball leaves the barrel.
barrel_tip :: proc() -> k2.Vec2 {
	dir := linalg.normalize0(k2.get_mouse_position() - CANNON)
	return CANNON + dir*BARREL_LENGTH
}

draw_cannon :: proc(dir: k2.Vec2) {
	// Positive rotations turn counter-clockwise in a Y up coordinate system, which is what
	// `atan2` gives, so the angle goes straight into `draw_rect`.
	angle := math.atan2(dir.y, dir.x)

	// The origin puts the pivot at the middle of the barrel's near end, so it swings around the
	// cannon rather than around its own corner.
	barrel := k2.Rect { CANNON.x, CANNON.y, BARREL_LENGTH, BARREL_THICKNESS }
	k2.draw_rect(barrel, k2.DARK_GRAY, { 0, BARREL_THICKNESS/2 }, angle)
	k2.draw_circle(CANNON, 20, k2.GRAY)
}

// Plots where the shot will land. This is the same constant-acceleration path Box2D integrates, so
// it matches the real flight until the ball hits something.
draw_aim :: proc(from: k2.Vec2, dir: k2.Vec2) {
	velocity := dir*BALL_SPEED

	DOTS :: 30
	DOT_INTERVAL :: 1.0 / 30.0

	for i in 1..=DOTS {
		t := f32(i)*DOT_INTERVAL
		p := from + velocity*t + 0.5*k2.Vec2{0, GRAVITY}*t*t

		if p.y < GROUND.y + GROUND.h {
			break
		}

		k2.draw_circle(p, 3, k2.color_alpha(k2.WHITE, 150), 8)
	}
}

draw_body_rect :: proc(body: b2.BodyId, size: f32, color: k2.Color) {
	position := b2.Body_GetPosition(body)
	r := b2.Body_GetRotation(body)

	// Positions and angles go straight from Box2D into Karl2D without any conversion, because both
	// are Y up here. In a Y down coordinate system both would have to be flipped.
	rot := math.atan2(r.s, r.c)
	half := size/2

	// Box2D positions a body by its centre, and the origin makes the rect rotate around that same
	// point rather than around its corner.
	k2.draw_rect({position.x, position.y, size, size}, color, {half, half}, rot)
}
