// Makes a Sublime project for developing and testing examples.
package karl2d_make_sublime_project

import "core:os"
import "core:fmt"
import "core:strings"

main :: proc() {
	make_dir_err := os.make_directory_all(".sublime")
	
	if make_dir_err != nil && make_dir_err != .Exist {
		fmt.eprintfln("Failed to create .sublime directory: %v", make_dir_err)
		return
	}

	PROJECT_FILE_TEMPLATE ::
`{{
	"folders":
	[
%s
	],
	"build_systems":
	[
		{{
			"file_regex": "^(.+)\\(([0-9]+):([0-9]+)\\) (.+)$",
			"name": "Karl2D",
			"working_dir": "$project_path/..",
			"variants": [
%s
			]
		}}
	],
	"settings":
	{{
		"auto_complete": false,
		"LSP":
		{{
			"odin":
			{{
				"enabled": true,
			}},
		}},
	}},
}}
`

	folders: [dynamic]string
	append(&folders, "..")

	folders_builder := strings.builder_make()

	for f in folders {
		entry := fmt.tprintf(`		{{ "path": "%s" }},`, f)
		strings.write_string(&folders_builder, entry)
	}

	examples_entries, examples_entries_err := os.read_all_directory_by_path("examples", context.allocator)
	
	if examples_entries_err != nil {
		fmt.eprintfln("Failed to read examples directory: %v", examples_entries_err)
		return
	}

	variants_builder := strings.builder_make()

	name_with_ext :: proc(name: string) -> string {
		return fmt.tprintf("%s.%s", name, ODIN_OS == .Windows ? "exe" : "bin")
	}

	write_build_variant :: proc(
		builder: ^strings.Builder,
		name: string,
		src_path: string,
		only_default_variant: bool,
	) {
		DEFAULT_VARIANT_TEMPLATE ::
`				{{
					"name": "%s",
					"working_dir": "$project_path/../%s",
					"shell_cmd": "odin run . -debug -vet -strict-style -vet-tabs",
				}},
`
		variant := fmt.tprintf(DEFAULT_VARIANT_TEMPLATE, name, src_path)
		strings.write_string(builder, variant)

		if only_default_variant {
			return
		}

		GL_VARIANT_TEMPLATE ::
`				{{
					"name": "%s (gl)",
					"working_dir": "$project_path/../%s",
					"shell_cmd": "odin run . -debug -vet -strict-style -vet-tabs -define:KARL2D_RENDER_BACKEND=gl",
				}},
`
		gl_variant := fmt.tprintf(GL_VARIANT_TEMPLATE, name, src_path)
		strings.write_string(builder, gl_variant)

		WEB_VARIANT_TEMPLATE ::
`				{{
					"name": "%s (web)",
					"shell_cmd": "odin run build_web -debug -vet -strict-style -vet-tabs -- %s -vet -strict-style -vet-tabs",
				}},
`
		web_variant := fmt.tprintf(WEB_VARIANT_TEMPLATE, name, src_path)
		strings.write_string(builder, web_variant)
	}

	for e in examples_entries {
		if e.type != .Directory {
			continue
		}

		name := e.name
		src_path := fmt.tprintf("examples/%v", e.name)

		write_build_variant(&variants_builder, name, src_path, false)
	}

	write_build_variant(
		&variants_builder,
		"test_examples",
		"tools/test_examples",
		true,
	)

	write_build_variant(
		&variants_builder,
		"api_doc_builder",
		"tools/api_doc_builder",		true,
	)

	write_build_variant(
		&variants_builder,
		"api_verifier",
		"tools/api_verifier",
		true,
	)

	write_build_variant(
		&variants_builder,
		"make_sublime_project",
		"tools/make_sublime_project",
		true,
	)

	project_str := fmt.tprintf(
		PROJECT_FILE_TEMPLATE,
		strings.to_string(folders_builder),
		strings.to_string(variants_builder),
	)
	project_file_write_err := os.write_entire_file(".sublime/karl2d-examples.sublime-project", transmute([]u8)(project_str))

	if project_file_write_err != nil {
		fmt.eprintfln("Failed writing project file. Error: %v", project_file_write_err)
	}
}
