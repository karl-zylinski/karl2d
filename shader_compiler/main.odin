#+build !js
package karl2d_shader_compiler

import "core:fmt"
import "core:os"
import "core:strings"

load_include_from_disk :: proc(filename: string) -> (data: []u8, ok: bool) {
	file_data, err := os.read_entire_file_from_path(filename, context.allocator)
	return file_data, err == nil
}

compile_from_file :: proc(
	filename: string,
	options := Compile_Options {},
	allocator := context.allocator,
	temp_allocator := context.temp_allocator,
	error_allocator := context.temp_allocator,
) -> (Compiled_Shader, Compile_Error, bool) {
	source, source_err := os.read_entire_file_from_path(filename, temp_allocator)

	if source_err != nil {
		return nil, { message = "Cannot read the file", file = filename }, false
	}

	return compile(source, filename, load_include_from_disk, options, allocator, temp_allocator, error_allocator)
}

main :: proc() {
	input: string
	output: string
	dump_dir: string
	targets: bit_set[Target]
	no_optimization := false

	for arg in os.args[1:] {
		if strings.has_prefix(arg, "-out:") {
			output = arg[5:]
		} else if strings.has_prefix(arg, "-dump:") {
			dump_dir = arg[6:]
		} else if arg == "-glsl" {
			targets += { .GLSL_330 }
		} else if arg == "-glsl-es" {
			targets += { .GLSL_ES_300 }
		} else if arg == "-spirv" {
			targets += { .SPIRV }
		} else if arg == "-dxbc" {
			targets += { .DXBC }
		} else if arg == "-no-opt" {
			no_optimization = true
		} else if strings.has_prefix(arg, "-") {
			fmt.eprintfln("Unknown option %s", arg)
			os.exit(1)
		} else {
			input = arg
		}
	}

	if input == "" {
		fmt.eprintln("Usage: shader_compiler shader.glsl [-out:shader.k2shader] [-dump:folder] [-glsl] [-glsl-es] [-spirv] [-dxbc] [-no-opt]")
		fmt.eprintln("All targets are compiled when none is chosen.")
		os.exit(1)
	}

	options := Compile_Options {
		targets = targets,
		no_optimization = no_optimization,
	}

	compiled, error, ok := compile_from_file(input, options)

	if !ok {
		fmt.eprintfln("%s(%d): %s", error.file, error.line, error.message)
		os.exit(1)
	}

	if output == "" {
		output = strings.concatenate({ input, ".k2shader" })
	}

	if os.write_entire_file(output, compiled) != nil {
		fmt.eprintfln("Cannot write %s", output)
		os.exit(1)
	}

	if dump_dir == "" {
		return
	}

	names := [Target][2]string {
		.GLSL_330 = { "vertex.glsl", "fragment.glsl" },
		.GLSL_ES_300 = { "vertex.es.glsl", "fragment.es.glsl" },
		.SPIRV = { "vertex.spv", "fragment.spv" },
		.DXBC = { "vertex.dxbc", "fragment.dxbc" },
	}

	os.make_directory(dump_dir)
	view, _ := compiled_shader_view(compiled)

	for target in Target {
		if target not_in view.targets {
			continue
		}

		vertex_err := os.write_entire_file(fmt.tprintf("%s/%s", dump_dir, names[target][0]), view.code[target].vertex)
		fragment_err := os.write_entire_file(fmt.tprintf("%s/%s", dump_dir, names[target][1]), view.code[target].fragment)

		if vertex_err != nil || fragment_err != nil {
			fmt.eprintfln("Cannot write to %s", dump_dir)
			os.exit(1)
		}
	}
}
