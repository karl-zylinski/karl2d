// Goes through all the examples and builds them. This script is used by the GitHub CI.
#+feature dynamic-literals

package karl2d_test_examples

import os "core:os/os2"
import "core:log"

no_web: map[string]struct{}
no_check: map[string]struct{}

main :: proc() {
	context.logger = log.create_console_logger()
	examples, examples_err := os.read_all_directory_by_path("examples", context.allocator)

	log.assertf(examples_err == nil, "Failed opening examples directory. Error: %v", examples_err)
	
	// These examples don't have web build
	no_web_list := [?]string{
		"minimal_hello_world",
		"custom_frame_update",
		"events",
		"premultiplied_alpha",
		"raylib_ports",
		"scaling_auto_window_resize",
		"ui",
	}

	// These examples are only for web -- Running a pure "check" on them will fail
	no_check_list := [?]string {
		"minimal_hello_world_web",
		"raylib_ports",
	}

	for n in no_web_list {
		no_web[n] = {}
	}

	for n in no_check_list {
		no_check[n] = {}
	}

	for e in examples {
		if e.type != .Directory {
			continue
		}

		if e.name not_in no_check {
			check(e.name, e.fullpath, {})
			check(e.name, e.fullpath, {"-debug"})
		}

		if e.name not_in no_web {
			build_web(e.name, e.fullpath, {})
			build_web(e.name, e.fullpath, {"-debug"})
		}
	}
}

check :: proc(name: string, fullpath: string, extra_params: []string) {
	if len(extra_params) > 0 {
		log.infof("examples/%v: Checking %v", name, extra_params)
	} else {
		log.infof("examples/%v: Checking", name)
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
		log.error(string(build_std_out))
	}

	if len(build_std_err) > 0 {
		log.error(string(build_std_err))
	}

	if build_status.exit_code != 0 {
		os.exit(build_status.exit_code)
	}
}

build_web :: proc(name: string, fullpath: string, extra_params: []string) {
	if len(extra_params) > 0 {
		log.infof("examples/%v: Web build %v", name, extra_params)
	} else {
		log.infof("examples/%v: Web build", name)
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
		log.error(string(build_std_out))
	}

	if len(build_std_err) > 0 {
		log.error(string(build_std_err))
	}

	if build_status.exit_code != 0 {
		os.exit(build_status.exit_code)
	}
}