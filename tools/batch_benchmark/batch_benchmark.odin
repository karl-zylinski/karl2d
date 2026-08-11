// Measures what it costs to draw when the batch gets broken up. It runs a set of scenarios that
// break the batch in different ways, which is what this benchmark is about: a batch break means a
// new draw call, and it used to mean a complete pipeline setup in the render backend.
//
// Two numbers are reported per scenario:
//
// - `cpu`: time spent issuing the draws and flushing them, without `present`. This is what the
//   game's own thread pays.
// - `frame`: the whole frame, `present` included.
//
// Read them together. `cpu` alone is misleading on GL, where the driver takes the commands and
// does the work on its own thread: a cheap-looking `cpu` can hide a pile of queued-up work that
// only shows up in `frame`. And `frame` alone is misleading whenever the frame fits inside the
// vsync interval, since both backends present with vsync on: everything under ~16 ms reads as
// ~16 ms. A scenario is only slow if `frame` is well above the vsync interval.
//
// Run it on each backend you care about:
//
//     odin run tools/batch_benchmark -o:speed
//     odin run tools/batch_benchmark -o:speed -define:KARL2D_RENDER_BACKEND=gl
package karl2d_batch_benchmark

import k2 "../.."
import "core:fmt"
import "core:time"

QUADS :: 2000
WARMUP_FRAMES :: 15
MEASURE_FRAMES :: 45

TEXTURE_SIZE :: 64
QUADS_PER_ROW :: 100
QUAD_SPACING_X :: 12
QUAD_SPACING_Y :: 30

WINDOW_WIDTH :: 1280
WINDOW_HEIGHT :: 720

Scenario_Kind :: enum {
	Single_Texture,
	Switch_Texture_Every_10,
	Switch_Texture_Every_Quad,
	Interleaved_Text,
	Camera_Switch_Every_10,
}

SCENARIO_NAMES :: [Scenario_Kind]string {
	.Single_Texture            = "single texture (1 batch break)",
	.Switch_Texture_Every_10   = "texture switch every 10 quads (200 breaks)",
	.Switch_Texture_Every_Quad = "texture switch every quad (2000 breaks)",
	.Interleaved_Text          = "texture + text interleaved (400 breaks)",
	.Camera_Switch_Every_10    = "camera switch every 10 quads (200 breaks)",
}

main :: proc() {
	k2.init(WINDOW_WIDTH, WINDOW_HEIGHT, "Karl2D batch benchmark")

	// Two solid-color textures. Which one a quad uses is what breaks the batch in the texture
	// switching scenarios.
	pixels_red: [TEXTURE_SIZE*TEXTURE_SIZE*4]u8
	pixels_green: [TEXTURE_SIZE*TEXTURE_SIZE*4]u8

	for i in 0..<TEXTURE_SIZE*TEXTURE_SIZE {
		pixels_red[i*4 + 0] = 255
		pixels_red[i*4 + 3] = 255
		pixels_green[i*4 + 1] = 255
		pixels_green[i*4 + 3] = 255
	}

	ts := TEXTURE_SIZE
	tex_red := k2.load_texture_from_bytes_raw(pixels_red[:], ts, ts, .RGBA_8_Norm)
	tex_green := k2.load_texture_from_bytes_raw(pixels_green[:], ts, ts, .RGBA_8_Norm)

	cpu_results: [Scenario_Kind]f64
	frame_results: [Scenario_Kind]f64

	kind := Scenario_Kind.Single_Texture
	done := false
	frame := 0
	cpu_total: f64
	frame_total: f64
	frame_start := time.tick_now()

	for k2.update() && !done {
		k2.clear(k2.BLACK)

		start := time.tick_now()
		run_scenario(kind, tex_red, tex_green)

		// Everything recorded above has to reach the backend before we stop the clock.
		k2.draw_current_batch()
		cpu := time.duration_milliseconds(time.tick_since(start))

		k2.present()

		// Measured frame start to frame start, so it covers present and whatever the driver was
		// still busy with.
		now := time.tick_now()
		frame_time := time.duration_milliseconds(time.tick_diff(frame_start, now))
		frame_start = now
		frame += 1

		if frame > WARMUP_FRAMES {
			cpu_total += cpu
			frame_total += frame_time
		}

		if frame == WARMUP_FRAMES + MEASURE_FRAMES {
			cpu_results[kind] = cpu_total / MEASURE_FRAMES
			frame_results[kind] = frame_total / MEASURE_FRAMES
			frame = 0
			cpu_total = 0
			frame_total = 0

			if kind == max(Scenario_Kind) {
				done = true
			} else {
				kind += Scenario_Kind(1)
			}
		}
	}

	k2.shutdown()

	fmt.printfln("Karl2D batch benchmark: %v backend, %v quads, average of %v frames",
		k2.RENDER_BACKEND_NAME, QUADS, MEASURE_FRAMES)
	fmt.println("'cpu' is draw issuing plus the flush. 'frame' is everything, present included.")
	fmt.println("Both backends present with vsync on, so anything under ~16 ms of frame is idle.")
	fmt.println()

	names := SCENARIO_NAMES

	for name, k in names {
		fmt.printfln("%-44s cpu %7.3f ms   frame %8.3f ms", name, cpu_results[k], frame_results[k])
	}
}

run_scenario :: proc(kind: Scenario_Kind, tex_red: k2.Texture, tex_green: k2.Texture) {
	switch kind {
	case .Single_Texture:
		for i in 0..<QUADS {
			k2.draw_texture(tex_red, quad_position(i))
		}

	case .Switch_Texture_Every_10:
		for i in 0..<QUADS {
			tex := (i/10) % 2 == 0 ? tex_red : tex_green
			k2.draw_texture(tex, quad_position(i))
		}

	case .Switch_Texture_Every_Quad:
		for i in 0..<QUADS {
			tex := i % 2 == 0 ? tex_red : tex_green
			k2.draw_texture(tex, quad_position(i))
		}

	case .Interleaved_Text:
		// A quarter of the quads are followed by a bit of text. Text uses the font atlas
		// texture, so each switch between the two breaks the batch twice.
		for i in 0..<QUADS {
			k2.draw_texture(tex_red, quad_position(i))

			if i % 10 == 0 {
				k2.draw_text("hi", quad_position(i), 16, k2.WHITE)
			}
		}

	case .Camera_Switch_Every_10:
		// Same texture throughout, so the camera changes are the only thing breaking batches.
		cam_a := k2.Camera { zoom = 1 }
		cam_b := k2.Camera { zoom = 1.0001 }

		for i in 0..<QUADS {
			k2.set_camera((i/10) % 2 == 0 ? cam_a : cam_b)
			k2.draw_texture(tex_red, quad_position(i))
		}

		k2.set_camera(nil)
	}
}

quad_position :: proc(i: int) -> k2.Vec2 {
	return {
		f32(i % QUADS_PER_ROW) * QUAD_SPACING_X,
		f32(i / QUADS_PER_ROW) * QUAD_SPACING_Y,
	}
}
