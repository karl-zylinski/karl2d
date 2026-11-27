package karl2d_shader_compiler

import "core:math"

opt_const :: proc(c: ^Compiler, e: Expr_Index, vals: ^[4]Const_Scalar) -> (count: int, ok: bool) {
	ex := c.exprs[e]
	ty := c.types[ex.type]

	if ex.kind == .Literal {
		vals[0] = { ty.scalar, ex.ival, ex.fval }
		return 1, true
	}

	if ex.kind != .Construct || ty.kind != .Vector {
		return 0, false
	}

	if int(ex.args_count) != int(ty.size) {
		return 0, false
	}

	for i in 0..<ex.args_count {
		arg := c.exprs[c.expr_args[ex.args_start + i]]

		if arg.kind != .Literal || arg.type != type_vec(ty.scalar, 1) {
			return 0, false
		}

		vals[i] = { ty.scalar, arg.ival, arg.fval }
	}

	return int(ty.size), true
}

opt_make :: proc(c: ^Compiler, type: Type_Index, vals: []Const_Scalar, file: u16, line: i32) -> Expr_Index {
	if len(vals) == 1 {
		return new_literal(c, type, vals[0].ival, vals[0].fval, file, line)
	}

	part := type_vec(c.types[type].scalar, 1)
	parts: [4]Expr_Index

	for v, i in vals {
		parts[i] = new_literal(c, part, v.ival, v.fval, file, line)
	}

	args_start := i32(len(c.expr_args))
	append(&c.expr_args, ..parts[:len(vals)])

	return new_expr(c, Expr {
		kind = .Construct,
		type = type,
		args_start = args_start,
		args_count = i32(len(vals)),
		file = file,
		line = line,
	})
}

opt_splat_value :: proc(c: ^Compiler, e: Expr_Index) -> (value: f64, ok: bool) {
	vals: [4]Const_Scalar
	count := opt_const(c, e, &vals) or_return

	if vals[0].scalar != .Float {
		return 0, false
	}

	for v in vals[:count] {
		if v.fval != vals[0].fval {
			return 0, false
		}
	}

	return vals[0].fval, true
}

opt_var_is_const :: proc(c: ^Compiler, vi: Var_Index) -> bool {
	v := c.vars[vi]

	if v.kind != .Local && v.kind != .Global {
		return false
	}

	if v.init == 0 {
		return false
	}

	return v.is_const || !v.written
}

opt_component :: proc(c: ^Compiler, e: Expr_Index, i: int) -> Expr_Index {
	ex := c.exprs[e]

	if ex.kind == .Literal {
		return e
	}

	return c.expr_args[int(ex.args_start) + i]
}

opt_binary :: proc(c: ^Compiler, e: Expr_Index) -> Expr_Index {
	ex := c.exprs[e]
	a := c.exprs[ex.a]
	b := c.exprs[ex.b]

	if ex.op == .And_And || ex.op == .Or_Or {
		keeps := ex.op == .And_And ? i64(1) : i64(0)

		if a.kind == .Literal {
			return a.ival == keeps ? ex.b : ex.a
		}

		if b.kind == .Literal && b.ival == keeps {
			return ex.a
		}

		if b.kind == .Literal && expr_is_pure(c, ex.a) {
			return ex.b
		}

		return e
	}

	va: [4]Const_Scalar
	vb: [4]Const_Scalar
	na, a_ok := opt_const(c, ex.a, &va)
	nb, b_ok := opt_const(c, ex.b, &vb)

	if !a_ok || !b_ok {
		return e
	}

	result := c.types[ex.type]
	n := max(na, nb)

	if result.kind != .Scalar && result.kind != .Vector {
		return e
	}

	if int(result.size) != n {
		return e
	}

	part := type_vec(result.scalar, 1)
	vals: [4]Const_Scalar

	for i in 0..<n {
		folded, ok := fold_binary(c, ex.op, opt_component(c, ex.a, na == 1 ? 0 : i), opt_component(c, ex.b, nb == 1 ? 0 : i), part)

		if !ok {
			return e
		}

		lit := c.exprs[folded]
		vals[i] = { result.scalar, lit.ival, lit.fval }
	}

	return opt_make(c, ex.type, vals[:n], ex.file, ex.line)
}

