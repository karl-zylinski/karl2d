package karl2d_shader_compiler

MAX_TEXTURES :: 16

Qualifiers :: struct {
	is_const: bool,
	is_uniform: bool,
	is_in: bool,
	is_out: bool,
	is_inout: bool,
	interpolation: Interpolation,
	location: i32,
}

new_stmt :: proc(c: ^Compiler, s: Stmt) -> Stmt_Index {
	append(&c.stmts, s)
	return Stmt_Index(len(c.stmts) - 1)
}

push_scope :: proc(c: ^Compiler) {
	append(&c.scope_marks, len(c.scope))
}

pop_scope :: proc(c: ^Compiler) {
	resize(&c.scope, pop(&c.scope_marks))
}

declare_var :: proc(c: ^Compiler, v: Var) -> Var_Index {
	scope_start := 0

	if len(c.scope_marks) > 0 {
		scope_start = c.scope_marks[len(c.scope_marks) - 1]
	}

	for i in scope_start..<len(c.scope) {
		if c.vars[c.scope[i]].name == v.name {
			compile_error(c, v.file, v.line, "'%s' is already declared", v.name)
			return 0
		}
	}

	if is_reserved_name(v.name) {
		compile_error(c, v.file, v.line, "'%s' cannot be used as a name, GLSL reserves it", v.name)
		return 0
	}

	append(&c.vars, v)
	idx := Var_Index(len(c.vars) - 1)
	append(&c.scope, idx)
	return idx
}

parse_qualifiers :: proc(c: ^Compiler) -> Qualifiers {
	q := Qualifiers { location = -1 }

	for !c.failed {
		tok := c.tokens[c.tok]

		#partial switch tok.kind {
		case .Kw_Const: q.is_const = true
		case .Kw_Uniform: q.is_uniform = true
		case .Kw_In: q.is_in = true
		case .Kw_Out: q.is_out = true
		case .Kw_Inout: q.is_inout = true
		case .Kw_Flat: q.interpolation = .Flat
		case .Kw_Smooth: q.interpolation = .Smooth
		case .Kw_Noperspective:
			compile_error(c, tok.file, tok.line, "'noperspective' is not supported, because GLSL ES (web and Android) does not have it. Remove it: when gl_Position.w is 1, as it is in 2D, it makes no difference. With a perspective projection, multiply the value by gl_Position.w in the vertex stage and by gl_FragCoord.w in the fragment stage")
			return q
		case .Kw_Highp, .Kw_Mediump, .Kw_Lowp:

		case .Kw_Layout:
			advance(c)
			expect(c, .LParen, "'('")

			for !c.failed {
				name := expect(c, .Ident, "a layout name")

				if name.text != "location" {
					compile_error(c, name.file, name.line, "layout(%s) is not supported, only layout(location = N)", name.text)
					return q
				}

				expect(c, .Assign, "'='")
				q.location = i32(parse_const_int_or_zero(c))

				if !accept(c, .Comma) {
					break
				}
			}

			expect(c, .RParen, "')'")
			continue

		case:
			return q
		}

		advance(c)
	}

	return q
}

parse_const_int_or_zero :: proc(c: ^Compiler) -> int {
	tok := c.tokens[c.tok]
	e := parse_ternary(c)

	if c.failed {
		return 0
	}

	ex := c.exprs[e]

	if ex.kind != .Literal || (ex.type != T_INT && ex.type != T_UINT) || ex.ival < 0 {
		compile_error(c, tok.file, tok.line, "Expected a constant integer")
		return 0
	}

	return int(ex.ival)
}

parse_type :: proc(c: ^Compiler) -> Type_Index {
	tok := c.tokens[c.tok]

	if tok.kind != .Ident {
		expect(c, .Ident, "a type")
		return T_NONE
	}

	type := lookup_type(c, tok)

	if type == T_NONE {
		if is_unsupported_type_name(tok.text) {
			compile_error(c, tok.file, tok.line, "The type '%s' is not supported", tok.text)
		} else {
			compile_error(c, tok.file, tok.line, "'%s' is not a known type", tok.text)
		}

		return T_NONE
	}

	advance(c)

	if peek(c) == .LBracket && peek_at(c, 1) != .RBracket {
		advance(c)
		length := parse_const_int(c, "an array size")
		expect(c, .RBracket, "']'")
		type = type_array(c, type, length)
	}

	return type
}

