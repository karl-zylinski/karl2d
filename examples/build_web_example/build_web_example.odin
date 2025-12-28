package karl2d_build_web_example

import "core:os"
import "core:fmt"
import "core:path/filepath"
import "core:os/os2"

main :: proc() {
	if len(os.args) != 2 {
		fmt.eprintfln("Usage: 'odin run build_web_example -- example_directory_name'\nExample: 'odin run build_web_example -- minimal'")
		return
	}

	WEB_ENTRY_TEMPLATE :: #load("web_entry_templates/web_entry_template.odin")
	WEB_ENTRY_INDEX :: #load("web_entry_templates/index_template.html")

	dir := os.args[1]
	dir_handle, dir_handle_err := os.open(dir)

	fmt.ensuref(dir_handle_err == nil, "Failed finding directory %v. Error: %v", dir, dir_handle_err)

	dir_stat, dir_stat_err := os.fstat(dir_handle)

	fmt.ensuref(dir_stat_err == nil, "Failed checking status of directory %v. Error: %v", dir, dir_stat_err)
		
	fmt.ensuref(dir_stat.is_dir, "%v is not a directory!", dir)

	web_dir := filepath.join({dir, "web"})
	os.make_directory(web_dir, 0o644)

	web_build_dir := filepath.join({web_dir, "build"})

	os.write_entire_file(
		filepath.join(
			{web_dir, fmt.tprintf("%v_web_entry.odin", dir)},
		),
		WEB_ENTRY_TEMPLATE,
	)
	os.write_entire_file(filepath.join({web_build_dir, "index.html"}), WEB_ENTRY_INDEX)

	_, odin_root_stdout, _, odin_root_err := os2.process_exec({
		command = { "odin", "root" },
	}, allocator = context.allocator)

	ensure(odin_root_err == nil, "Failed fetching 'odin root' (Odin in PATH needed!)")

	odin_root := string(odin_root_stdout)
	

	js_runtime_path := filepath.join({odin_root, "core", "sys", "wasm", "js", "odin.js"})
	fmt.ensuref(os2.exists(js_runtime_path), "File does not exist: %v -- It is the Odin Javascript runtime that this program needs to copy to the web build output folder!", js_runtime_path)

	os2.copy_file(filepath.join({web_build_dir, "odin.js"}), js_runtime_path)

	wasm_out_path := filepath.join({web_build_dir, "main.wasm"})

	build_status, build_std_out, build_std_err, build_err := os2.process_exec({
		command = {
			"odin",
			"build",
			web_dir,
			fmt.tprintf("-out:%v", wasm_out_path),
			"-target:js_wasm32",
			"-debug",
			"-vet",
			"-strict-style",
		},
	}, allocator = context.allocator)
	
	if len(build_std_out) > 0 {
		fmt.println(string(build_std_out))
	}

	if len(build_std_err) > 0 {
		fmt.println(string(build_std_err))
	}
}