opt_builtin :: proc(c: ^Compiler, e: Expr_Index) -> Expr_Index {
	ex := c.exprs[e]

	if ex.args_count > 3 {
		return e
	}

	v: [3][4]f32
	size := 0

	for i in 0..<ex.args_count {
		vals: [4]Const_Scalar
		count, ok := opt_const(c, c.expr_args[ex.args_start + i], &vals)

		if !ok {
			return e
		}

		if vals[0].scalar != .Float {
			return e
		}

		for j in 0..<4 {
			v[i][j] = f32(vals[j % count].fval)
		}

		size = max(size, count)
	}

	x := v[0]
	y := v[1]
	z := v[2]
	r: [4]f32
	out := size

	#partial switch ex.builtin {
	case .Dot, .Length, .Distance, .Normalize:
		sum := f32(0)

		for i in 0..<size {
			d := ex.builtin == .Distance ? x[i] - y[i] : x[i]
			sum += d * (ex.builtin == .Dot ? y[i] : d)
		}

		out = 1
		r[0] = ex.builtin == .Dot ? sum : math.sqrt(sum)

		if ex.builtin == .Normalize {
			out = size

			for i in 0..<size {
				r[i] = x[i] / math.sqrt(sum)
			}
		}

	case .Cross:
		r = { x[1] * y[2] - y[1] * x[2], x[2] * y[0] - y[2] * x[0], x[0] * y[1] - y[0] * x[1], 0 }

	case:
		for i in 0..<size {
			a := x[i]
			b := y[i]
			d := z[i]

			#partial switch ex.builtin {
			case .Radians: r[i] = a * 0.0174532924
			case .Degrees: r[i] = a * 57.2957802
			case .Sin: r[i] = math.sin(a)
			case .Cos: r[i] = math.cos(a)
			case .Tan: r[i] = math.tan(a)
			case .Pow: r[i] = math.pow(a, b)
			case .Exp: r[i] = math.exp(a)
			case .Log: r[i] = math.ln(a)
			case .Exp2: r[i] = math.pow(f32(2), a)
			case .Log2: r[i] = math.log2(a)
			case .Sqrt: r[i] = math.sqrt(a)
			case .Inversesqrt: r[i] = 1 / math.sqrt(a)
			case .Abs: r[i] = abs(a)
			case .Sign: r[i] = a > 0 ? 1 : a < 0 ? -1 : 0
			case .Floor: r[i] = math.floor(a)
			case .Ceil: r[i] = math.ceil(a)
			case .Fract: r[i] = a - math.floor(a)
			case .Mod: r[i] = a - b * math.floor(a / b)
			case .Min: r[i] = min(a, b)
			case .Max: r[i] = max(a, b)
			case .Clamp: r[i] = min(max(a, b), d)
			case .Mix: r[i] = a * (1 - d) + b * d
			case .Step: r[i] = b < a ? 0 : 1

			case .Smoothstep:
				t := min(max((d - a) / (b - a), 0), 1)
				r[i] = t * t * (3 - 2 * t)

			case:
				return e
			}
		}
	}

	if type_component_count(c, ex.type) != out {
		return e
	}

	vals: [4]Const_Scalar

	for i in 0..<out {
		class := math.classify(r[i])

		if class == .NaN || class == .Inf || class == .Neg_Inf {
			return e
		}

		vals[i] = { .Float, 0, f64(r[i]) }
	}

	return opt_make(c, ex.type, vals[:out], ex.file, ex.line)
}