is_unsupported_type_name :: proc(name: string) -> bool {
	switch name {
	case "double", "dvec2", "dvec3", "dvec4", "mat2x2", "mat2x3", "mat2x4", "mat3x2", "mat3x3", "mat3x4",
	     "mat4x2", "mat4x3", "mat4x4", "sampler1D", "sampler3D", "samplerCube", "sampler2DArray",
	     "sampler2DShadow", "sampler2DRect", "sampler2DMS", "isampler2D", "usampler2D":
		return true
	}

	return false
}

is_reserved_name :: proc(name: string) -> bool {
	if len(name) >= 3 && name[:3] == "gl_" {
		return true
	}

	if len(name) >= 7 && name[:7] == "karl2d_" {
		return true
	}

	switch name {
	case CONSTANTS_BLOCK_NAME, "attribute", "varying", "centroid", "invariant", "common", "partition", "active",
	     "asm", "class", "union", "enum", "typedef", "template", "this", "packed", "goto", "inline", "noinline",
	     "volatile", "public", "static", "extern", "external", "interface", "long", "short", "half", "fixed",
	     "unsigned", "superp", "input", "output", "filter", "sizeof", "cast", "namespace", "using", "sample",
	     "patch", "subroutine", "resource", "atomic_uint", "coherent", "restrict", "readonly", "writeonly",
	     "precise", "register":
		return true
	}

	return false
}

parse_array_suffix :: proc(c: ^Compiler, type: Type_Index) -> (result: Type_Index, unsized: bool) {
	if peek(c) != .LBracket {
		return type, false
	}

	tok := advance(c)

	if accept(c, .RBracket) {
		return type, true
	}

	if c.types[type].kind == .Array {
		compile_error(c, tok.file, tok.line, "Arrays of arrays are not supported")
		return type, false
	}

	length := parse_const_int(c, "an array size")
	expect(c, .RBracket, "']'")
	return type_array(c, type, length), false
}

parse_program :: proc(c: ^Compiler) {
	for peek(c) != .EOF {
		tok := c.tokens[c.tok]

		#partial switch tok.kind {
		case .Stage_Vertex, .Stage_Fragment:
			advance(c)
			stage := tok.kind == .Stage_Vertex ? Stage.Vertex : Stage.Fragment

			if stage in c.seen_stages {
				compile_error(c, tok.file, tok.line, "This stage is already declared")
				return
			}

			if c.seen_stages == {} {
				c.stage_scope_start = len(c.scope)
			}

			resize(&c.scope, c.stage_scope_start)
			c.seen_stages += { stage }
			c.stage = stage

		case .Semicolon:
			advance(c)

		case .Kw_Precision:
			for peek(c) != .Semicolon && peek(c) != .EOF {
				advance(c)
			}

		case .Kw_Struct:
			parse_struct(c)

		case:
			parse_global(c)
		}
	}
}

parse_struct :: proc(c: ^Compiler) {
	advance(c)
	name := expect(c, .Ident, "a struct name")
	expect(c, .LBrace, "'{'")

	if c.failed {
		return
	}

	if lookup_type(c, name) != T_NONE {
		compile_error(c, name.file, name.line, "The type '%s' is already declared", name.text)
		return
	}

	fields := make([dynamic]Field, 0, 8)

	for peek(c) != .RBrace && peek(c) != .EOF {
		parse_qualifiers(c)
		field_base := parse_type(c)

		for !c.failed {
			field_name := expect(c, .Ident, "a field name")
			field_type, unsized := parse_array_suffix(c, field_base)

			if c.failed {
				return
			}

			if unsized || field_type == T_VOID || type_contains_sampler(c, field_type) {
				compile_error(c, field_name.file, field_name.line, "The field '%s' has a type that cannot be used in a struct", field_name.text)
				return
			}

			for f in fields {
				if f.name == field_name.text {
					compile_error(c, field_name.file, field_name.line, "The field '%s' is already declared", field_name.text)
					return
				}
			}

			append(&fields, Field { name = field_name.text, type = field_type })

			if !accept(c, .Comma) {
				break
			}
		}

		expect(c, .Semicolon, "';'")
	}

	expect(c, .RBrace, "'}'")
	expect(c, .Semicolon, "';'")

	if c.failed {
		return
	}

	if len(fields) == 0 {
		compile_error(c, name.file, name.line, "The struct '%s' has no fields", name.text)
		return
	}

	offset := 0

	for &f in fields {
		field_size, field_align := type_std140_layout(c, f.type)
		offset = (offset + field_align - 1) / field_align * field_align
		f.offset = i32(offset)
		offset += field_size
	}

	append(&c.types, Type { kind = .Struct, name = name.text, fields = fields[:] })
	append(&c.decls, Decl { kind = .Struct, index = i32(len(c.types) - 1) })
}

