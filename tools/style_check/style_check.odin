// Checks the code style rules from CLAUDE.md that a machine can check. It looks only at the lines
// the current changes add, so older code written before a rule does not make it fail.
//
// Check the working tree against HEAD:
//
//     odin run tools/style_check
//
// Check a whole branch, which is what the GitHub CI does:
//
//     odin run tools/style_check -- -base origin/master

package karl2d_style_check

import os "core:os"
import "core:fmt"
import "core:strconv"
import "core:strings"
import "core:unicode/utf8"

MAX_LINE_LENGTH :: 100

GENERATED_FILE :: "karl2d.doc.odin"

problem_count: int

main :: proc() {
	base: string
	args := os.args[1:]

	for i := 0; i < len(args); i += 1 {
		if args[i] == "-base" && i + 1 < len(args) {
			base = args[i + 1]
			i += 1
			continue
		}

		fmt.eprintfln("Unknown argument: %v", args[i])
		fmt.eprintfln("Usage: odin run tools/style_check [-- -base <revision>]")
		os.exit(2)
	}

	if base != "" {
		check_diff(run_git({"diff", "-U0", fmt.tprintf("%v...HEAD", base), "--", "*.odin"}))
	}

	check_diff(run_git({"diff", "-U0", "HEAD", "--", "*.odin"}))
	check_untracked_files()

	if problem_count == 0 {
		fmt.println("Style check passed.")
		return
	}

	fmt.eprintln()
	fmt.eprintfln("%v style problem(s) in added lines. The rules are in CLAUDE.md.", problem_count)
	os.exit(1)
}

// Walks a unified diff produced with -U0, so every line that is not a header is a line the change
// added or removed. The hunk header carries the line number the added lines start at.
check_diff :: proc(diff: string) {
	rest := diff
	file: string
	line_number: int
	generated := false

	for line in strings.split_lines_iterator(&rest) {
		if strings.has_prefix(line, "+++ ") {
			file = strings.trim_prefix(line[4:], "b/")
			generated = strings.has_suffix(file, GENERATED_FILE)
			continue
		}

		if strings.has_prefix(line, "@@ ") {
			line_number = hunk_start_line(line)
			continue
		}

		if !strings.has_prefix(line, "+") {
			continue
		}

		if !generated {
			check_line(file, line_number, line[1:])
		}

		line_number += 1
	}
}

// A file that git does not know about yet has no diff, so all of it counts as added.
check_untracked_files :: proc() {
	list := run_git({"ls-files", "--others", "--exclude-standard", "--", "*.odin"})

	for path in strings.split_lines_iterator(&list) {
		if path == "" || strings.has_suffix(path, GENERATED_FILE) {
			continue
		}

		data, data_err := os.read_entire_file(path, context.allocator)

		if data_err != nil {
			fmt.eprintfln("Failed reading %v. Error: %v", path, data_err)
			continue
		}

		text := string(data)
		line_number := 1

		for line in strings.split_lines_iterator(&text) {
			check_line(path, line_number, line)
			line_number += 1
		}
	}
}

check_line :: proc(file: string, line_number: int, text: string) {
	length := utf8.rune_count_in_string(text)

	if length > MAX_LINE_LENGTH {
		report(
			file,
			line_number,
			fmt.tprintf("Line is %v characters. The limit is %v.", length, MAX_LINE_LENGTH),
		)
	}

	if len(text) > 0 && (text[len(text) - 1] == ' ' || text[len(text) - 1] == '\t') {
		report(file, line_number, "Trailing whitespace.")
	}

	if attribute_has_spaces(text) {
		report(file, line_number, "Spaces around `=` in an attribute. Write `@(private=\"pkg\")`.")
	}

	if range_has_spaces(text) {
		report(file, line_number, "Spaces around a range operator. Write `0..<n`.")
	}

	if is_single_line_if(text) {
		report(file, line_number, "Single line `if` body. The body goes on its own line.")
	}

	if has_prefixed_result_name(text) {
		report(file, line_number, "Result named `err_x` or `ok_x`. Use `x_err` and `x_ok`.")
	}
}

attribute_has_spaces :: proc(text: string) -> bool {
	start := strings.index(text, "@(")

	if start < 0 {
		return false
	}

	inside := text[start + 2:]
	end := strings.index(inside, ")")

	if end >= 0 {
		inside = inside[:end]
	}

	return strings.contains(inside, " =") || strings.contains(inside, "= ")
}

// The operator is found by scanning rather than by matching the spaced forms as string literals,
// so that this file does not report itself.
range_has_spaces :: proc(text: string) -> bool {
	search := text

	for {
		start := strings.index(search, "..")

		if start < 0 || start + 2 >= len(search) {
			return false
		}

		end := start + 2
		operator := search[end]

		if operator == '<' || operator == '=' {
			before_spaced := start > 0 && search[start - 1] == ' '
			after_spaced := end + 1 < len(search) && search[end + 1] == ' '

			if before_spaced || after_spaced {
				return true
			}
		}

		search = search[end:]
	}
}

is_single_line_if :: proc(text: string) -> bool {
	trimmed := strings.trim_space(text)

	if !strings.has_suffix(trimmed, "}") {
		return false
	}

	return strings.has_prefix(trimmed, "if ") ||
		strings.has_prefix(trimmed, "else if ") ||
		strings.has_prefix(trimmed, "} else if ")
}

// Only multi-return result names carry the suffix rule, so this looks for a declaration that binds
// several names at once. `err_buf` as a plain parameter is fine and must not be flagged.
has_prefixed_result_name :: proc(text: string) -> bool {
	assign := strings.index(text, ":=")

	if assign < 0 {
		return false
	}

	left := text[:assign]

	if !strings.contains(left, ",") {
		return false
	}

	for name in strings.split(left, ",", context.temp_allocator) {
		trimmed := strings.trim_space(name)

		if strings.has_prefix(trimmed, "err_") || strings.has_prefix(trimmed, "ok_") {
			return true
		}
	}

	return false
}

// Reads the line number the added side of a hunk starts at out of "@@ -12,0 +13,4 @@".
hunk_start_line :: proc(line: string) -> int {
	plus := strings.index(line, "+")

	if plus < 0 {
		return 0
	}

	digits := line[plus + 1:]
	end := 0

	for end < len(digits) && digits[end] >= '0' && digits[end] <= '9' {
		end += 1
	}

	number, number_ok := strconv.parse_int(digits[:end])

	if !number_ok {
		return 0
	}

	return number
}

run_git :: proc(arguments: []string) -> string {
	command := make([]string, len(arguments) + 1, context.temp_allocator)
	command[0] = "git"
	copy(command[1:], arguments)

	state, std_out, std_err, exec_err := os.process_exec(
		{ command = command },
		allocator = context.allocator,
	)

	if exec_err != nil {
		fmt.eprintfln("Failed running git. Error: %v", exec_err)
		os.exit(2)
	}

	if state.exit_code != 0 {
		fmt.eprint(string(std_err))
		fmt.eprintfln("git %v failed with exit code %v.", arguments[0], state.exit_code)
		os.exit(2)
	}

	return string(std_out)
}

report :: proc(file: string, line_number: int, text: string) {
	fmt.eprintfln("%v:%v: %v", file, line_number, text)
	problem_count += 1
}
