#+build !js
package karl2d_shader_compiler

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:strings"

read_file_from_disk :: proc(path: string, user_data: rawptr, allocator: runtime.Allocator) -> (data: []u8, ok: bool) {
	file_data, err := os.read_entire_file_from_path(path, allocator)
	return file_data, err == nil
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

	if targets == {} {
		targets = ~bit_set[Target]{}
	}

	source, source_err := os.read_entire_file_from_path(input, context.allocator)

	if source_err != nil {
		fmt.eprintfln("Cannot read %s", input)
		os.exit(1)
	}

	options := Compile_Options {
		targets = targets,
		no_optimization = no_optimization,
		read_file = read_file_from_disk,
	}

	compiled, error, ok := compile(source, input, options)

	if !ok {
		fmt.eprintln(error)
		os.exit(1)
	}

	if output == "" {
		output = strings.concatenate({ input, ".k2shader" })
	}

	if os.write_entire_file(output, compiled.bytes) != nil {
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

	for target in Target {
		if target not_in compiled.targets {
			continue
		}

		vertex_err := os.write_entire_file(fmt.tprintf("%s/%s", dump_dir, names[target][0]), compiled.code[target].vertex)
		fragment_err := os.write_entire_file(fmt.tprintf("%s/%s", dump_dir, names[target][1]), compiled.code[target].fragment)

		if vertex_err != nil || fragment_err != nil {
			fmt.eprintfln("Cannot write to %s", dump_dir)
			os.exit(1)
		}
	}
}
