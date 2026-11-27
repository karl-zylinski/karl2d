package karl2d_shader_compiler

import "core:math"
import "core:strings"

CONSTANTS_BLOCK_NAME :: "Karl2D_Constants"
FRAG_COORD_FLIP_NAME :: "karl2d_frag_coord_flip"

Glsl_Emitter :: struct {
	c: ^Compiler,
	b: strings.Builder,
	file: u16,
	line: i32,
	synced_line: i32,
	indent: int,
	frag_coord_prologue: bool,
}

glsl_w :: proc(g: ^Glsl_Emitter, s: string) {
	strings.write_string(&g.b, s)
}

glsl_nl :: proc(g: ^Glsl_Emitter) {
	strings.write_byte(&g.b, '\n')
	g.line += 1
}

glsl_indent :: proc(g: ^Glsl_Emitter) {
	for _ in 0..<g.indent {
		strings.write_byte(&g.b, '\t')
	}
}

glsl_sync_line :: proc(g: ^Glsl_Emitter, file: u16, line: i32) {
	if line <= 0 {
		return
	}

	if file == g.file && line == g.line {
		g.synced_line = line
		return
	}

	if file == g.file && line == g.synced_line {
		return
	}

	g.synced_line = line

	if file == g.file && line > g.line && line - g.line <= 2 {
		for g.line < line {
			glsl_nl(g)
		}

		return
	}

	glsl_w(g, "#line ")
	strings.write_int(&g.b, int(line))
	glsl_w(g, " ")
	strings.write_int(&g.b, int(file))
	strings.write_byte(&g.b, '\n')
	g.file = file
	g.line = line
}

glsl_type :: proc(g: ^Glsl_Emitter, t: Type_Index) {
	ty := g.c.types[t]

	if ty.kind == .Array {
		glsl_w(g, g.c.types[ty.elem].name)
		return
	}

	glsl_w(g, ty.name)
}

glsl_array_suffix :: proc(g: ^Glsl_Emitter, t: Type_Index) {
	ty := g.c.types[t]

	if ty.kind != .Array {
		return
	}

	glsl_w(g, "[")
	strings.write_int(&g.b, int(ty.len))
	glsl_w(g, "]")
}

glsl_declarator :: proc(g: ^Glsl_Emitter, t: Type_Index, name: string) {
	glsl_type(g, t)

	if name != "" {
		glsl_w(g, " ")
		glsl_w(g, name)
	}

	glsl_array_suffix(g, t)
}

glsl_float :: proc(g: ^Glsl_Emitter, value: f64) {
	if math.is_nan(value) {
		glsl_w(g, "(0.0 / 0.0)")
		return
	}

	if math.is_inf(value, 1) {
		glsl_w(g, "(1.0 / 0.0)")
		return
	}

	if math.is_inf(value, -1) {
		glsl_w(g, "(-1.0 / 0.0)")
		return
	}

	start := len(g.b.buf)
	strings.write_float(&g.b, value, 'g', -1, 32)
	has_point := false

	for ch in g.b.buf[start:] {
		if ch == '.' || ch == 'e' {
			has_point = true
			break
		}
	}

	if !has_point {
		glsl_w(g, ".0")
	}
}

glsl_op :: proc(kind: Token_Kind) -> string {
	#partial switch kind {
	case .Plus: return "+"
	case .Minus: return "-"
	case .Star: return "*"
	case .Slash: return "/"
	case .Percent: return "%"
	case .Inc: return "++"
	case .Dec: return "--"
	case .Lt: return "<"
	case .Gt: return ">"
	case .Le: return "<="
	case .Ge: return ">="
	case .Eq_Eq: return "=="
	case .Not_Eq: return "!="
	case .And_And: return "&&"
	case .Or_Or: return "||"
	case .Xor_Xor: return "^^"
	case .Not: return "!"
	case .Amp: return "&"
	case .Pipe: return "|"
	case .Caret: return "^"
	case .Tilde: return "~"
	case .Shl: return "<<"
	case .Shr: return ">>"
	case .Assign: return "="
	case .Add_Assign: return "+="
	case .Sub_Assign: return "-="
	case .Mul_Assign: return "*="
	case .Div_Assign: return "/="
	case .Mod_Assign: return "%="
	case .And_Assign: return "&="
	case .Or_Assign: return "|="
	case .Xor_Assign: return "^="
	case .Shl_Assign: return "<<="
	case .Shr_Assign: return ">>="
	}

	return ""
}

glsl_args :: proc(g: ^Glsl_Emitter, ex: Expr) {
	glsl_w(g, "(")

	for i in 0..<ex.args_count {
		if i > 0 {
			glsl_w(g, ", ")
		}

		glsl_expr(g, g.c.expr_args[ex.args_start + i], true)
	}

	glsl_w(g, ")")
}

