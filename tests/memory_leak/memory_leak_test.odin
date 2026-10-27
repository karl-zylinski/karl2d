package karl2d_memory_leak_test

import k2 "../.."
import "core:mem"
import "core:testing"

@(test)
init_and_shutdown_frees_everything :: proc(t: ^testing.T) {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	context.allocator = mem.tracking_allocator(&track)

	k2.init(320, 240, "karl2d memory leak test")

	tex := k2.create_texture(64, 32, .RGBA_8_Norm)
	static_font := k2.load_static_font_from_bytes(k2.DEFAULT_FONT_DATA, 20)
	dynamic_font := k2.load_dynamic_font_from_bytes(k2.DEFAULT_FONT_DATA)

	for _ in 0..<3 {
		k2.update()
		k2.clear(k2.BLACK)
		k2.draw_texture(tex, {10, 10})
		k2.draw_text("Hello", {10, 50}, 20, k2.WHITE)
		k2.draw_text("Hello", {10, 80}, 20, k2.WHITE, static_font)
		k2.draw_text("Hello", {10, 110}, 20, k2.WHITE, dynamic_font)
		k2.present()
	}

	k2.destroy_font(dynamic_font)
	k2.destroy_font(static_font)
	k2.destroy_texture(tex)
	k2.shutdown()

	for _, entry in track.allocation_map {
		testing.expectf(t, false, "%v bytes not freed, allocated at %v", entry.size, entry.location)
	}

	for entry in track.bad_free_array {
		testing.expectf(t, false, "Bad free of %p at %v", entry.memory, entry.location)
	}

	mem.tracking_allocator_destroy(&track)
}