opt_expr :: proc(c: ^Compiler, e: Expr_Index) -> Expr_Index {
	if e == 0 {
		return 0
	}

	ex := c.exprs[e]
	vals: [4]Const_Scalar

	if ex.kind == .Literal {
		return e
	}

	if ex.kind == .Var {
		if !opt_var_is_const(c, ex.var) {
			return e
		}

		init := c.vars[ex.var].init

		if _, ok := opt_const(c, init, &vals); ok {
			return init
		}

		return e
	}

	if ex.kind == .Index {
		ex.b = opt_expr(c, ex.b)
		c.exprs[e].b = ex.b
		index := c.exprs[ex.b]
		root := c.exprs[expr_root(c, ex.a)]
		const_root := root.kind == .Var && opt_var_is_const(c, root.var)

		if index.kind != .Literal {
			if const_root {
				c.vars[root.var].keep_decl = true
			} else {
				c.exprs[e].a = opt_expr(c, ex.a)
			}

			if c.types[c.exprs[ex.a].type].kind != .Vector {
				mark_dynamic_index(c, ex.a)
			}

			return e
		}

		base := c.exprs[ex.a]

		if base.kind == .Var && const_root {
			init := c.exprs[c.vars[base.var].init]

			if init.kind == .Construct && c.types[init.type].kind == .Array && int(init.args_count) == int(c.types[init.type].len) {
				element := c.expr_args[init.args_start + i32(index.ival)]

				if _, ok := opt_const(c, element, &vals); ok {
					return element
				}
			}
		}

		ex.a = opt_expr(c, ex.a)
		c.exprs[e].a = ex.a

		if count, ok := opt_const(c, ex.a, &vals); ok && int(index.ival) < count {
			return opt_make(c, ex.type, vals[index.ival:][:1], ex.file, ex.line)
		}

		return e
	}

	ex.a = opt_expr(c, ex.a)
	ex.b = opt_expr(c, ex.b)
	ex.c = opt_expr(c, ex.c)
	c.exprs[e].a = ex.a
	c.exprs[e].b = ex.b
	c.exprs[e].c = ex.c
	all_const := true

	for i in 0..<ex.args_count {
		arg := opt_expr(c, c.expr_args[ex.args_start + i])
		c.expr_args[ex.args_start + i] = arg

		if _, ok := opt_const(c, arg, &vals); !ok {
			all_const = false
		}
	}

	#partial switch ex.kind {
	case .Binary:
		return opt_binary(c, e)

	case .Unary:
		count, ok := opt_const(c, ex.a, &vals)

		if !ok {
			return e
		}

		if ex.op == .Minus {
			for &v in vals[:count] {
				v.ival = v.scalar == .Uint ? i64(u32(-i32(v.ival))) : i64(-i32(v.ival))
				v.fval = -v.fval
			}

			return opt_make(c, ex.type, vals[:count], ex.file, ex.line)
		}

		if ex.op == .Not && count == 1 {
			vals[0].ival = 1 - vals[0].ival
			return opt_make(c, ex.type, vals[:1], ex.file, ex.line)
		}

	case .Ternary:
		if c.exprs[ex.a].kind == .Literal {
			return c.exprs[ex.a].ival != 0 ? ex.b : ex.c
		}

	case .Swizzle:
		if _, ok := opt_const(c, ex.a, &vals); ok {
			picked: [4]Const_Scalar

			for i in 0..<int(ex.swizzle_count) {
				picked[i] = vals[ex.swizzle[i]]
			}

			return opt_make(c, ex.type, picked[:ex.swizzle_count], ex.file, ex.line)
		}

	case .Construct:
		kind := c.types[ex.type].kind

		if all_const && (kind == .Scalar || kind == .Vector) {
			wide: [16]Const_Scalar
			count := 0

			if const_components(c, e, &wide, &count) {
				return opt_make(c, ex.type, wide[:count], ex.file, ex.line)
			}
		}

	case .Builtin_Call:
		if all_const {
			return opt_builtin(c, e)
		}
	}

	return e
}

opt_stmts :: proc(c: ^Compiler, first: Stmt_Index) {
	s := first

	for s != 0 {
		st := c.stmts[s]
		st.expr = opt_expr(c, st.expr)
		st.post = opt_expr(c, st.post)

		if st.kind == .Decl {
			c.vars[st.var].init = st.expr
		}

		if st.kind == .If && c.exprs[st.expr].kind == .Literal {
			taken := c.exprs[st.expr].ival != 0 ? st.body : st.else_body
			st = Stmt { kind = .Block, first = taken, next = st.next, file = st.file, line = st.line }
		}

		if st.kind == .For {
			init := st.first

			for init != 0 {
				if c.stmts[init].kind == .Decl {
					c.vars[c.stmts[init].var].keep_decl = true
				}

				init = c.stmts[init].next
			}
		}

		c.stmts[s] = st
		opt_stmts(c, st.first)
		opt_stmts(c, st.body)
		opt_stmts(c, st.else_body)
		s = st.next
	}
}

optimize_program :: proc(c: ^Compiler) {
	for &v in c.vars {
		v.dynamic_index = false

		if v.kind == .Global || v.kind == .Uniform {
			v.init = opt_expr(c, v.init)
		}
	}

	for f in c.funcs {
		opt_stmts(c, f.body)
	}

	vals: [4]Const_Scalar

	for &st in c.stmts {
		if st.kind != .Decl || c.vars[st.var].keep_decl || !opt_var_is_const(c, st.var) {
			continue
		}

		if _, ok := opt_const(c, st.expr, &vals); ok {
			st.kind = .None
			st.expr = 0
		}
	}
}