glsl_expr :: proc(g: ^Glsl_Emitter, e: Expr_Index, top: bool) {
	c := g.c
	ex := c.exprs[e]

	switch ex.kind {
	case .None:

	case .Literal:
		switch c.types[ex.type].scalar {
		case .Float:
			glsl_float(g, ex.fval)

		case .Int:
			if ex.ival < 0 {
				glsl_w(g, "(")
				strings.write_i64(&g.b, ex.ival)
				glsl_w(g, ")")
			} else {
				strings.write_i64(&g.b, ex.ival)
			}

		case .Uint:
			strings.write_i64(&g.b, ex.ival)
			glsl_w(g, "u")

		case .Bool:
			glsl_w(g, ex.ival != 0 ? "true" : "false")

		case .None:
		}

	case .Var:
		if c.vars[ex.var].builtin == .Frag_Coord {
			glsl_w(g, "karl2d_frag_coord")
		} else {
			glsl_w(g, c.vars[ex.var].name)
		}

	case .Binary:
		if ex.op == .Percent && c.types[ex.type].scalar == .Int && expr_is_pure(c, ex.a) && expr_is_pure(c, ex.b) {
			glsl_w(g, "(")
			glsl_expr(g, ex.a, false)
			glsl_w(g, " - (")
			glsl_expr(g, ex.a, false)
			glsl_w(g, " / ")
			glsl_expr(g, ex.b, false)
			glsl_w(g, ") * ")
			glsl_expr(g, ex.b, false)
			glsl_w(g, ")")
			break
		}

		if !top {
			glsl_w(g, "(")
		}

		glsl_expr(g, ex.a, false)
		glsl_w(g, " ")
		glsl_w(g, glsl_op(ex.op))
		glsl_w(g, " ")
		glsl_expr(g, ex.b, false)

		if !top {
			glsl_w(g, ")")
		}

	case .Unary:
		glsl_w(g, "(")

		if ex.postfix {
			glsl_expr(g, ex.a, false)
			glsl_w(g, glsl_op(ex.op))
		} else {
			glsl_w(g, glsl_op(ex.op))
			glsl_expr(g, ex.a, false)
		}

		glsl_w(g, ")")

	case .Assign:
		if !top {
			glsl_w(g, "(")
		}

		glsl_expr(g, ex.a, false)
		glsl_w(g, " ")
		glsl_w(g, glsl_op(ex.op))
		glsl_w(g, " ")
		glsl_expr(g, ex.b, true)

		if !top {
			glsl_w(g, ")")
		}

	case .Ternary:
		glsl_w(g, "(")
		glsl_expr(g, ex.a, false)
		glsl_w(g, " ? ")
		glsl_expr(g, ex.b, false)
		glsl_w(g, " : ")
		glsl_expr(g, ex.c, false)
		glsl_w(g, ")")

	case .Call:
		glsl_w(g, c.funcs[ex.func].name)
		glsl_args(g, ex)

	case .Builtin_Call:
		if ex.builtin == .DFdy {
			glsl_w(g, "(dFdy")
			glsl_args(g, ex)
			glsl_w(g, " * " + FRAG_COORD_FLIP_NAME + ".x)")
		} else {
			glsl_w(g, builtin_names[ex.builtin])
			glsl_args(g, ex)
		}

	case .Construct:
		glsl_type(g, ex.type)
		glsl_array_suffix(g, ex.type)
		glsl_args(g, ex)

	case .Index:
		glsl_expr(g, ex.a, false)
		glsl_w(g, "[")
		glsl_expr(g, ex.b, true)
		glsl_w(g, "]")

	case .Field:
		glsl_expr(g, ex.a, false)
		glsl_w(g, ".")
		glsl_w(g, c.types[c.exprs[ex.a].type].fields[ex.field].name)

	case .Swizzle:
		glsl_expr(g, ex.a, false)
		glsl_w(g, ".")
		letters := "xyzw"

		for i in 0..<int(ex.swizzle_count) {
			strings.write_byte(&g.b, letters[ex.swizzle[i]])
		}

	case .Comma:
		glsl_w(g, "(")
		glsl_expr(g, ex.a, false)
		glsl_w(g, ", ")
		glsl_expr(g, ex.b, false)
		glsl_w(g, ")")
	}
}

glsl_decl_body :: proc(g: ^Glsl_Emitter, v: Var, init: Expr_Index) {
	if v.is_const {
		glsl_w(g, "const ")
	}

	glsl_declarator(g, v.type, v.name)

	if init != 0 {
		glsl_w(g, " = ")
		glsl_expr(g, init, true)
	}
}

