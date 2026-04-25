#+vet explicit-allocators
package karl2d_hot_reload_app

// If you use this as the basis for an actual game, then copy karl2d into this folder and just do
// `import k2 "karl2d"`
import k2 "../../.."
import "base:runtime"
import "core:math/linalg"
import "core:fmt"

App_Memory :: struct {
	allocator: runtime.Allocator,
	counter: int,
	player_pos: k2.Vec2,
}

@(private="file")
mem: ^App_Memory

@export
app_startup :: proc(allocator: runtime.Allocator) -> (k2_state: ^k2.State) {
	return k2.init(
		1280,
		720,
		"Karl2D: Hot Reload Example",
		allocator = allocator,
		options = {
			.Windowed_Resizable,
		}
	)
}

@export
app_shutdown :: proc() {
	k2.shutdown()
}

@export
app_init_state :: proc(k2_state: ^k2.State, allocator: runtime.Allocator) {
	mem = new(App_Memory, allocator)
	mem.allocator = allocator
	mem.player_pos = {200, 200}
}

@export
app_destroy_state :: proc() {
	free(mem, mem.allocator)
}


@export
app_update :: proc() -> bool {
	if !k2.update() {
		return false
	}

	movement: k2.Vec2

	if k2.key_is_held(.Up) {
		movement.y -= 1
	}

	if k2.key_is_held(.Down) {
		movement.y += 1
	}

	if k2.key_is_held(.Left) {
		movement.x -= 1
	}

	if k2.key_is_held(.Right) {
		movement.x += 1
	}

	mem.player_pos += linalg.normalize0(movement) * k2.get_frame_time() * 200

	mem.counter += 1
	k2.clear(k2.LIGHT_BLUE)
	k2.draw_circle(mem.player_pos, 100, k2.DARK_BLUE)
	k2.draw_text(fmt.tprint(mem.counter), {20, 20}, 100, k2.BLACK)

	screen_rect := k2.rect_from_pos_size({}, k2.get_screen_size())
	bottom_bar := k2.rect_cut_bottom(&screen_rect, 36, 0)
	k2.draw_rect(bottom_bar, k2.DARK_GRAY)
	bottom_bar = k2.rect_shrink(bottom_bar, 4, 4)
	k2.draw_text("Hot reload by running the `build.odin` program.", k2.rect_top_left(bottom_bar), bottom_bar.h, k2.WHITE)
	source_code_rect := k2.rect_cut_right(&bottom_bar, k2.ui_button_width("Source Code", bottom_bar.h) + 50, 0)

	if k2.ui_button(source_code_rect, "Source Code") {
		k2.open_url("https://github.com/karl-zylinski/karl2d/blob/master/examples/hot_reload/hot_reload.odin")
	}


	k2.present()

	free_all(context.temp_allocator)
	return true
}

@export	
app_memory :: proc() -> ^App_Memory {
	return mem
}

@export
app_memory_size :: proc() -> int {
	return size_of(App_Memory)
}

@export
app_hot_reloaded :: proc(memory: ^App_Memory, k2_state: ^k2.State) {
	k2.set_internal_state(k2_state)
	mem = memory
}

@export
app_force_restart :: proc() -> bool {
	return k2.key_went_down(.F6)
}
