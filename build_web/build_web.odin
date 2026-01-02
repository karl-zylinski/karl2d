// This program builds a Karl2D game as a web version.
//
// Usage:
//    odin run build_web -- directory_name 
//
// For example:
//    odin run build_web -- examples/minimal_web
//
// This program copies the `odin.js` from `<odin>/core/sys/wasm/js/odin.js` to the `bin/web` folder.
// It also copies an `index.html` file to the `bin/web` folder. It also copies a `web_entry.odin`
// file into the `build/web` folder. That's the file which is actually built. It contains some
// wrapper code that calls into your game. The wrapper, and your game, is built using the
// `js_wasm32` target. The resulting `main.wasm` file is also put in the `build/web` folder.
package karl2d_build_web_tool

import "core:fmt"
import "core:path/filepath"
import os "core:os/os2"
import "core:strings"

main :: proc() {
	print_usage: bool

	if len(os.args) < 2 {
		print_usage = true
	}

	debug := false
	opt_string: string
	dir: string

	for a in os.args {
		if a == "-debug" {
			debug = true
		} else if a == "-help" {
			print_usage = true
		} else if a == "-o:speed" {
			opt_string = a
		} else if a == "-o:size" {
			opt_string = a
		} else if strings.has_prefix(a, "-") {
			print_usage = true
		} else {
			dir = a
		}
	}

	if dir == "" {
		print_usage = true
	}

	if print_usage {
		fmt.eprintfln("Usage: 'odin run build_web -- directory_name [-debug] [-o:speed/size]' where `[]` means that it is an optional flag\nExample: 'odin run build_web -- examples/minimal_web'")
		return
	}

	WEB_ENTRY_TEMPLATE :: #load("web_entry_templates/web_entry_template.odin")
	WEB_ENTRY_INDEX :: #load("web_entry_templates/index_template.html")

	dir_handle, dir_handle_err := os.open(dir)
	fmt.ensuref(dir_handle_err == nil, "Failed finding directory %v. Error: %v", dir, dir_handle_err)

	dir_stat, dir_stat_err := os.fstat(dir_handle, context.allocator)
	fmt.ensuref(dir_stat_err == nil, "Failed checking status of directory %v. Error: %v", dir, dir_stat_err)
	fmt.ensuref(dir_stat.type == .Directory, "%v is not a directory!", dir)

	dir_name := dir_stat.name

	bin_dir := filepath.join({dir, "bin"})
	os.make_directory(bin_dir, 0o644)
	bin_web_dir := filepath.join({bin_dir, "web"})
	os.make_directory(bin_web_dir, 0o644)

	build_dir := filepath.join({dir, "build"})
	os.make_directory(build_dir, 0o644)
	build_web_dir := filepath.join({build_dir, "web"})
	os.make_directory(build_web_dir, 0o644)

	entry_odin_file_path := filepath.join({build_web_dir, fmt.tprintf("%v_web_entry.odin", dir_name)})
	write_entry_odin_err := os.write_entire_file(entry_odin_file_path, WEB_ENTRY_TEMPLATE)
	fmt.ensuref(write_entry_odin_err == nil, "Failed writing %v. Error: %v", entry_odin_file_path, write_entry_odin_err)

	entry_html_file_path := filepath.join({bin_web_dir, "index.html"})
	write_entry_html_err := os.write_entire_file(entry_html_file_path, WEB_ENTRY_INDEX)
	fmt.ensuref(write_entry_html_err == nil, "Failed writing %v. Error: %v", entry_html_file_path, write_entry_html_err)

	_, odin_root_stdout, _, odin_root_err := os.process_exec({
		command = { "odin", "root" },
	}, allocator = context.allocator)

	ensure(odin_root_err == nil, "Failed fetching 'odin root' (Odin in PATH needed!)")
	odin_root := string(odin_root_stdout)

	js_runtime_path := filepath.join({odin_root, "core", "sys", "wasm", "js", "odin.js"})
	fmt.ensuref(os.exists(js_runtime_path), "File does not exist: %v -- It is the Odin Javascript runtime that this program needs to copy to the web build output folder!", js_runtime_path)
	os.copy_file(filepath.join({bin_web_dir, "odin.js"}), js_runtime_path)

	wasm_out_path := filepath.join({bin_web_dir, "main.wasm"})

	build_command: [dynamic]string

	append(&build_command, ..[]string{
		"odin",
		"build",
		build_web_dir,
		fmt.tprintf("-out:%v", wasm_out_path),
		"-target:js_wasm32",
		"-vet",
		"-strict-style",
	})

	if debug {
		append(&build_command, "-debug")
	}

	if opt_string != "" {
		append(&build_command, opt_string)
	}

	_, build_std_out, build_std_err, _ := os.process_exec({ command = build_command[:] }, allocator = context.allocator)

	if len(build_std_out) > 0 {
		fmt.println(string(build_std_out))
	}

	if len(build_std_err) > 0 {
		fmt.println(string(build_std_err))
	}
}