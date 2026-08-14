// Makes a zed project for developing and testing examples.
package karl2d_make_zed_project

import "core:os"
import "core:fmt"

main :: proc() {
	make_dir_err := os.make_directory_all(".zed")
	
	if make_dir_err != nil {
		fmt.eprintfln("Failed to create .zed directory: %v", make_dir_err)
		return
	}
	
	SETTINGS_TEMPLATE ::
`{
		"tab_size": 4,
		"lsp": {
			"ols": {
				"initialization_options": {
					"enable_hover": true,
					"enable_snippets": true,
					"enable_procedure_snippet": true,
					"enable_completion_matching": true,
					"enable_references": true,
					"enable_document_symbols": true,
					"enable_format": false,
					"enable_document_links": true,
				}
			}
		}
}`

	write_settings_err := os.write_entire_file(".zed/settings.json", SETTINGS_TEMPLATE)
	
	if write_settings_err != nil {
		fmt.eprintfln("Failed to write settings.json: %v", write_settings_err)
		return
	}
	
	debugh, debugh_err := os.open(".zed/debug.json", {.Write, .Create, .Trunc})
	
	if debugh_err != nil {
		fmt.eprintfln("Failed to create debug.json: %v", debugh_err)
		return
	}
	
	tasksh, tasksh_err := os.open(".zed/tasks.json", {.Write, .Create, .Trunc})
	
	if tasksh_err != nil {
		fmt.eprintfln("Failed to create tasks.json: %v", tasksh_err)
		return
	}
	
	examples_entries, examples_entries_err := os.read_all_directory_by_path("examples", context.allocator)
	
	if examples_entries_err != nil {
		fmt.eprintfln("Failed to read examples directory: %v", examples_entries_err)
		return
	}
	
	fmt.fprintln(tasksh, "[")
	fmt.fprintln(debugh, "[")
		
	name_with_ext :: proc(name: string) -> string {
		return fmt.tprintf("%s.%s", name, ODIN_OS == .Windows ? "exe" : "bin")
	}

	write_debug_tasks_entry :: proc(
		tasks_file: ^os.File,
		debug_file: ^os.File,
		name: string,
		src: string,
	) {
		
		TASKS_ENTRY_TEMPLATE ::
`	{{
		"label": "build %s",
		"command": "odin build %s -debug -vet -strict-style -vet-tabs -out:bin/%s",
	}},
`
	
		tasks_entry := fmt.tprintf(
			TASKS_ENTRY_TEMPLATE,
			name,
			src,
			name_with_ext(name),
		)
		
		fmt.fprint(tasks_file, tasks_entry)
		
		DEBUG_ENTRY_TEMPLATE ::
`	{{
		"label": "%s",
		"adapter": "CodeLLDB",
		"program": "bin/%s",
		"request": "launch",
		"workingDirectory": "${{workspace}}",
		"build": "build %s"
	}},
`

		debug_entry := fmt.tprintf(
			DEBUG_ENTRY_TEMPLATE,
			name,
			name_with_ext(name),
			name,
		)
		
		fmt.fprint(debug_file, debug_entry)
	}
	
	for e in examples_entries {
		if e.type != .Directory {
			continue
		}

		write_debug_tasks_entry(tasksh, debugh, e.name, fmt.tprintf("examples/%v", e.name))
	}
	
	write_debug_tasks_entry(tasksh, debugh, "test_examples", "tools/test_examples")
	write_debug_tasks_entry(tasksh, debugh, "api_doc_builder", "tools/api_doc_builder")
	write_debug_tasks_entry(tasksh, debugh, "api_verifier", "tools/api_verifier")
	write_debug_tasks_entry(tasksh, debugh, "make_zed_project", "tools/make_zed_project")
	
	fmt.fprintln(tasksh, "]")
	fmt.fprintln(debugh, "]")
	os.close(debugh)
	os.close(tasksh)
}
