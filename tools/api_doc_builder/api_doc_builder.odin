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

// Writes a procedure type the way the doc file should show it, which is not quite what the source
// says.
//
// Return values lose their names. A name like `_ok` is there to stop the implementation assigning
// to it, so it says nothing to somebody reading the API, and it would make two procedures that
// return the same thing look like they differ.
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

	results := make([dynamic]string, context.temp_allocator)

	for field in type.results.list {
		// A field is one type plus the names that share it, so `(a, b: int)` is a single field
		// standing for two return values. Dropping the names has to leave two entries behind.
		// A return value with no name at all reports one name that is the type itself, so the
		// count is right either way and the type is what we want in both cases.
		for _ in 0..<max(len(field.names), 1) {
			append(&results, f.src[field.type.pos.offset:field.type.end.offset])
		}
	}

	// The parameters are used exactly as they are written, so a signature that splits them over
	// several lines keeps them that way. `params.end` sits on the closing parenthesis.
	params := f.src[type.pos.offset:type.params.end.offset + 1]

	if len(results) == 1 {
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

		decl_loop: for &d in f.decls {
			#partial switch &dd in d.derived {
			case ^ast.Value_Decl:
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

				if dd.docs != nil {
					pln(o, "")
					pln(o, f.src[dd.docs.pos.offset:dd.docs.end.offset])
				} else {
					if prev_line != dd.pos.line - 1 {
						pln(o, "")
					}
				}

				pln(o, val)

				prev_line = dd.pos.line
			}
		}
	}

	os.close(o)
}