glsl_body :: proc(g: ^Glsl_Emitter, s: Stmt_Index) {
	glsl_w(g, " {")
	glsl_nl(g)
	g.indent += 1

	if g.frag_coord_prologue {
		g.frag_coord_prologue = false
		glsl_w(g, "\tkarl2d_frag_coord = vec4(gl_FragCoord.x, gl_FragCoord.y * " + FRAG_COORD_FLIP_NAME + ".x + " + FRAG_COORD_FLIP_NAME + ".y, gl_FragCoord.zw);")
		glsl_nl(g)
	}

	if s != 0 {
		if g.c.stmts[s].kind == .Block {
			glsl_stmts(g, g.c.stmts[s].first)
		} else {
			glsl_stmts(g, s)
		}
	}

	g.indent -= 1
	glsl_indent(g)
	glsl_w(g, "}")
}

glsl_stmts :: proc(g: ^Glsl_Emitter, first: Stmt_Index) {
	c := g.c
	s := first

	for s != 0 {
		st := c.stmts[s]

		if st.kind == .None {
			s = st.next
			continue
		}

		glsl_sync_line(g, st.file, st.line)
		glsl_indent(g)

		switch st.kind {
		case .None:

		case .Block:
			glsl_w(g, "{")
			glsl_nl(g)
			g.indent += 1
			glsl_stmts(g, st.first)
			g.indent -= 1
			glsl_indent(g)
			glsl_w(g, "}")

		case .Decl:
			glsl_decl_body(g, c.vars[st.var], st.expr)
			glsl_w(g, ";")

		case .Expr:
			glsl_expr(g, st.expr, true)
			glsl_w(g, ";")

		case .If:
			glsl_w(g, "if (")
			glsl_expr(g, st.expr, true)
			glsl_w(g, ")")
			glsl_body(g, st.body)

			if st.else_body != 0 {
				glsl_w(g, " else")
				glsl_body(g, st.else_body)
			}

		case .For:
			glsl_w(g, "for (")
			init := st.first

			for init != 0 {
				is := c.stmts[init]

				if is.kind == .Decl {
					if init == st.first {
						glsl_decl_body(g, c.vars[is.var], is.expr)
					} else {
						glsl_w(g, ", ")
						glsl_w(g, c.vars[is.var].name)

						if is.expr != 0 {
							glsl_w(g, " = ")
							glsl_expr(g, is.expr, true)
						}
					}
				} else {
					glsl_expr(g, is.expr, true)
				}

				init = is.next
			}

			glsl_w(g, "; ")

			if st.expr != 0 {
				glsl_expr(g, st.expr, true)
			}

			glsl_w(g, "; ")

			if st.post != 0 {
				glsl_expr(g, st.post, true)
			}

			glsl_w(g, ")")
			glsl_body(g, st.body)

		case .While:
			glsl_w(g, "while (")
			glsl_expr(g, st.expr, true)
			glsl_w(g, ")")
			glsl_body(g, st.body)

		case .Do_While:
			glsl_w(g, "do")
			glsl_body(g, st.body)
			glsl_w(g, " while (")
			glsl_expr(g, st.expr, true)
			glsl_w(g, ");")

		case .Return:
			glsl_w(g, "return")

			if st.expr != 0 {
				glsl_w(g, " ")
				glsl_expr(g, st.expr, true)
			}

			glsl_w(g, ";")

		case .Break:
			glsl_w(g, "break;")

		case .Continue:
			glsl_w(g, "continue;")

		case .Discard:
			glsl_w(g, "discard;")

		case .Switch:
			glsl_w(g, "switch (")
			glsl_expr(g, st.expr, true)
			glsl_w(g, ") {")
			glsl_nl(g)
			g.indent += 1
			glsl_stmts(g, st.first)
			g.indent -= 1
			glsl_indent(g)
			glsl_w(g, "}")

		case .Case:
			glsl_w(g, "case ")
			glsl_expr(g, st.expr, true)
			glsl_w(g, ":")

		case .Default:
			glsl_w(g, "default:")
		}

		glsl_nl(g)
		s = st.next
	}
}

glsl_signature :: proc(g: ^Glsl_Emitter, f: Func) {
	c := g.c
	glsl_type(g, f.return_type)
	glsl_array_suffix(g, f.return_type)
	glsl_w(g, " ")
	glsl_w(g, f.name)
	glsl_w(g, "(")

	for p, p_idx in f.params {
		if p_idx > 0 {
			glsl_w(g, ", ")
		}

		v := c.vars[p]

		if v.is_const {
			glsl_w(g, "const ")
		}

		switch v.param_qualifier {
		case .In:
		case .Out: glsl_w(g, "out ")
		case .Inout: glsl_w(g, "inout ")
		}

		glsl_declarator(g, v.type, v.name)
	}

	glsl_w(g, ")")
}