parse_global :: proc(c: ^Compiler) {
	q := parse_qualifiers(c)

	if c.failed {
		return
	}

	first := c.tokens[c.tok]

	if q.is_uniform && first.kind == .Ident && peek_at(c, 1) == .LBrace {
		compile_error(c, first.file, first.line, "Uniform blocks are not supported. Declare each uniform on its own, or use a struct as the uniform's type")
		return
	}

	base_type := parse_type(c)
	name := expect(c, .Ident, "a name")

	if c.failed {
		return
	}

	if peek(c) == .LParen {
		parse_function(c, q, base_type, name)
		return
	}

	for !c.failed {
		type, unsized := parse_array_suffix(c, base_type)
		init: Expr_Index

		if accept(c, .Assign) {
			init = parse_assign(c)
		}

		if c.failed {
			return
		}

		if unsized {
			if init == 0 || c.types[c.exprs[init].type].kind != .Array {
				compile_error(c, name.file, name.line, "The array '%s' needs a size", name.text)
				return
			}

			type = c.exprs[init].type
		}

		declare_global(c, q, type, name, init)

		if !accept(c, .Comma) {
			break
		}

		name = expect(c, .Ident, "a name")
	}

	expect(c, .Semicolon, "';'")
}

declare_global :: proc(c: ^Compiler, q: Qualifiers, type: Type_Index, name: Token, init_expr: Expr_Index) {
	init := init_expr

	if type == T_VOID {
		compile_error(c, name.file, name.line, "'%s' cannot be void", name.text)
		return
	}

	if init != 0 {
		init = convert_to(c, init, type, "initial value")

		if c.failed {
			return
		}
	}

	v := Var {
		name = name.text,
		type = type,
		stage = c.stage,
		file = name.file,
		line = name.line,
		location = q.location,
		interpolation = q.interpolation,
		init = init,
		kind = .Global,
	}

	is_sampler := type_contains_sampler(c, type)

	if is_sampler && (!q.is_uniform || type != T_SAMPLER_2D) {
		compile_error(c, name.file, name.line, "A sampler2D can only be declared as 'uniform sampler2D %s;'", name.text)
		return
	}

	if q.is_uniform {
		v.kind = .Uniform
		list := is_sampler ? &c.textures : &c.uniforms

		if is_sampler && len(c.textures) >= MAX_TEXTURES {
			compile_error(c, name.file, name.line, "Too many textures, a shader can use at most %d", MAX_TEXTURES)
			return
		}

		if init != 0 && !is_const_expr(c, init) {
			compile_error(c, name.file, name.line, "The default value of the uniform '%s' must be constant", name.text)
			return
		}

		if (c.types[type].kind == .Struct || c.types[type].kind == .Array) && type_contains_bool(c, type) {
			compile_error(c, name.file, name.line, "The uniform '%s' has a bool inside a struct or array, which is not supported. Use an int instead", name.text)
			return
		}

		for existing in list {
			ev := c.vars[existing]

			if ev.name != name.text {
				continue
			}

			if ev.stage == c.stage || ev.stage == .Shared {
				break
			}

			if ev.type != type {
				compile_error(c, name.file, name.line, "The uniform '%s' has a different type in the other stage", name.text)
				return
			}

			c.vars[existing].stage = .Shared
			append(&c.scope, existing)
			return
		}

		idx := declare_var(c, v)

		if idx != 0 {
			append(list, idx)
			append(&c.decls, Decl { kind = .Var, index = i32(idx) })
		}

		return
	}

	if q.is_in || q.is_out {
		if c.stage == .Shared {
			compile_error(c, name.file, name.line, "'%s' must be declared after #vertex or #fragment", name.text)
			return
		}

		ty := c.types[type]

		if ty.kind != .Scalar && ty.kind != .Vector {
			compile_error(c, name.file, name.line, "'%s' must be a number or a vector", name.text)
			return
		}

		if ty.scalar == .Bool {
			compile_error(c, name.file, name.line, "'%s' cannot be a bool", name.text)
			return
		}

		if init != 0 {
			compile_error(c, name.file, name.line, "'%s' cannot have an initial value", name.text)
			return
		}

		v.kind = q.is_in ? .Input : .Output

		if c.stage == .Vertex && q.is_in {
			if ty.scalar != .Float {
				compile_error(c, name.file, name.line, "The vertex input '%s' must be a float or a float vector", name.text)
				return
			}

			idx := declare_var(c, v)

			if idx != 0 {
				append(&c.inputs, idx)
			}

			return
		}

		if c.stage == .Fragment && q.is_out {
			if type != T_VEC4 {
				compile_error(c, name.file, name.line, "The fragment output '%s' must be a vec4", name.text)
				return
			}

			if c.frag_output != 0 {
				compile_error(c, name.file, name.line, "Only one fragment output is supported")
				return
			}

			c.frag_output = declare_var(c, v)
			return
		}

		if ty.scalar != .Float {
			v.interpolation = .Flat
		}

		if c.stage == .Vertex {
			idx := declare_var(c, v)

			if idx != 0 {
				append(&c.varyings, Varying { vertex_var = idx })
			}

			return
		}

		for &vary in c.varyings {
			vv := c.vars[vary.vertex_var]

			if vv.name != name.text {
				continue
			}

			if vv.type != type {
				compile_error(c, name.file, name.line, "'%s' is a '%s' here but a '%s' in the vertex stage", name.text, type_name(c, type), type_name(c, vv.type))
				return
			}

			if vv.interpolation != v.interpolation {
				compile_error(c, name.file, name.line, "'%s' has a different interpolation in the vertex stage", name.text)
				return
			}

			vary.fragment_var = declare_var(c, v)
			return
		}

		compile_error(c, name.file, name.line, "The fragment input '%s' has no matching 'out' in the vertex stage", name.text)
		return
	}

	if init != 0 && !is_const_expr(c, init) {
		compile_error(c, name.file, name.line, "The initial value of '%s' must be constant. Assign it inside main instead", name.text)
		return
	}

	if q.is_const {
		if init == 0 {
			compile_error(c, name.file, name.line, "The constant '%s' needs a value", name.text)
			return
		}

		v.is_const = true
		set_const_value(c, &v, init)
	}

	idx := declare_var(c, v)

	if idx != 0 {
		append(&c.decls, Decl { kind = .Var, index = i32(idx) })
	}
}

