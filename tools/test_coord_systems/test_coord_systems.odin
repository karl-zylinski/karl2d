// Builds `tools/coord_test` in both coordinate-system configurations and checks that they produce
// the same output.
//
// `tools/coord_test` positions everything it draws in screen space (Y from the top of the surface)
// and reports the resulting geometry in normalized device coordinates. So if Y down and Y up are
// both implemented correctly, they describe the same picture and the output is byte-identical.
//
// Run with: odin run tools/test_coord_systems
#+feature dynamic-literals

package karl2d_test_coord_systems

import "core:fmt"
import "core:os"
import "core:strings"

Config :: struct {
	name: string,
	defines: []string,
}

CONFIGS := []Config {
	{ name = "y-down (default)", defines = {} },
	{ name = "y-up", defines = { "-define:KARL2D_Y_UP=true" } },
}

main :: proc() {
	outputs := make([]string, len(CONFIGS))
	failed := false

	for cfg, cfg_idx in CONFIGS {
		fmt.printfln("=== %v ===", cfg.name)

		out, ok := run_config(cfg, cfg_idx)

		if !ok {
			failed = true
			continue
		}

		outputs[cfg_idx] = out
	}

	if failed {
		os.exit(1)
	}

	// Every configuration reports where things ended up on screen, so they must all agree. Anything
	// that identifies the configuration goes to stderr instead, so stdout can be compared as-is.
	reference := outputs[0]

	for cfg, cfg_idx in CONFIGS[1:] {
		got := outputs[cfg_idx + 1]

		if got == reference {
			continue
		}

		fmt.eprintfln("MISMATCH: '%v' does not draw the same picture as '%v'.", cfg.name, CONFIGS[0].name)
		print_diff(reference, got, CONFIGS[0].name, cfg.name)
		failed = true
	}

	if failed {
		os.exit(1)
	}

	fmt.printfln("All %v coordinate-system configurations agree.", len(CONFIGS))
}

run_config :: proc(cfg: Config, cfg_idx: int) -> (string, bool) {
	// Absolute, so that the exec below finds it regardless of how the process resolves relative
	// paths, and with the platform's executable suffix.
	suffix := ".exe" if ODIN_OS == .Windows else ""
	cwd, _ := os.get_working_directory(context.temp_allocator)
	exe := fmt.tprintf("%v/bin/coord_test_%v%v", cwd, cfg_idx, suffix)

	build := [dynamic]string {
		"odin", "build", "tools/coord_test",
		"-no-threaded-checker", "-vet", "-strict-style", "-vet-tabs",
		"-define:KARL2D_RENDER_BACKEND=nil",
		fmt.tprintf("-out:%v", exe),
	}

	append(&build, ..cfg.defines)

	if !run(build[:], "build") {
		return "", false
	}

	command := [dynamic]string { exe }

	state, out, err, exec_err := os.process_exec({ command = command[:] }, context.allocator)

	if exec_err != nil {
		fmt.eprintfln("Failed running %v: %v", exe, exec_err)
		return "", false
	}

	if len(err) > 0 {
		fmt.eprint(string(err))
	}

	if state.exit_code != 0 {
		fmt.eprintfln("%v exited with %v", exe, state.exit_code)
		return "", false
	}

	fmt.print(string(out))
	return string(out), true
}

run :: proc(command: []string, what: string) -> bool {
	state, out, err, exec_err := os.process_exec({ command = command }, context.allocator)

	if exec_err != nil {
		fmt.eprintfln("Failed to %v: %v", what, exec_err)
		return false
	}

	if len(out) > 0 {
		fmt.eprint(string(out))
	}

	if len(err) > 0 {
		fmt.eprint(string(err))
	}

	if state.exit_code != 0 {
		fmt.eprintfln("Failed to %v: exit code %v", what, state.exit_code)
		return false
	}

	return true
}

print_diff :: proc(want: string, got: string, want_name: string, got_name: string) {
	want_lines := strings.split_lines(want, context.allocator)
	got_lines := strings.split_lines(got, context.allocator)

	for i in 0..<max(len(want_lines), len(got_lines)) {
		w := want_lines[i] if i < len(want_lines) else ""
		g := got_lines[i] if i < len(got_lines) else ""

		if w == g {
			continue
		}

		fmt.eprintfln("  %v: %v", want_name, w)
		fmt.eprintfln("  %v: %v", got_name, g)
	}
}
