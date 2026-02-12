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

	pln(o, `// This file is purely documentational. It is generated from the contents of 'karl2d.odin'.`)
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
				val: string
				for v, vi in dd.values {
					#partial switch vd in v.derived {
					case ^ast.Proc_Lit:
						name := f.src[dd.names[vi].pos.offset:dd.names[vi].end.offset]
						type := f.src[vd.type.pos.offset:vd.type.end.offset]
						val = fmt.tprintf("%v :: %v", name, type)
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
