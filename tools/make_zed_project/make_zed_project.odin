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
	
	examples_entries, examples_entries_err := os.read_all_directory_by_path("examples", context.allocator)
	
	if examples_entries_err != nil {
		fmt.eprintfln("Failed to read examples directory: %v", examples_entries_err)
		return
	}
	
	fmt.fprintln(debugh, "[")
	
	DEBUG_ENTRY_TEMPLATE ::
`	{{
		"label": "%s",
		"adapter": "CodeLLDB",
		"program": "bin/%s",
		"request": "launch",
		"workingDirectory": "${{workspace}}",
		"build": {{
			"command": "odin",
			"args": [
				"build",
				"%s",
				"-debug",
				"-vet",
				"-strict-style",
				"-vet-tabs",
				"-out:bin/%s"
			]
		}}
	}},
`

	write_debug_entry :: proc(h: ^os.File, name: string, src: string) {
		ext := ODIN_OS == .Windows ? "exe" : "bin"
		name_with_ext := fmt.tprintf("%s.%s", name, ext)
		
		debug_build_config := fmt.tprintf(
			DEBUG_ENTRY_TEMPLATE,
			name,
			name_with_ext,
			src,
			name_with_ext,
		)
		
		fmt.fprint(h, debug_build_config)
	}

	for e in examples_entries {
		if e.type != .Directory {
			continue
		}

		write_debug_entry(debugh, e.name, fmt.tprintf("examples/%v", e.name))
	}
	
	fmt.fprint(
		debugh,
		fmt.tprintf(
			DEBUG_ENTRY_TEMPLATE,
			"test_examples",
			"test_examples",
			"tools/test_examples"
		)
	)
	
	fmt.fprint(
		debugh,
		fmt.tprintf(
			DEBUG_ENTRY_TEMPLATE,
			"api_doc_builder",
			"api_doc_builder",
			"tools/api_doc_builder"
		)
	)
	
	fmt.fprint(
		debugh,
		fmt.tprintf(
			DEBUG_ENTRY_TEMPLATE,
			"api_verifier",
			"api_verifier",
			"tools/api_verifier"
		)
	)
	
	fmt.fprintln(debugh, "]")
	os.close(debugh)
}