set_const_value :: proc(c: ^Compiler, v: ^Var, init: Expr_Index) {
	ex := c.exprs[init]

	if ex.kind != .Literal {
		return
	}

	v.has_const_value = true
	v.ival = ex.ival
	v.fval = ex.fval
}

is_const_expr :: proc(c: ^Compiler, e: Expr_Index) -> bool {
	ex := c.exprs[e]

	#partial switch ex.kind {
	case .Literal:
		return true

	case .Unary:
		return ex.op != .Inc && ex.op != .Dec && is_const_expr(c, ex.a)

	case .Binary, .Index, .Field, .Swizzle, .Ternary:
		if !is_const_expr(c, ex.a) {
			return false
		}

		if ex.b != 0 && !is_const_expr(c, ex.b) {
			return false
		}

		return ex.c == 0 || is_const_expr(c, ex.c)

	case .Construct, .Builtin_Call:
		if ex.kind == .Builtin_Call {
			#partial switch ex.builtin {
			case .Texture, .Texture_Lod, .Texture_Grad, .Texel_Fetch, .Texture_Size, .DFdx, .DFdy, .Fwidth:
				return false
			}
		}

		for i in 0..<ex.args_count {
			if !is_const_expr(c, c.expr_args[ex.args_start + i]) {
				return false
			}
		}

		return true

	case .Var:
		v := c.vars[ex.var]
		return v.is_const && v.kind != .Param && v.init != 0
	}

	return false
}

