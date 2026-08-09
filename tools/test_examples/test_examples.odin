// Goes through all the examples and builds them. This script is used by the GitHub CI.
#+feature dynamic-literals

package karl2d_test_examples

import os "core:os"
import "core:fmt"

main :: proc() {
	// Any arguments are passed straight through to the compiler, so the CI can run the whole sweep
	// again with, for example, -define:KARL2D_Y_UP=true. Pass `-skip-web` to leave out the web
	// builds, which is worth doing for those extra sweeps: they are slow and the coordinate system
	// is not web-specific.
	skip_web := false
	extra: [dynamic]string

	for arg in os.args[1:] {
		if arg == "-skip-web" {
			skip_web = true
			continue
		}

		append(&extra, arg)
	}

	examples, examples_err := os.read_all_directory_by_path("examples", context.allocator)

	fmt.assertf(examples_err == nil, "Failed opening examples directory. Error: %v", examples_err)

	// These examples don't have web build
	no_web_list := [?]string{
		"minimal_hello_world",
		"custom_frame_update",
		"events",
		"premultiplied_alpha",
		"raylib_ports",
		"scaling_auto_window_resize",
		"ui",
		"scraps",
	}

	// These examples are only for web -- Running a pure "check" on them will fail
	no_check_list := [?]string {
		"minimal_hello_world_web",
		"raylib_ports",
		"scraps",
	}

	no_web: map[string]struct{}

	for n in no_web_list {
		no_web[n] = {}
	}

	no_check: map[string]struct{}

	for n in no_check_list {
		no_check[n] = {}
	}

	for e in examples {
		if e.type != .Directory {
			continue
		}

		debug_params := make([dynamic]string, context.temp_allocator)
		append(&debug_params, "-debug")
		append(&debug_params, ..extra[:])

		if e.name not_in no_check {
			check(e.name, e.fullpath, extra[:])
			check(e.name, e.fullpath, debug_params[:])
		}

		if !skip_web && e.name not_in no_web {
			build_web(e.name, e.fullpath, extra[:])
			build_web(e.name, e.fullpath, debug_params[:])
		}
	}
}

check :: proc(name: string, fullpath: string, extra_params: []string) {
	if len(extra_params) > 0 {
		fmt.printfln("examples/%v: Checking. Extra options: %v", name, extra_params)
	} else {
		fmt.printfln("examples/%v: Checking", name)
	}

	build_command := [dynamic]string {
		"odin",
		"check",
		fullpath,
		"-no-threaded-checker",
		"-vet",
		"-strict-style",
		"-vet-tabs",
	}

	append(&build_command, ..extra_params)
	
	build_status, build_std_out, build_std_err, _ := os.process_exec({ command = build_command[:] }, allocator = context.allocator)

	if len(build_std_out) > 0 {
		fmt.eprint(string(build_std_out))
	}

	if len(build_std_err) > 0 {
		fmt.eprint(string(build_std_err))
	}

	if build_status.exit_code != 0 {
		os.exit(build_status.exit_code)
	}
}

build_web :: proc(name: string, fullpath: string, extra_params: []string) {
	if len(extra_params) > 0 {
		fmt.printfln("examples/%v: Web build. Extra options: %v", name, extra_params)
	} else {
		fmt.printfln("examples/%v: Web build", name)
	}

	build_command := [dynamic]string {
		"odin",
		"run",
		"build_web",
		"-no-threaded-checker",
		"-vet",
		"-strict-style",
		"-vet-tabs",
		"--",
		fullpath,
		"-no-threaded-checker",
		"-vet",
		"-strict-style",
		"-vet-tabs",
	}

	append(&build_command, ..extra_params)
	
	build_status, build_std_out, build_std_err, _ := os.process_exec({ command = build_command[:] }, allocator = context.allocator)

	if len(build_std_out) > 0 {
		fmt.eprint(string(build_std_out))
	}

	if len(build_std_err) > 0 {
		fmt.eprint(string(build_std_err))
	}

	if build_status.exit_code != 0 {
		os.exit(build_status.exit_code)
	}
}