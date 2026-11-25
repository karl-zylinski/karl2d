// Goes through all the examples and checks that they compile, both with and without `-debug`. Pass
// `web` as argument to check them for the web target instead of the native one:
//
//    odin run tools/test_examples -- web
//
// This script is used by the GitHub CI.
#+feature dynamic-literals

package karl2d_test_examples

import os "core:os"
import "core:fmt"

main :: proc() {
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

	web := len(os.args) > 1 && os.args[1] == "web"

	for e in examples {
		if e.type != .Directory {
			continue
		}

		if web {
			if e.name not_in no_web {
				check(e.name, e.fullpath, {"-target:js_wasm32", "-no-entry-point"})
				check(e.name, e.fullpath, {"-target:js_wasm32", "-no-entry-point", "-debug"})
			}
		} else {
			if e.name not_in no_check {
				check(e.name, e.fullpath, {})
				check(e.name, e.fullpath, {"-debug"})
			}
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