parse_function :: proc(c: ^Compiler, q: Qualifiers, return_type: Type_Index, name: Token) {
	advance(c)
	params := make([dynamic]Var_Index, 0, 8)
	push_scope(c)

	if peek(c) == .Ident && c.tokens[c.tok].text == "void" && peek_at(c, 1) == .RParen {
		advance(c)
	}

	for peek(c) != .RParen && !c.failed {
		pq := parse_qualifiers(c)
		param_base := parse_type(c)
		param_name := c.tokens[c.tok]

		if param_name.kind == .Ident {
			advance(c)
		} else {
			param_name.text = ""
		}

		param_type, unsized := parse_array_suffix(c, param_base)

		if c.failed {
			break
		}

		if unsized || param_type == T_VOID {
			compile_error(c, param_name.file, param_name.line, "The parameter '%s' has a type that cannot be used here", param_name.text)
			break
		}

		v := Var {
			name = param_name.text,
			type = param_type,
			kind = .Param,
			stage = c.stage,
			is_const = pq.is_const,
			file = param_name.file,
			line = param_name.line,
			location = -1,
		}

		if pq.is_inout {
			v.param_qualifier = .Inout
		} else if pq.is_out {
			v.param_qualifier = .Out
		}

		if param_type == T_SAMPLER_2D && v.param_qualifier != .In {
			compile_error(c, param_name.file, param_name.line, "A sampler2D parameter cannot be 'out' or 'inout'")
			break
		}

		idx: Var_Index

		if v.name == "" {
			append(&c.vars, v)
			idx = Var_Index(len(c.vars) - 1)
		} else {
			idx = declare_var(c, v)
		}

		append(&params, idx)

		if !accept(c, .Comma) {
			break
		}
	}

	expect(c, .RParen, "')'")

	if c.failed {
		return
	}

	func_idx := Func_Index(0)

	for fi in 1..<len(c.funcs) {
		f := c.funcs[fi]

		if f.name != name.text {
			continue
		}

		if f.stage != .Shared && f.stage != c.stage {
			continue
		}

		if len(f.params) != len(params) {
			continue
		}

		same := true

		for p, p_idx in f.params {
			if c.vars[p].type != c.vars[params[p_idx]].type {
				same = false
				break
			}
		}

		if !same {
			continue
		}

		if f.has_body || f.return_type != return_type {
			compile_error(c, name.file, name.line, "The function '%s' is already declared", name.text)
			return
		}

		func_idx = Func_Index(fi)
		break
	}

	if func_idx == 0 {
		append(&c.funcs, Func {
			name = name.text,
			return_type = return_type,
			stage = c.stage,
			file = name.file,
			line = name.line,
		})

		func_idx = Func_Index(len(c.funcs) - 1)
	}

	c.funcs[func_idx].params = params[:]

	if name.text == "main" {
		if c.stage == .Shared {
			compile_error(c, name.file, name.line, "'main' must be declared after #vertex or #fragment")
			return
		}

		if return_type != T_VOID || len(params) != 0 {
			compile_error(c, name.file, name.line, "'main' must be declared as 'void main()'")
			return
		}

		c.main_funcs[c.stage] = func_idx
	}

	if accept(c, .Semicolon) {
		pop_scope(c)
		return
	}

	if peek(c) != .LBrace {
		expect(c, .LBrace, "'{'")
		return
	}

	c.funcs[func_idx].has_body = true
	c.funcs[func_idx].file = name.file
	c.funcs[func_idx].line = name.line
	c.cur_func = func_idx
	body := parse_block(c, false)
	c.cur_func = 0
	c.funcs[func_idx].body = body
	pop_scope(c)
	append(&c.decls, Decl { kind = .Func, index = i32(func_idx) })
}

parse_block :: proc(c: ^Compiler, new_scope: bool) -> Stmt_Index {
	open := expect(c, .LBrace, "'{'")

	if new_scope {
		push_scope(c)
	}

	block := new_stmt(c, Stmt { kind = .Block, file = open.file, line = open.line })
	last := Stmt_Index(0)

	for peek(c) != .RBrace && peek(c) != .EOF {
		s := parse_statement(c)

		if c.failed {
			break
		}

		if s == 0 {
			continue
		}

		if last == 0 {
			c.stmts[block].first = s
		} else {
			c.stmts[last].next = s
		}

		last = s

		for c.stmts[last].next != 0 {
			last = c.stmts[last].next
		}
	}

	expect(c, .RBrace, "'}'")

	if new_scope {
		pop_scope(c)
	}

	return block
}

is_declaration_start :: proc(c: ^Compiler) -> bool {
	tok := c.tokens[c.tok]

	#partial switch tok.kind {
	case .Kw_Const, .Kw_Highp, .Kw_Mediump, .Kw_Lowp:
		return true

	case .Ident:
		if lookup_type(c, tok) == T_NONE {
			return false
		}

		next := peek_at(c, 1)

		if next == .Ident {
			return true
		}

		if next != .LBracket {
			return false
		}

		i := 2

		for peek_at(c, i) != .RBracket && peek_at(c, i) != .EOF {
			i += 1
		}

		return peek_at(c, i + 1) == .Ident
	}

	return false
}

