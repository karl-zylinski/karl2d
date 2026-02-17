// Makes a VS Code project for developing and testing examples.
package karl2d_make_vscode_project

import "core:os"
import "core:fmt"

main :: proc() {
	make_dir_err := os.make_directory_all(".vscode")
	
	if make_dir_err != nil {
		fmt.eprintfln("Failed to create .vscode directory: %v", make_dir_err)
		return
	}
	
	SETTINGS_TEMPLATE ::
`{
	"editor.tabSize": 4,
	"editor.insertSpaces": true,
	"editor.formatOnSave": false
}
`

	write_settings_err := os.write_entire_file(".vscode/settings.json", SETTINGS_TEMPLATE)
	
	if write_settings_err != nil {
		fmt.eprintfln("Failed to write settings.json: %v", write_settings_err)
		return
	}
	
	launchh, launchh_err := os.open(".vscode/launch.json", {.Write, .Create, .Trunc})
	
	if launchh_err != nil {
		fmt.eprintfln("Failed to create launch.json: %v", launchh_err)
		return
	}
	
	tasksh, tasksh_err := os.open(".vscode/tasks.json", {.Write, .Create, .Trunc})
	
	if tasksh_err != nil {
		fmt.eprintfln("Failed to create tasks.json: %v", tasksh_err)
		return
	}
	
	examples_entries, examples_entries_err := os.read_all_directory_by_path("examples", context.allocator)
	
	if examples_entries_err != nil {
		fmt.eprintfln("Failed to read examples directory: %v", examples_entries_err)
		return
	}
	
	fmt.fprintln(tasksh, "{")
	fmt.fprintln(tasksh, "\t\"version\": \"2.0.0\",")
	fmt.fprintln(tasksh, "\t\"tasks\": [")
	fmt.fprintln(launchh, "{")
	fmt.fprintln(launchh, "\t\"version\": \"0.2.0\",")
	fmt.fprintln(launchh, "\t\"configurations\": [")
		
	name_with_ext :: proc(name: string) -> string {
		return fmt.tprintf("%s.%s", name, ODIN_OS == .Windows ? "exe" : "bin")
	}

	write_debug_tasks_entry :: proc(
		tasks_file: ^os.File,
		launch_file: ^os.File,
		name: string,
		src: string,
		first_task: ^bool,
		first_launch: ^bool,
	) {
		
		if !first_task^ {
			fmt.fprintln(tasks_file, ",")
		}
		first_task^ = false
		
		TASKS_ENTRY_TEMPLATE ::
`		{{
			"label": "build %s",
			"type": "shell",
			"command": "odin",
			"args": ["build", "%s", "-debug", "-vet", "-strict-style", "-vet-tabs", "-out:bin/%s"],
			"group": {{
				"kind": "build",
				"isDefault": false
			}},
			"problemMatcher": []
		}}`
	
		tasks_entry := fmt.tprintf(
			TASKS_ENTRY_TEMPLATE,
			name,
			src,
			name_with_ext(name),
		)
		
		fmt.fprint(tasks_file, tasks_entry)
		
		if !first_launch^ {
			fmt.fprintln(launch_file, ",")
		}
		first_launch^ = false
		
		LAUNCH_ENTRY_TEMPLATE ::
`		{{
			"name": "%s",
			"type": "lldb",
			"request": "launch",
			"program": "${{workspaceFolder}}/bin/%s",
			"args": [],
			"cwd": "${{workspaceFolder}}",
			"preLaunchTask": "build %s",
			"stopOnEntry": false
		}}`

		launch_entry := fmt.tprintf(
			LAUNCH_ENTRY_TEMPLATE,
			name,
			name_with_ext(name),
			name,
		)
		
		fmt.fprint(launch_file, launch_entry)
	}
	
	first_task := true
	first_launch := true
	
	for e in examples_entries {
		if e.type != .Directory {
			continue
		}

		write_debug_tasks_entry(tasksh, launchh, e.name, fmt.tprintf("examples/%v", e.name), &first_task, &first_launch)
	}
	
	write_debug_tasks_entry(tasksh, launchh, "test_examples", "tools/test_examples", &first_task, &first_launch)
	write_debug_tasks_entry(tasksh, launchh, "api_doc_builder", "tools/api_doc_builder", &first_task, &first_launch)
	write_debug_tasks_entry(tasksh, launchh, "api_verifier", "tools/api_verifier", &first_task, &first_launch)
	write_debug_tasks_entry(tasksh, launchh, "make_vscode_project", "tools/make_vscode_project", &first_task, &first_launch)
	
	fmt.fprintln(tasksh)
	fmt.fprintln(tasksh, "\t]")
	fmt.fprintln(tasksh, "}")
	fmt.fprintln(launchh)
	fmt.fprintln(launchh, "\t]")
	fmt.fprintln(launchh, "}")
	os.close(launchh)
	os.close(tasksh)
}
