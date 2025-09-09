package karl2d_api_doc_builder

import os "core:os/os2"
import vmem "core:mem/virtual"
import "core:log"
import "core:fmt"
import "core:odin/parser"
import "core:odin/ast"
import "core:strings"

main :: proc() {
	arena: vmem.Arena
	context.allocator = vmem.arena_allocator(&arena)
	context.temp_allocator = context.allocator
	context.logger = log.create_console_logger()


	plug_ast, plug_ast_ok := parser.parse_package_from_path(".")
	log.ensuref(plug_ast_ok, "Could not generate AST for package")

	b := strings.builder_make()

	strings.write_string(&b, "// This file is purely documentational and never built.\n")
	strings.write_string(&b, "#+build ignore\n")
	strings.write_string(&b, "package karl2d\n")

	prev_line: int

	for n, &f in plug_ast.files {
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
					strings.write_rune(&b, '\n')
					strings.write_string(&b, f.src[dd.docs.pos.offset:dd.docs.end.offset])
					strings.write_rune(&b, '\n')
				} else {
					if prev_line != dd.pos.line - 1 {
						strings.write_rune(&b, '\n')
					}
				}

				strings.write_string(&b, val)
				strings.write_rune(&b, '\n')

				prev_line = dd.pos.line
			}
		}
	}

	_ = os.write_entire_file("karl2d.doc.odin", transmute([]u8)(strings.to_string(b)))
}
