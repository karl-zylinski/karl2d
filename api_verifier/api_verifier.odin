// This program takes the current karl2d.doc.odin and compares it to a new one. If there is any
// difference, it exits with an error. This is used in the CI process to make sure users are aware
// that they changed the API in a Pull Request.
package karl2d_api_verifier

import os "core:os/os2"
import "core:fmt"
import "core:strings"

main :: proc() {
	curr_doc_file, curr_doc_file_err := os.read_entire_file("karl2d.doc.odin", context.allocator)

	fmt.ensuref(curr_doc_file_err == nil, "Could not open karl2d.doc.odin. Error: %v", curr_doc_file_err)

	compare_filename := "karl2d.doc.compare.odin"

	build_comparison_doc_command := []string {
		"odin",
		"run",
		"api_doc_builder",
		"--",
		compare_filename,
	}

	build_status, build_std_out, build_std_err, _ := os.process_exec({ command = build_comparison_doc_command[:] }, allocator = context.allocator)

	if len(build_std_out) > 0 {
		fmt.println(string(build_std_out))
	}

	if len(build_std_err) > 0 {
		fmt.println(string(build_std_err))
	}

	if build_status.exit_code != 0 {
		os.exit(build_status.exit_code)
	}

	compare_doc_file, compare_doc_file_err := os.read_entire_file(compare_filename, context.allocator)
	fmt.ensuref(compare_doc_file_err == nil, "Could not open %v. Error: %v", compare_filename, curr_doc_file_err)

	compare_doc_lines := strings.split_lines(string(compare_doc_file))
	curr_doc_lines := strings.split_lines(string(curr_doc_file))
	
	ok := true

	if len(compare_doc_lines) == len(curr_doc_lines) {
		// We compare line-by-line to get rid of any line-ending issues
		for i in 0..<len(compare_doc_lines) {
			l1 := compare_doc_lines[i]
			l2 := curr_doc_lines[i]

			if l1 != l2 {
				ok = false
				break
			}
		}
	} else {
		ok = false
	}

	if !ok {
		fmt.eprintln("karl2d.doc.odin is not up-to-date: You may have modified the API unknowingly. Please run `odin run api_doc_builder` and check what lines in `karl2d.doc.odin` that have changed. Make sure you are really sure about these API changes.")
		os.exit(1)
	}
}