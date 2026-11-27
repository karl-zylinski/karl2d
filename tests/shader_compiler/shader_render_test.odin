package karl2d_shader_render_test

import k2 "../.."
import sc "../../shader_compiler"
import "base:runtime"
import "core:dynlib"
import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"

SIZE :: 256

compare :: proc(dir_a: string, dir_b: string) {
	files, files_err := os.read_all_directory_by_path(dir_a, context.allocator)

	if files_err != nil {
		fmt.eprintfln("Cannot list %s", dir_a)
		os.exit(1)
	}

	slice.sort_by(files, proc(a, b: os.File_Info) -> bool { return a.name < b.name })
	worst := 0

	for f in files {
		if !strings.has_suffix(f.name, ".rgba") {
			continue
		}

		a, a_err := os.read_entire_file_from_path(f.fullpath, context.allocator)
		b, b_err := os.read_entire_file_from_path(fmt.tprintf("%s/%s", dir_b, f.name), context.allocator)

		if a_err != nil || b_err != nil || len(a) != len(b) {
			fmt.printfln("%-32s MISSING", f.name)
			worst = 255
			continue
		}

		max_diff := 0
		different := 0

		for i in 0..<len(a) {
			d := abs(int(a[i]) - int(b[i]))

			if d > 2 {
				different += 1
			}

			max_diff = max(max_diff, d)
		}

		worst = max(worst, max_diff)
		fmt.printfln("%-32s max diff %3d, values off by more than 2: %d", f.name, max_diff, different)
	}

	fmt.printfln("Worst difference: %d", worst)
}

check_errors :: proc() {
	read_file :: proc(path: string, user_data: rawptr, allocator: runtime.Allocator) -> ([]u8, bool) {
		data, err := os.read_entire_file_from_path(path, allocator)
		return data, err == nil
	}

	error_dir := #directory + "errors"
	files, files_err := os.read_all_directory_by_path(error_dir, context.allocator)

	if files_err != nil {
		fmt.eprintfln("Cannot list %s", error_dir)
		os.exit(1)
	}

	slice.sort_by(files, proc(a, b: os.File_Info) -> bool { return a.name < b.name })
	accepted := 0

	for f in files {
		source, source_err := os.read_entire_file_from_path(f.fullpath, context.allocator)

		if source_err != nil {
			continue
		}

		options := sc.Compile_Options { targets = ~bit_set[sc.Target]{}, read_file = read_file }
		_, message, ok := sc.compile(source, f.name, options)

		if ok {
			fmt.printfln("%-44s WAS ACCEPTED", f.name)
			accepted += 1
		} else {
			fmt.println(message)
		}
	}

	fmt.printfln("%d error shaders, %d wrongly accepted", len(files), accepted)

	if accepted > 0 {
		os.exit(1)
	}
}

capture :: proc(capture_path: string, shader_path: string) {
	library, library_ok := dynlib.load_library("C:/Program Files/RenderDoc/renderdoc.dll")

	if !library_ok {
		fmt.eprintln("Cannot load renderdoc.dll")
		os.exit(1)
	}

	get_api_address, get_api_ok := dynlib.symbol_address(library, "RENDERDOC_GetAPI")

	if !get_api_ok {
		fmt.eprintln("Cannot find RENDERDOC_GetAPI")
		os.exit(1)
	}

	api: ^[32]rawptr
	get_api := cast(proc "c" (version: i32, out: ^^[32]rawptr) -> i32)get_api_address

	if get_api(10102, &api) != 1 {
		fmt.eprintln("RENDERDOC_GetAPI failed")
		os.exit(1)
	}

	set_capture_path := cast(proc "c" (path: cstring))api[11]
	start_capture := cast(proc "c" (device: rawptr, window: rawptr))api[19]
	end_capture := cast(proc "c" (device: rawptr, window: rawptr) -> u32)api[21]
	set_capture_path(strings.clone_to_cstring(capture_path))
	k2.init(SIZE, SIZE, "Shader capture", { disable_auto_scale_hint = true, disable_vsync = true })
	texels: [4 * 4 * 4]u8

	for &t in texels {
		t = 200
	}

	tex := k2.load_texture_from_bytes_raw(texels[:], 4, 4, .RGBA_8_Norm)
	shd, shd_ok := k2.load_shader_from_file(shader_path)

	if !shd_ok {
		fmt.eprintln("Cannot load the shader")
		os.exit(1)
	}

	for frame in 0..<3 {
		k2.update()

		if frame == 1 {
			start_capture(nil, nil)
		}

		k2.clear(k2.BLACK)
		k2.set_shader(shd)
		k2.draw_texture_ex(tex, { 0, 0, 4, 4 }, { 0, 0, SIZE, SIZE }, {}, 0)
		k2.present()

		if frame == 1 {
			fmt.println("capture result:", end_capture(nil, nil))
		}
	}

	k2.shutdown()
}

