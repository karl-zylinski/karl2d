package snake

import k2 "../.."
import "core:math"
import "core:fmt"
import "core:time"
import "core:math/rand"
import "base:intrinsics"
import "core:log"
import "core:mem"

WINDOW_SIZE :: 1000
GRID_WIDTH :: 20
CELL_SIZE :: 16
CANVAS_SIZE :: GRID_WIDTH*CELL_SIZE
TICK_RATE :: 0.13
Vec2i :: [2]int
MAX_SNAKE_LENGTH :: GRID_WIDTH*GRID_WIDTH

snake: [MAX_SNAKE_LENGTH]Vec2i
snake_length: int
tick_timer: f32 = TICK_RATE
move_direction: Vec2i
game_over: bool
food_pos: Vec2i

place_food :: proc() {
	occupied: [GRID_WIDTH][GRID_WIDTH]bool

	for i in 0..<snake_length {
		occupied[snake[i].x][snake[i].y] = true
	}

	free_cells := make([dynamic]Vec2i, context.temp_allocator)

	for x in 0..<GRID_WIDTH {
		for y in 0..<GRID_WIDTH {
			if !occupied[x][y] {
				append(&free_cells, Vec2i {x, y})
			}
		}
	}

	if len(free_cells) > 0 {
		random_cell_index := rand.int31_max(i32(len(free_cells)))
		food_pos = free_cells[random_cell_index]
	}

}

restart :: proc() {
	start_head_pos := Vec2i { GRID_WIDTH / 2, GRID_WIDTH / 2 }
	snake[0] = start_head_pos
	snake[1] = start_head_pos - {0, 1}
	snake[2] = start_head_pos - {0, 2}
	snake_length = 3
	move_direction = {0, 1}
	game_over = false
	place_food()
}

main :: proc() {
	context.logger = log.create_console_logger()

	when ODIN_DEBUG {
		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		context.allocator = mem.tracking_allocator(&track)

		defer {
			if len(track.allocation_map) > 0 {
				for _, entry in track.allocation_map {
					fmt.eprintf("%v leaked: %v bytes\n", entry.location, entry.size)
				}
			}
			mem.tracking_allocator_destroy(&track)
		}
	}

	k2.init(WINDOW_SIZE, WINDOW_SIZE, "Snake")

	SHADER_SOURCE :: #load("shader.hlsl")

	shader := k2.load_shader(string(SHADER_SOURCE), {
		.RG32_Float,
		.RG32_Float,
		.RGBA8_Norm,
		.RG32_Float,
	})

	prev_time := time.now()

	restart()

	food_sprite := k2.load_texture_from_file("food.png")
	head_sprite := k2.load_texture_from_file("head.png")
	body_sprite := k2.load_texture_from_file("body.png")
	tail_sprite := k2.load_texture_from_file("tail.png")

	food_eaten_at := time.now()
	started_at := time.now()

	for !k2.close_window_wanted() {
		time_now := time.now()
		dt := f32(time.duration_seconds(time.diff(prev_time, time_now)))
		prev_time = time_now
		total_time := time.duration_seconds(time.diff(started_at, time_now))
		k2.process_events()

		if k2.key_is_held(.Up) {
			move_direction = {0, -1}
		}

		if k2.key_is_held(.Down) {
			move_direction = {0, 1}
		}

		if k2.key_is_held(.Left) {
			move_direction = {-1, 0}
		}

		if k2.key_is_held(.Right) {
			move_direction = {1, 0}
		}

		if game_over {
			if k2.key_went_down(.Enter) {
				restart()
			}
		} else {
			tick_timer -= dt
		}

		if tick_timer <= 0 {
			next_part_pos := snake[0]
			snake[0] += move_direction
			head_pos := snake[0]

			if head_pos.x < 0 || head_pos.y < 0 || head_pos.x >= GRID_WIDTH || head_pos.y >= GRID_WIDTH {
				game_over = true
			}

			for i in 1..<snake_length {
				cur_pos := snake[i]

				if cur_pos == head_pos {
					game_over = true
				}

				snake[i] = next_part_pos
				next_part_pos = cur_pos
			}

			if head_pos == food_pos {
				snake_length += 1
				snake[snake_length - 1] = next_part_pos
				place_food()
				food_eaten_at = time.now()
			}

			tick_timer = TICK_RATE + tick_timer
		}

		k2.clear({76, 53, 83, 255})
		k2.set_shader(shader)

		camera := k2.Camera {
			zoom = f32(WINDOW_SIZE) / CANVAS_SIZE,
		}
		
		k2.set_camera(camera)
		food_sprite.width = CELL_SIZE
		food_sprite.height = CELL_SIZE
		k2.draw_texture(food_sprite, {f32(food_pos.x), f32(food_pos.y)}*CELL_SIZE)

		time_since_food := time.duration_seconds(time.diff(food_eaten_at, time_now))

		if time_since_food < 0.5 && total_time > 1 {
			shader.input_overrides[3] = k2.create_vertex_input_override(k2.Vec2{f32(math.cos(total_time*100)), f32(math.sin(total_time*120 + 3))})
		}

		for i in 0..<snake_length {
			part_sprite := body_sprite
			dir: Vec2i

			if i == 0 {
				part_sprite = head_sprite
				dir = snake[i] - snake[i + 1]
			} else if i == snake_length - 1 {
				part_sprite = tail_sprite
				dir = snake[i - 1] - snake[i]
			} else {
				dir = snake[i - 1] - snake[i]
			}

			rot := math.atan2(f32(dir.y), f32(dir.x)) * math.DEG_PER_RAD

			source := k2.Rect {
				0, 0,
				f32(part_sprite.width), f32(part_sprite.height),
			}

			dest := k2.Rect {
				f32(snake[i].x)*CELL_SIZE + 0.5*CELL_SIZE,
				f32(snake[i].y)*CELL_SIZE + 0.5*CELL_SIZE,
				CELL_SIZE,
				CELL_SIZE,
			}

			k2.draw_texture_ex(part_sprite, source, dest, {CELL_SIZE, CELL_SIZE}*0.5, rot)
		}

		if game_over {
			k2.draw_text("Game Over!", {4, 4}, 25, k2.RED)
			k2.draw_text("Press Enter to play again", {4, 30}, 15, k2.BLACK)
		}

		shader.input_overrides[3] = {}

		score := snake_length - 3
		score_str := fmt.tprintf("Score: %v", score)
		k2.draw_text(score_str, {4, CANVAS_SIZE - 14}, 10, k2.GRAY)
		k2.present()

		free_all(context.temp_allocator)
	}

	k2.destroy_shader(shader)
	k2.destroy_texture(head_sprite)
	k2.destroy_texture(food_sprite)
	k2.destroy_texture(body_sprite)
	k2.destroy_texture(tail_sprite)

	k2.shutdown()
}