parse_local_decl :: proc(c: ^Compiler) -> Stmt_Index {
	q := parse_qualifiers(c)
	base_type := parse_type(c)
	first := Stmt_Index(0)
	last := Stmt_Index(0)

	for !c.failed {
		name := expect(c, .Ident, "a name")
		type, unsized := parse_array_suffix(c, base_type)
		init: Expr_Index

		if accept(c, .Assign) {
			init = parse_assign(c)
		}

		if c.failed {
			return 0
		}

		if unsized {
			if init == 0 || c.types[c.exprs[init].type].kind != .Array {
				compile_error(c, name.file, name.line, "The array '%s' needs a size", name.text)
				return 0
			}

			type = c.exprs[init].type
		}

		if type == T_VOID || type_contains_sampler(c, type) {
			compile_error(c, name.file, name.line, "'%s' has a type that cannot be used for a variable", name.text)
			return 0
		}

		if init != 0 {
			init = convert_to(c, init, type, "initial value")
		}

		v := Var {
			name = name.text,
			type = type,
			kind = .Local,
			stage = c.stage,
			is_const = q.is_const,
			file = name.file,
			line = name.line,
			location = -1,
			init = init,
		}

		if q.is_const {
			if init == 0 {
				compile_error(c, name.file, name.line, "The constant '%s' needs a value", name.text)
				return 0
			}

			if !is_const_expr(c, init) {
				compile_error(c, name.file, name.line, "The value of the constant '%s' is not constant. Remove 'const' or use only constants in the value", name.text)
				return 0
			}

			set_const_value(c, &v, init)
		}

		idx := declare_var(c, v)
		s := new_stmt(c, Stmt { kind = .Decl, var = idx, expr = init, file = name.file, line = name.line })

		if first == 0 {
			first = s
		} else {
			c.stmts[last].next = s
		}

		last = s

		if !accept(c, .Comma) {
			break
		}
	}

	return first
}

parse_condition :: proc(c: ^Compiler, what: string) -> Expr_Index {
	tok := c.tokens[c.tok]
	e := parse_expr(c)

	if c.failed {
		return 0
	}

	if c.exprs[e].type != T_BOOL {
		compile_error(c, tok.file, tok.line, "The condition of %s must be a bool but its type is '%s'", what, type_name(c, c.exprs[e].type))
		return 0
	}

	return e
}