glsl_interpolation :: proc(g: ^Glsl_Emitter, v: Var) {
	switch v.interpolation {
	case .Smooth:
	case .Flat: glsl_w(g, "flat ")
	}
}

emit_glsl :: proc(c: ^Compiler, stage: Stage, es: bool) -> []u8 {
	g := Glsl_Emitter {
		c = c,
		line = 1,
	}

	strings.builder_init(&g.b, 0, 4096, c.allocator)

	if es {
		glsl_w(&g, "#version 300 es")
		glsl_nl(&g)
		glsl_w(&g, "precision highp float;")
		glsl_nl(&g)
		glsl_w(&g, "precision highp int;")
		glsl_nl(&g)
		glsl_w(&g, "precision highp sampler2D;")
		glsl_nl(&g)
	} else {
		glsl_w(&g, "#version 330")
		glsl_nl(&g)
	}

	for d in c.decls {
		if d.kind != .Struct {
			continue
		}

		ty := c.types[d.index]
		glsl_w(&g, "struct ")
		glsl_w(&g, ty.name)
		glsl_w(&g, " {")
		glsl_nl(&g)

		for f in ty.fields {
			glsl_w(&g, "\t")
			glsl_declarator(&g, f.type, f.name)
			glsl_w(&g, ";")
			glsl_nl(&g)
		}

		glsl_w(&g, "};")
		glsl_nl(&g)
	}

	if len(c.uniforms) > 0 {
		glsl_w(&g, "layout(std140) uniform ")
		glsl_w(&g, CONSTANTS_BLOCK_NAME)
		glsl_w(&g, " {")
		glsl_nl(&g)

		for u in c.uniforms {
			v := c.vars[u]
			glsl_w(&g, "\t")
			glsl_declarator(&g, v.type, v.name)
			glsl_w(&g, ";")
			glsl_nl(&g)
		}

		glsl_w(&g, "};")
		glsl_nl(&g)
	}

	for t in c.textures {
		v := c.vars[t]

		if stage not_in v.used {
			continue
		}

		glsl_w(&g, "uniform sampler2D ")
		glsl_w(&g, v.name)
		glsl_w(&g, ";")
		glsl_nl(&g)
	}

	if stage == .Vertex {
		for i in c.inputs {
			v := c.vars[i]
			glsl_w(&g, "layout(location = ")
			strings.write_int(&g.b, int(v.location))
			glsl_w(&g, ") in ")
			glsl_declarator(&g, v.type, v.name)
			glsl_w(&g, ";")
			glsl_nl(&g)
		}

		for vary in c.varyings {
			v := c.vars[vary.vertex_var]
			glsl_interpolation(&g, v)
			glsl_w(&g, "out ")
			glsl_declarator(&g, v.type, v.name)
			glsl_w(&g, ";")
			glsl_nl(&g)
		}
	} else {
		for vary in c.varyings {
			if vary.fragment_var == 0 {
				continue
			}

			v := c.vars[vary.fragment_var]
			glsl_interpolation(&g, v)
			glsl_w(&g, "in ")
			glsl_declarator(&g, v.type, v.name)
			glsl_w(&g, ";")
			glsl_nl(&g)
		}

		out := c.vars[c.frag_output]
		glsl_w(&g, "out vec4 ")
		glsl_w(&g, out.name)
		glsl_w(&g, ";")
		glsl_nl(&g)

		if c.uses_frag_coord_flip {
			glsl_w(&g, "vec4 karl2d_frag_coord;")
			glsl_nl(&g)
		}
	}

	for d in c.decls {
		if d.kind != .Func {
			continue
		}

		f := c.funcs[d.index]

		if stage not_in f.used || f.name == "main" {
			continue
		}

		glsl_signature(&g, f)
		glsl_w(&g, ";")
		glsl_nl(&g)
	}

	for d in c.decls {
		switch d.kind {
		case .Struct:

		case .Var:
			v := c.vars[d.index]

			if v.kind != .Global || stage not_in v.used {
				continue
			}

			glsl_sync_line(&g, v.file, v.line)
			glsl_decl_body(&g, v, v.init)
			glsl_w(&g, ";")
			glsl_nl(&g)

		case .Func:
			f := c.funcs[d.index]

			if stage not_in f.used {
				continue
			}

			glsl_sync_line(&g, f.file, f.line)
			g.frag_coord_prologue = c.uses_frag_coord_flip && stage == .Fragment && Func_Index(d.index) == c.main_funcs[stage]
			glsl_signature(&g, f)
			glsl_body(&g, f.body)
			glsl_nl(&g)
		}
	}

	return g.b.buf[:]
}
