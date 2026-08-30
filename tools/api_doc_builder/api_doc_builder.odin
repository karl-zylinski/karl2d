// This program creates the `karl2d.doc.odin` file by parsing `karl2d.odin`. It skips procedure
// bodies and stops when it reaches `API_END :: true`. The resulting file is a nice overview of the
// library's API surface.
package karl2d_api_doc_builder

import "core:os"
import "core:log"
import "core:fmt"
import "core:odin/parser"
import "core:odin/ast"
import "core:strings"

// A return value with no name at all still reports one name, and that name is the type itself.
// Comparing the positions is what tells a real name apart from that.
result_is_named :: proc(f: ^ast.File, field: ^ast.Field) -> bool {
	return len(field.names) > 0 && field.names[0].pos.offset != field.type.pos.offset
}

// Writes a procedure type the way the doc file should show it, which is not quite what the source
// says.
//
// Return values whose name starts with an underscore lose it. That name is there to stop the
// implementation assigning to the return value, so it says nothing to somebody reading the API, and
// it would make two procedures that return the same thing look like they differ. A return value
// named anything else was named to describe itself, so that name is kept.
//
// Tags such as `#optional_ok` have to be written back out. The parser keeps them in a bit set
// rather than in the source range of the procedure type.
proc_type_text :: proc(f: ^ast.File, type: ^ast.Proc_Type) -> string {
	tag := ""

	if .Optional_Ok in type.tags {
		tag = " #optional_ok"
	}

	if type.results == nil || len(type.results.list) == 0 {
		return fmt.tprintf("%v%v", f.src[type.pos.offset:type.end.offset], tag)
	}

	// The underscore only counts when it is on every name. Odin does not let a procedure mix named
	// and unnamed return values, so dropping some of the names and keeping the rest would write out
	// a signature that does not parse.
	strip_names := true

	for field in type.results.list {
		if !result_is_named(f, field) {
			continue
		}

		for n in field.names {
			if !strings.has_prefix(f.src[n.pos.offset:n.end.offset], "_") {
				strip_names = false
			}
		}
	}

	results := make([dynamic]string, context.temp_allocator)
	kept_a_name := false

	for field in type.results.list {
		type_src := f.src[field.type.pos.offset:field.type.end.offset]

		if strip_names || !result_is_named(f, field) {
			// A field is one type plus the names that share it, so `(a, b: int)` is a single field
			// standing for two return values, and has to leave two entries behind.
			for _ in 0..<max(len(field.names), 1) {
				append(&results, type_src)
			}

			continue
		}

		for n in field.names {
			append(&results, fmt.tprintf("%v: %v", f.src[n.pos.offset:n.end.offset], type_src))
			kept_a_name = true
		}
	}

	// The parameters are used exactly as they are written, so a signature that splits them over
	// several lines keeps them that way. `params.end` sits on the closing parenthesis.
	params := f.src[type.pos.offset:type.params.end.offset + 1]

	// A lone return value only needs the parentheses back if it kept a name, since `-> name: T` is
	// not something you can write.
	if len(results) == 1 && !kept_a_name {
		return fmt.tprintf("%v -> %v%v", params, results[0], tag)
	}

	joined := strings.join(results[:], ", ", context.temp_allocator)
	return fmt.tprintf("%v -> (%v)%v", params, joined, tag)
}

// A declaration and the comment groups standing on their own above it.
Doc_Entry :: struct {
	decl:     ^ast.Value_Decl,
	comments: []^ast.Comment_Group,
}

main :: proc() {
	context.logger = log.create_console_logger()

	pkg_ast, pkg_ast_ok := parser.parse_package_from_path(".")
	log.ensuref(pkg_ast_ok, "Could not generate AST for package")

	output_filename := "karl2d.doc.odin"

	if len(os.args) > 1 {
		output_filename = os.args[1]
	}

	o, o_err := os.open(output_filename, {.Create, .Trunc, .Write}, os.perm_number(0o644))
	log.assertf(o_err == nil, "Couldn't open karl2d.doc.odin: %v", o_err)

	pln :: fmt.fprintln

	pln(o, `// This file gives an overview of the Karl2D API. It shows all procedures without their bodies.`)
	pln(o, `// This file is generated from the contents of 'karl2d.odin'. It should not be compiled.`)
	
	pln(o, "#+build ignore")
	pln(o, "package karl2d")

	prev_line: int

	for n, &f in pkg_ast.files {
		if !strings.ends_with(n, "karl2d.odin") {
			continue
		}

		// The boxed section headers such as `// INPUT //` are comment groups of their own. The
		// parser hands a box and the doc comment beneath it over separately, and only the second is
		// reachable through `decl.docs`, so each declaration is first paired up with whatever stands
		// above it. Declarations and comments are both in source order, so this walks the two lists
		// together and looks at each comment once for the whole file.
		entries := make([dynamic]Doc_Entry, context.temp_allocator)
		next_comment := 0
		prev_decl_end := 0

		for d in f.decls {
			decl, is_value_decl := d.derived.(^ast.Value_Decl)

			if !is_value_decl {
				continue
			}

			// Comments that sat inside the previous declaration, such as the ones on struct
			// fields, belong to it. Only what stands between two declarations is a header.
			for next_comment < len(f.comments) &&
			    f.comments[next_comment].pos.offset < prev_decl_end {
				next_comment += 1
			}

			first := next_comment

			for next_comment < len(f.comments) &&
			    f.comments[next_comment].end.offset <= decl.pos.offset {
				next_comment += 1
			}

			comments := f.comments[first:next_comment]

			// The last group before a declaration is its doc comment, which is written from
			// `decl.docs` below. On an older Odin the box and the doc comment arrive as one group,
			// so this drops the lot and the output stays as it was before the parser changed.
			if decl.docs != nil && len(comments) > 0 && comments[len(comments) - 1] == decl.docs {
				comments = comments[:len(comments) - 1]
			}

			append(&entries, Doc_Entry { decl = decl, comments = comments })
			prev_decl_end = decl.end.offset
		}

		entry_loop: for entry in entries {
			dd := entry.decl

			for a in dd.attributes {
				attr_text := f.src[a.pos.offset:a.close.offset]
				if strings.contains(attr_text, "deprecated") {
					continue entry_loop
				}
			}

			val: string
			for v, vi in dd.values {
				#partial switch vd in v.derived {
				case ^ast.Proc_Lit:
					name := f.src[dd.names[vi].pos.offset:dd.names[vi].end.offset]
					val = fmt.tprintf("%v :: %v", name, proc_type_text(f, vd.type))
				}
			}

			if val == "" {
				val = f.src[dd.pos.offset:dd.end.offset]
			}

			if val == "API_END :: true" {
				break entry_loop
			}

			// A name that starts with an underscore is internal. The underscore already says that
			// on return values, so it says the same here. Filtering on it lets a helper sit next
			// to the API procedure that uses it, instead of being moved out of the way to keep it
			// out of this file.
			if len(dd.names) > 0 {
				name := f.src[dd.names[0].pos.offset:dd.names[0].end.offset]

				if strings.has_prefix(name, "_") {
					continue entry_loop
				}
			}

			for comment in entry.comments {
				pln(o, "")
				pln(o, f.src[comment.pos.offset:comment.end.offset])
			}

			if dd.docs != nil {
				pln(o, "")
				pln(o, f.src[dd.docs.pos.offset:dd.docs.end.offset])
			} else {
				if prev_line != dd.pos.line - 1 && len(entry.comments) == 0 {
					pln(o, "")
				}
			}

			pln(o, val)

			prev_line = dd.pos.line
		}
	}

	os.close(o)
}
