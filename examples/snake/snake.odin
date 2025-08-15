package snake

import kl "../.."
import "core:math"
import "core:fmt"
import "core:time"
import "core:math/rand"

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
	kl.init(WINDOW_SIZE, WINDOW_SIZE, "Snake")
	prev_time := time.now()

	restart()

	food_sprite := kl.load_texture_from_file("food.png")
	head_sprite := kl.load_texture_from_file("head.png")
	body_sprite := kl.load_texture_from_file("body.png")
	tail_sprite := kl.load_texture_from_file("tail.png")

	for !kl.window_should_close() {
		time_now := time.now()
		dt := f32(time.duration_seconds(time.diff(prev_time, time_now)))
		prev_time = time_now
		kl.process_events()

		if kl.key_is_held(.Up) {
			move_direction = {0, -1}
		}

		if kl.key_is_held(.Down) {
			move_direction = {0, 1}
		}

		if kl.key_is_held(.Left) {
			move_direction = {-1, 0}
		}

		if kl.key_is_held(.Right) {
			move_direction = {1, 0}
		}

		if game_over {
			if kl.key_went_down(.Enter) {
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
			}

			tick_timer = TICK_RATE + tick_timer
		}

		kl.clear({76, 53, 83, 255})

		camera := kl.Camera {
			zoom = f32(WINDOW_SIZE) / CANVAS_SIZE,
		}

		kl.set_camera(camera)
		kl.draw_texture(food_sprite, {f32(food_pos.x), f32(food_pos.y)}*CELL_SIZE)

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

			source := kl.Rect {
				0, 0,
				f32(part_sprite.width), f32(part_sprite.height),
			}

			dest := kl.Rect {
				f32(snake[i].x)*CELL_SIZE + 0.5*CELL_SIZE,
				f32(snake[i].y)*CELL_SIZE + 0.5*CELL_SIZE,
				CELL_SIZE,
				CELL_SIZE,
			}

			kl.draw_texture_ex(part_sprite, source, dest, {CELL_SIZE, CELL_SIZE}*0.5, rot)
		}

		if game_over {
			kl.draw_text("Game Over!", {4, 4}, 25, kl.RED)
			kl.draw_text("Press Enter to play again", {4, 30}, 15, kl.BLACK)
		}

		score := snake_length - 3
		score_str := fmt.tprintf("Score: %v", score)
		kl.draw_text(score_str, {4, CANVAS_SIZE - 14}, 10, kl.GRAY)
		kl.present()

		free_all(context.temp_allocator)
	}

	kl.destroy_texture(head_sprite)
	kl.destroy_texture(food_sprite)
	kl.destroy_texture(body_sprite)
	kl.destroy_texture(tail_sprite)

	kl.shutdown()
}