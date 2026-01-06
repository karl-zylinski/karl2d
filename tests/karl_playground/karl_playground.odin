// I add things I often want to test in here while devving.
package karl2d_playground

import k2 "../.."
import "core:fmt"
import "core:mem"

_ :: fmt

tex: k2.Texture

init :: proc() {
	k2.init(1080, 1080, "Karl2D Minimal Program", options = {
		window_mode = .Windowed,
	})

	// Note that we #load the texture: This bakes it into the program's data. WASM has no filesystem
	// so in order to bundle textures with your game, you need to store them somewhere it can fetch
	// them.
	tex = k2.load_texture_from_bytes(#load("../../examples/basics/sixten.jpg"))
}

pos_x: f32
rot: f32

step :: proc() -> bool {
	if !k2.update() {
		return false
	}

	k2.clear(k2.LIGHT_BLUE)

	t := k2.get_time()

	if k2.key_went_down(.F) {
		k2.set_window_mode(.Borderless_Fullscreen)
	}

	if k2.key_went_down(.W) {
		k2.set_window_mode(.Windowed)
	}

	if k2.key_went_down(.R) {
		k2.set_window_mode(.Windowed_Resizable)
	}

	if k2.key_went_down(.Z) {
		k2.set_window_position(0, 0) 
	}

	if k2.key_is_held(.A) {
		pos_x -= k2.get_frame_time() * 400
	}

	if k2.key_is_held(.D) {
		pos_x += k2.get_frame_time() * 400
	}

	if k2.mouse_button_is_held(.Left) {
		rot += k2.get_frame_time() * 400
	}

	k2.draw_texture_ex(tex, {0, 0, f32(tex.width), f32(tex.height)}, {400, 450, 900, 500}, {450, 250}, rot)

	k2.draw_rect({pos_x + 10, 10, 60, 60}, k2.GREEN)
	k2.draw_rect({20, 20, 40, 40}, k2.LIGHT_GREEN)
	k2.draw_circle({120, 40}, 30, k2.DARK_RED)
	k2.draw_circle({120, 40}, 20, k2.RED)

	k2.draw_rect({4, 95, 512, 152}, k2.color_alpha(k2.DARK_GRAY, 192))
	
	k2.draw_text("Hellöpe!", {10, 100}, 48, k2.LIGHT_RED)

	msg1 := fmt.tprintf("Time since start: %.3f s", t)
	msg2 := fmt.tprintf("Last frame time: %.5f s", k2.get_frame_time())
	k2.draw_text(msg1, {10, 148}, 48, k2.ORANGE)
	k2.draw_text(msg2, {10, 196}, 48, k2.LIGHT_PURPLE)

	k2.present()
	free_all(context.temp_allocator)

	return true
}

shutdown :: proc() {
	k2.destroy_texture(tex)
	k2.shutdown()
}

// This is not run by the web version, but it makes this program also work on non-web!
main :: proc() {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	context.allocator = mem.tracking_allocator(&track)

	init()
	for step()  {}
	shutdown()

	if len(track.allocation_map) > 0 {
		fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
		for _, entry in track.allocation_map {
			fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
		}
	}
	mem.tracking_allocator_destroy(&track)
}