parse_statement :: proc(c: ^Compiler) -> Stmt_Index {
	tok := c.tokens[c.tok]

	#partial switch tok.kind {
	case .Semicolon:
		advance(c)
		return 0

	case .LBrace:
		return parse_block(c, true)

	case .Kw_If:
		advance(c)
		expect(c, .LParen, "'('")
		cond := parse_condition(c, "'if'")
		expect(c, .RParen, "')'")
		push_scope(c)
		body := parse_statement(c)
		pop_scope(c)
		else_body: Stmt_Index

		if accept(c, .Kw_Else) {
			push_scope(c)
			else_body = parse_statement(c)
			pop_scope(c)
		}

		return new_stmt(c, Stmt { kind = .If, expr = cond, body = body, else_body = else_body, file = tok.file, line = tok.line })

	case .Kw_For:
		advance(c)
		expect(c, .LParen, "'('")
		push_scope(c)
		init: Stmt_Index

		if !accept(c, .Semicolon) {
			if is_declaration_start(c) {
				init = parse_local_decl(c)
			} else {
				init_tok := c.tokens[c.tok]
				init = new_stmt(c, Stmt { kind = .Expr, expr = parse_expr(c), file = init_tok.file, line = init_tok.line })
			}

			expect(c, .Semicolon, "';'")
		}

		cond: Expr_Index

		if peek(c) != .Semicolon {
			cond = parse_condition(c, "'for'")
		}

		expect(c, .Semicolon, "';'")
		post: Expr_Index

		if peek(c) != .RParen {
			post = parse_expr(c)
		}

		expect(c, .RParen, "')'")
		c.loop_depth += 1
		body := peek(c) == .LBrace ? parse_block(c, false) : parse_statement(c)
		c.loop_depth -= 1
		pop_scope(c)
		return new_stmt(c, Stmt { kind = .For, first = init, expr = cond, post = post, body = body, file = tok.file, line = tok.line })

	case .Kw_While:
		advance(c)
		expect(c, .LParen, "'('")
		cond := parse_condition(c, "'while'")
		expect(c, .RParen, "')'")
		push_scope(c)
		c.loop_depth += 1
		body := parse_statement(c)
		c.loop_depth -= 1
		pop_scope(c)
		return new_stmt(c, Stmt { kind = .While, expr = cond, body = body, file = tok.file, line = tok.line })

	case .Kw_Do:
		advance(c)
		push_scope(c)
		c.loop_depth += 1
		body := parse_statement(c)
		c.loop_depth -= 1
		pop_scope(c)
		expect(c, .Kw_While, "'while'")
		expect(c, .LParen, "'('")
		cond := parse_condition(c, "'while'")
		expect(c, .RParen, "')'")
		expect(c, .Semicolon, "';'")
		return new_stmt(c, Stmt { kind = .Do_While, expr = cond, body = body, file = tok.file, line = tok.line })

	case .Kw_Return:
		advance(c)
		value: Expr_Index
		return_type := c.funcs[c.cur_func].return_type

		if peek(c) != .Semicolon {
			value = parse_expr(c)

			if c.failed {
				return 0
			}

			if return_type == T_VOID {
				compile_error(c, tok.file, tok.line, "This function returns nothing")
				return 0
			}

			value = convert_to(c, value, return_type, "returned value")
		} else if return_type != T_VOID {
			compile_error(c, tok.file, tok.line, "This function must return a '%s'", type_name(c, return_type))
			return 0
		}

		expect(c, .Semicolon, "';'")
		return new_stmt(c, Stmt { kind = .Return, expr = value, file = tok.file, line = tok.line })

	case .Kw_Break, .Kw_Continue:
		advance(c)

		if c.loop_depth == 0 && (tok.kind == .Kw_Continue || c.switch_depth == 0) {
			compile_error(c, tok.file, tok.line, "'%s' can only be used inside a loop", tok.text)
			return 0
		}

		expect(c, .Semicolon, "';'")
		return new_stmt(c, Stmt { kind = tok.kind == .Kw_Break ? .Break : .Continue, file = tok.file, line = tok.line })

	case .Kw_Discard:
		advance(c)
		expect(c, .Semicolon, "';'")
		mark_fragment_only(c, tok)
		return new_stmt(c, Stmt { kind = .Discard, file = tok.file, line = tok.line })

	case .Kw_Switch:
		advance(c)
		expect(c, .LParen, "'('")
		selector := parse_expr(c)
		expect(c, .RParen, "')'")
		expect(c, .LBrace, "'{'")

		if c.failed {
			return 0
		}

		selector_type := c.exprs[selector].type

		if selector_type != T_INT && selector_type != T_UINT {
			compile_error(c, tok.file, tok.line, "A switch needs an int but got '%s'", type_name(c, selector_type))
			return 0
		}

		push_scope(c)
		c.switch_depth += 1
		first := Stmt_Index(0)
		last := Stmt_Index(0)
		values := make([dynamic]i64, 0, 8, c.allocator)
		has_default := false

		for peek(c) != .RBrace && peek(c) != .EOF && !c.failed {
			label := c.tokens[c.tok]
			s: Stmt_Index

			if label.kind == .Kw_Case {
				advance(c)
				value := parse_ternary(c)
				expect(c, .Colon, "':'")

				if c.failed {
					break
				}

				if c.exprs[value].kind != .Literal || !can_convert(c, c.exprs[value].type, selector_type) {
					compile_error(c, label.file, label.line, "A case needs a constant of the same type as the switch")
					break
				}

				for v in values {
					if v == c.exprs[value].ival {
						compile_error(c, label.file, label.line, "The case %d appears twice", v)
					}
				}

				append(&values, c.exprs[value].ival)
				s = new_stmt(c, Stmt { kind = .Case, expr = make_cast(c, value, selector_type), file = label.file, line = label.line })
			} else if label.kind == .Kw_Default {
				advance(c)
				expect(c, .Colon, "':'")

				if has_default {
					compile_error(c, label.file, label.line, "The switch already has a default")
				}

				has_default = true
				s = new_stmt(c, Stmt { kind = .Default, file = label.file, line = label.line })
			} else {
				if first == 0 {
					compile_error(c, label.file, label.line, "A switch must start with 'case' or 'default'")
					break
				}

				s = parse_statement(c)
			}

			if c.failed || s == 0 {
				continue
			}

			if first == 0 {
				first = s
			} else {
				c.stmts[last].next = s
			}

			last = s

			for c.stmts[last].next != 0 {
				last = c.stmts[last].next
			}
		}

		close := expect(c, .RBrace, "'}'")
		c.switch_depth -= 1
		pop_scope(c)

		if c.failed {
			return 0
		}

		if last != 0 && (c.stmts[last].kind == .Case || c.stmts[last].kind == .Default) {
			compile_error(c, close.file, close.line, "The last case of the switch has no statements. Add a 'break;'")
			return 0
		}

		return new_stmt(c, Stmt { kind = .Switch, expr = selector, first = first, file = tok.file, line = tok.line })

	case .Kw_Case, .Kw_Default:
		compile_error(c, tok.file, tok.line, "'%s' can only be used inside a switch", tok.text)
		return 0

	case .Kw_Struct:
		compile_error(c, tok.file, tok.line, "Structs must be declared outside of functions")
		return 0
	}

	if is_declaration_start(c) {
		s := parse_local_decl(c)
		expect(c, .Semicolon, "';'")
		return s
	}

	e := parse_expr(c)
	expect(c, .Semicolon, "';'")
	return new_stmt(c, Stmt { kind = .Expr, expr = e, file = tok.file, line = tok.line })
}

