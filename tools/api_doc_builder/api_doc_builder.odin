// This program creates the `karl2d.doc.odin` file by parsing `karl2d.odin`. It skips procedure
// bodies and stops when it reaches `API_END :: true`. The resulting file is a nice overview of the
// library's API surface.
//
// Procedure signatures are slightly cleaned up: Return value names that start with an underscore
// are removed, but only if all return values have such names. Tags like `#optional_ok` are written
// back out, since the parser does not keep them in the source range of the procedure type. Boxed
// section headers such as `// INPUT //` are kept, even though the parser does not include them in
// `decl.docs`.
package karl2d_api_doc_builder

import "core:os"
import "core:log"
import "core:fmt"
import "core:odin/parser"
import "core:odin/ast"
import "core:strings"

result_is_named :: proc(field: ^ast.Field) -> bool {
	return len(field.names) > 0 && field.names[0].pos.offset != field.type.pos.offset
}

proc_type_text :: proc(f: ^ast.File, type: ^ast.Proc_Type) -> string {
	tag := ""

	if .Optional_Ok in type.tags {
		tag = " #optional_ok"
	}

	if type.results == nil || len(type.results.list) == 0 {
		return fmt.tprintf("%v%v", f.src[type.pos.offset:type.end.offset], tag)
	}

	strip_names := true

	for field in type.results.list {
		if !result_is_named(field) {
			continue
		}

		for n in field.names {
			if !strings.has_prefix(f.src[n.pos.offset:n.end.offset], "_") {
				strip_names = false
			}
		}
	}

	results := make([dynamic]string, context.temp_allocator)

	for field in type.results.list {
		type_src := f.src[field.type.pos.offset:field.type.end.offset]

		if strip_names {
			for _ in 0..<max(len(field.names), 1) {
				append(&results, type_src)
			}

			continue
		}

		for n in field.names {
			append(&results, fmt.tprintf("%v: %v", f.src[n.pos.offset:n.end.offset], type_src))
		}
	}

	params := f.src[type.pos.offset:type.params.end.offset + 1]

	if len(results) == 1 && strip_names {
		return fmt.tprintf("%v -> %v%v", params, results[0], tag)
	}

	joined := strings.join(results[:], ", ", context.temp_allocator)
	return fmt.tprintf("%v -> (%v)%v", params, joined, tag)
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

		next_comment := 0
		prev_decl_end := 0

		decl_loop: for d in f.decls {
			dd, is_value_decl := d.derived.(^ast.Value_Decl)

			if !is_value_decl {
				continue
			}

			for next_comment < len(f.comments) &&
			    f.comments[next_comment].pos.offset < prev_decl_end {
				next_comment += 1
			}

			first := next_comment

			for next_comment < len(f.comments) &&
			    f.comments[next_comment].end.offset <= dd.pos.offset {
				next_comment += 1
			}

			comments := f.comments[first:next_comment]

			if dd.docs != nil && len(comments) > 0 && comments[len(comments) - 1] == dd.docs {
				comments = comments[:len(comments) - 1]
			}

			prev_decl_end = dd.end.offset

			for a in dd.attributes {
				attr_text := f.src[a.pos.offset:a.close.offset]
				if strings.contains(attr_text, "deprecated") {
					continue decl_loop
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
				break decl_loop
			}

			if len(dd.names) > 0 {
				name := f.src[dd.names[0].pos.offset:dd.names[0].end.offset]

				if strings.has_prefix(name, "_") {
					continue decl_loop
				}
			}

			for comment in comments {
				pln(o, "")
				pln(o, f.src[comment.pos.offset:comment.end.offset])
			}

			if dd.docs != nil {
				pln(o, "")
				pln(o, f.src[dd.docs.pos.offset:dd.docs.end.offset])
			} else {
				if prev_line != dd.pos.line - 1 && len(comments) == 0 {
					pln(o, "")
				}
			}

			pln(o, val)

			prev_line = dd.pos.line
		}
	}

	os.close(o)
}
