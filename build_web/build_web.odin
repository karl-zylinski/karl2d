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
import os "core:os"
import "core:strings"

main :: proc() {
	print_usage: bool

	if len(os.args) < 2 {
		print_usage = true
	}

	dir: string
	compiler_params: [dynamic]string

	for a in os.args {
		if a == "-help" || a == "--help" {
			print_usage = true
		} else if strings.has_prefix(a, "-") {
			append(&compiler_params, a)
		} else {
			dir = a
		}
	}

	if dir == "" {
		print_usage = true
	}

	if print_usage {
		fmt.eprintfln("Usage: 'odin run build_web -- directory_name -extra -parameters' Any extra parameter that start with a dash will be passed on to Odin compiler.\nExample: 'odin run build_web -- examples/minimal_web -debug'")
		return
	}

	WEB_ENTRY_TEMPLATE :: #load("web_entry_templates/web_entry_template.odin")
	WEB_ENTRY_INDEX :: #load("web_entry_templates/index_template.html")
	AUDIO_JS :: #load("../audio_backend_web_audio.js")
	AUDIO_PROCESSOR_JS :: #load("../audio_backend_web_audio_processor.js")

	dir_handle, dir_handle_err := os.open(dir)
	fmt.ensuref(dir_handle_err == nil, "Failed finding directory %v. Error: %v", dir, dir_handle_err)

	dir_stat, dir_stat_err := os.fstat(dir_handle, context.allocator)
	fmt.ensuref(dir_stat_err == nil, "Failed checking status of directory %v. Error: %v", dir, dir_stat_err)
	fmt.ensuref(dir_stat.type == .Directory, "%v is not a directory!", dir)

	dir_name := dir_stat.name
	
	path_join :: proc(parts: []string) -> string {
		p, err := os.join_path(parts, allocator = context.allocator)
		fmt.ensuref(err == nil, "Failed joining path: %v", err)
		return p
	}

	bin_dir := path_join({dir, "bin"})
	os.make_directory(bin_dir, os.perm_number(0o755))
	bin_web_dir := path_join({bin_dir, "web"})
	os.make_directory(bin_web_dir, os.perm_number(0o755))

	build_dir := path_join({dir, "build"})
	os.make_directory(build_dir, os.perm_number(0o755))
	build_web_dir := path_join({build_dir, "web"})
	os.make_directory(build_web_dir, os.perm_number(0o755))

	entry_odin_file_path := path_join({build_web_dir, fmt.tprintf("%v_web_entry.odin", dir_name)})
	write_entry_odin_err := os.write_entire_file(entry_odin_file_path, WEB_ENTRY_TEMPLATE)
	fmt.ensuref(write_entry_odin_err == nil, "Failed writing %v. Error: %v", entry_odin_file_path, write_entry_odin_err)

	entry_html_file_path := path_join({bin_web_dir, "index.html"})
	write_entry_html_err := os.write_entire_file(entry_html_file_path, WEB_ENTRY_INDEX)
	fmt.ensuref(write_entry_html_err == nil, "Failed writing %v. Error: %v", entry_html_file_path, write_entry_html_err)

	_, odin_root_stdout, _, odin_root_err := os.process_exec({
		command = { "odin", "root" },
	}, allocator = context.allocator)

	ensure(odin_root_err == nil, "Failed fetching 'odin root' (Odin in PATH needed!)")
	odin_root := string(odin_root_stdout)

	js_runtime_path := path_join({odin_root, "core", "sys", "wasm", "js", "odin.js"})
	fmt.ensuref(os.exists(js_runtime_path), "File does not exist: %v -- It is the Odin Javascript runtime that this program needs to copy to the web build output folder!", js_runtime_path)
	os.copy_file(path_join({bin_web_dir, "odin.js"}), js_runtime_path)

	write_audio_js_err := os.write_entire_file(path_join({bin_web_dir, "audio_backend_web_audio.js"}), AUDIO_JS)
	fmt.ensuref(write_audio_js_err == nil, "Failed writing %v. Error: %v", entry_odin_file_path, write_audio_js_err)

	write_audio_js_processor_err := os.write_entire_file(path_join({bin_web_dir, "audio_backend_web_audio_processor.js"}), AUDIO_PROCESSOR_JS)
	fmt.ensuref(write_audio_js_processor_err == nil, "Failed writing %v. Error: %v", entry_odin_file_path, write_audio_js_processor_err)

	wasm_out_path := path_join({bin_web_dir, "main.wasm"})

	build_command: [dynamic]string

	append(&build_command, ..[]string{
		"odin",
		"build",
		build_web_dir,
		fmt.tprintf("-out:%v", wasm_out_path),
		"-target:js_wasm32",
	})

	append(&build_command, ..compiler_params[:])

	build_status, build_std_out, build_std_err, _ := os.process_exec({ command = build_command[:] }, allocator = context.allocator)

	if len(build_std_out) > 0 {
		fmt.println(string(build_std_out))
	}

	if len(build_std_err) > 0 {
		fmt.println(string(build_std_err))
	}

	os.exit(build_status.exit_code)
}