mark_fragment_only :: proc(c: ^Compiler, tok: Token) {
	if c.cur_func == 0 {
		return
	}

	f := &c.funcs[c.cur_func]

	if f.fragment_only {
		return
	}

	f.fragment_only = true
	f.fragment_only_file = tok.file
	f.fragment_only_line = tok.line
	f.fragment_only_what = tok.text
}

mark_expr :: proc(c: ^Compiler, e: Expr_Index, stage: Stage) {
	if e == 0 {
		return
	}

	ex := c.exprs[e]

	if ex.kind == .Var {
		c.vars[ex.var].used += { stage }
		v := c.vars[ex.var]

		if v.kind == .Builtin {
			vertex_only := v.builtin == .Position || v.builtin == .Vertex_ID || v.builtin == .Instance_ID

			if vertex_only != (stage == .Vertex) {
				compile_error(c, ex.file, ex.line, "'%s' cannot be used in this stage", v.name)
			}
		}

		if v.kind == .Global && v.init != 0 && stage not_in v.used_init {
			c.vars[ex.var].used_init += { stage }
			mark_expr(c, v.init, stage)
		}

		return
	}

	if ex.kind == .Call {
		mark_func(c, ex.func, stage, ex.file, ex.line)
	}

	mark_expr(c, ex.a, stage)
	mark_expr(c, ex.b, stage)
	mark_expr(c, ex.c, stage)

	for i in 0..<ex.args_count {
		mark_expr(c, c.expr_args[ex.args_start + i], stage)
	}
}

mark_stmt :: proc(c: ^Compiler, first: Stmt_Index, stage: Stage) {
	s := first

	for s != 0 && !c.failed {
		st := c.stmts[s]
		mark_expr(c, st.expr, stage)
		mark_expr(c, st.post, stage)
		mark_stmt(c, st.first, stage)
		mark_stmt(c, st.body, stage)
		mark_stmt(c, st.else_body, stage)
		s = st.next
	}
}

mark_func :: proc(c: ^Compiler, fi: Func_Index, stage: Stage, file: u16, line: i32) {
	f := c.funcs[fi]

	if stage in f.visiting {
		compile_error(c, file, line, "'%s' ends up calling itself, recursion is not allowed", f.name)
		return
	}

	if stage in f.used {
		return
	}

	if !f.has_body {
		compile_error(c, file, line, "The function '%s' is declared but has no body", f.name)
		return
	}

	if f.fragment_only && stage == .Vertex {
		compile_error(c, f.fragment_only_file, f.fragment_only_line, "'%s' only works in the fragment stage, but the function '%s' is used by the vertex stage", f.fragment_only_what, f.name)
		return
	}

	c.funcs[fi].used += { stage }
	c.funcs[fi].visiting += { stage }
	mark_stmt(c, f.body, stage)
	c.funcs[fi].visiting -= { stage }
}

finish_program :: proc(c: ^Compiler) {
	last := c.tokens[len(c.tokens) - 1]

	for stage in ([2]Stage { .Vertex, .Fragment }) {
		if c.main_funcs[stage] == 0 {
			compile_error(c, 0, last.line, "The %s stage has no 'void main()'. Put it after %s", stage == .Vertex ? "vertex" : "fragment", stage == .Vertex ? "#vertex" : "#fragment")
			return
		}

		mark_func(c, c.main_funcs[stage], stage, 0, 0)

		if c.failed {
			return
		}
	}

	if c.frag_output == 0 {
		compile_error(c, 0, last.line, "The fragment stage has no output. Declare one such as 'out vec4 final_color;'")
		return
	}

	offset := 0

	for u in c.uniforms {
		size, align := type_std140_layout(c, c.vars[u].type)
		offset = (offset + align - 1) / align * align
		c.vars[u].offset = i32(offset)
		offset += size
	}

	c.constants_size = (offset + 15) / 16 * 16
	used_locations: bit_set[0..<32]

	for i in c.inputs {
		v := c.vars[i]

		if v.location == -1 {
			continue
		}

		if v.location >= 32 || int(v.location) in used_locations {
			compile_error(c, v.file, v.line, "The location of '%s' is already used or too large", v.name)
			return
		}

		used_locations += { int(v.location) }
	}

	next_location := 0

	for i in c.inputs {
		if c.vars[i].location != -1 {
			continue
		}

		for (next_location in used_locations) {
			next_location += 1
		}

		if next_location >= 32 {
			compile_error(c, c.vars[i].file, c.vars[i].line, "Too many vertex inputs")
			return
		}

		c.vars[i].location = i32(next_location)
		used_locations += { next_location }
	}
}