main :: proc() {
	if len(os.args) == 4 && os.args[1] == "capture" {
		capture(os.args[2], os.args[3])
		return
	}

	if len(os.args) == 4 && os.args[1] == "compare" {
		compare(os.args[2], os.args[3])
		return
	}

	if len(os.args) == 2 && os.args[1] == "errors" {
		check_errors()
		return
	}

	if len(os.args) != 2 {
		fmt.eprintln("Usage: shader_render_test output_folder")
		fmt.eprintln("       shader_render_test compare folder_a folder_b")
		os.exit(1)
	}

	out_dir := os.args[1]
	os.make_directory_all(out_dir)
	shader_dir := #directory + "shaders"
	files, files_err := os.read_all_directory_by_path(shader_dir, context.allocator)

	if files_err != nil {
		fmt.eprintfln("Cannot list %s", shader_dir)
		os.exit(1)
	}

	slice.sort_by(files, proc(a, b: os.File_Info) -> bool { return a.name < b.name })
	k2.init(SIZE, SIZE, "Shader render test", { disable_auto_scale_hint = true, disable_vsync = true })
	texels: [8 * 8 * 4]u8

	for y in 0..<8 {
		for x in 0..<8 {
			i := (y * 8 + x) * 4
			texels[i + 0] = u8(x * 36)
			texels[i + 1] = u8(y * 36)
			texels[i + 2] = (x + y) % 2 == 0 ? 255 : 32
			texels[i + 3] = 255
		}
	}

	tex := k2.load_texture_from_bytes_raw(texels[:], 8, 8, .RGBA_8_Norm)
	k2.set_texture_sampler(tex, k2.Texture_Sampler { scale_up_filter = .Point, scale_down_filter = .Point })
	pixels := make([]u8, SIZE * SIZE * 4)
	failures := 0
	count := 0

	for f in files {
		if !strings.has_suffix(f.name, ".glsl") {
			continue
		}

		if strings.has_suffix(f.name, ".inc.glsl") {
			continue
		}

		k2.update()
		count += 1
		shd, shd_ok := k2.load_shader_from_file(f.fullpath)

		if !shd_ok {
			fmt.printfln("%-32s FAILED TO LOAD", f.name)
			failures += 1
			continue
		}

		k2.clear(k2.BLACK)
		k2.set_shader(shd)

		if loc, loc_ok := shd.constant_lookup["time"]; loc_ok {
			k2.set_shader_constant(shd, loc, f32(1.25))
		}

		if loc, loc_ok := shd.constant_lookup["resolution"]; loc_ok {
			k2.set_shader_constant(shd, loc, k2.Vec2 { SIZE, SIZE })
		}

		k2.draw_texture_ex(tex, { 0, 0, 8, 8 }, { 0, 0, SIZE, SIZE }, {}, 0)

		if !k2.read_backbuffer(pixels) {
			fmt.eprintln("Cannot read the backbuffer")
			os.exit(1)
		}

		k2.present()
		k2.set_shader(nil)
		k2.destroy_shader(shd)
		name := strings.trim_suffix(f.name, ".glsl")

		if os.write_entire_file(fmt.tprintf("%s/%s.rgba", out_dir, name), pixels) != nil {
			fmt.eprintfln("Cannot write to %s", out_dir)
			os.exit(1)
		}

		if !strings.has_prefix(f.name, "check_") {
			fmt.printfln("%-32s rendered", f.name)
			continue
		}

		bad := 0

		for i := 0; i < len(pixels); i += 4 {
			if pixels[i] != 0 || pixels[i + 1] != 255 || pixels[i + 2] != 0 {
				bad += 1
			}
		}

		if bad == 0 {
			fmt.printfln("%-32s ok", f.name)
		} else {
			fmt.printfln("%-32s %d PIXELS FAILED", f.name, bad)
			failures += 1
		}
	}

	k2.shutdown()
	fmt.printfln("%d shaders, %d failures", count, failures)

	if failures > 0 {
		os.exit(1)
	}
}
