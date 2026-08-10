// Measures the CPU cost of issuing draws and flushing them to the render backend. It runs a set of
// scenarios that break the batch in different ways, which is what this benchmark is about: a batch
// break used to mean a complete pipeline setup in the render backend.
//
// Only the draw-issuing region is timed, `present` is left out. That keeps vsync out of the
// numbers, since the D3D11 backend presents with a sync interval of 1.
//
// Run it on each backend you care about:
//
//     odin run tools/batch_benchmark -o:speed
//     odin run tools/batch_benchmark -o:speed -define:KARL2D_RENDER_BACKEND=gl
//
// Note that GL numbers under-report the real cost: GL drivers hand most of the work to a driver
// thread, so the time shows up outside the timed region.
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

Scenario :: struct {
	kind: Scenario_Kind,
	name: string,
}

SCENARIOS :: [Scenario_Kind]Scenario {
	.Single_Texture            = { .Single_Texture,            "single texture (1 batch break)" },
	.Switch_Texture_Every_10   = { .Switch_Texture_Every_10,   "texture switch every 10 quads (200 breaks)" },
	.Switch_Texture_Every_Quad = { .Switch_Texture_Every_Quad, "texture switch every quad (2000 breaks)" },
	.Interleaved_Text          = { .Interleaved_Text,          "texture + text interleaved (400 breaks)" },
	.Camera_Switch_Every_10    = { .Camera_Switch_Every_10,    "camera switch every 10 quads (200 breaks)" },
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

	tex_red := k2.load_texture_from_bytes_raw(pixels_red[:], TEXTURE_SIZE, TEXTURE_SIZE, .RGBA_8_Norm)
	tex_green := k2.load_texture_from_bytes_raw(pixels_green[:], TEXTURE_SIZE, TEXTURE_SIZE, .RGBA_8_Norm)

	scenarios := SCENARIOS
	results: [Scenario_Kind]f64

	kind := Scenario_Kind.Single_Texture
	done := false
	frame := 0
	total: f64

	for k2.update() && !done {
		k2.clear(k2.BLACK)

		start := time.tick_now()
		run_scenario(kind, tex_red, tex_green)

		// Everything recorded above has to reach the backend before we stop the clock.
		k2.draw_current_batch()
		elapsed := time.duration_milliseconds(time.tick_since(start))

		k2.present()
		frame += 1

		if frame > WARMUP_FRAMES {
			total += elapsed
		}

		if frame == WARMUP_FRAMES + MEASURE_FRAMES {
			results[kind] = total / MEASURE_FRAMES
			frame = 0
			total = 0

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
	fmt.println("Timings cover draw issuing plus the flush, but not present.")
	fmt.println()

	for s in scenarios {
		fmt.printfln("%-44s %.3f ms", s.name, results[s.kind])
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
