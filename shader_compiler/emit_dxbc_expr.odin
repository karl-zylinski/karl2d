package karl2d_shader_compiler

dx_pure :: proc(c: ^Compiler, e: Expr_Index) -> bool {
	if e == 0 {
		return true
	}

	ex := c.exprs[e]

	if ex.kind == .Assign || ex.kind == .Call {
		return false
	}

	if ex.kind == .Unary && (ex.op == .Inc || ex.op == .Dec) {
		return false
	}

	if !dx_pure(c, ex.a) || !dx_pure(c, ex.b) || !dx_pure(c, ex.c) {
		return false
	}

	for i in 0..<ex.args_count {
		if !dx_pure(c, c.expr_args[ex.args_start + i]) {
			return false
		}
	}

	return true
}

dx_keep :: proc(g: ^Dx, v: Dx_Value, later: Expr_Index) -> Dx_Value {
	if v.space == .Imm || dx_pure(g.c, later) {
		return v
	}

	t := dx_temp(g, v.type)
	dx_copy(g, t, v)
	return t
}

dx_index_register :: proc(g: ^Dx, index: Dx_Value, scale: u32, base: Dx_Value) -> (reg: u32, comp: u8) {
	t := dx_temp(g, T_INT)

	if scale == 1 {
		dx_ins(g, DX_MOV, t, index)
	} else {
		start := len(g.code)
		append(&g.code, DX_IMUL, 0x0000d000)
		dx_dst(g, t)
		dx_src(g, index, t)
		dx_src(g, dx_imm_u(scale), t)
		dx_end(g, start)
	}

	if base.has_dyn {
		previous := Dx_Value { space = .Temp, reg = base.dyn_reg, count = 1, swizzle = { base.dyn_comp, 0, 0, 0 }, type = T_INT }
		dx_ins(g, DX_IADD, t, t, previous)
	}

	return t.reg, 0
}

dx_place :: proc(g: ^Dx, e: Expr_Index) -> Dx_Value {
	c := g.c
	ex := c.exprs[e]

	#partial switch ex.kind {
	case .Var:
		return dx_var_value(g, ex.var)

	case .Field:
		base := dx_place(g, ex.a)
		field := c.types[c.exprs[ex.a].type].fields[ex.field]
		return dx_sub(g, base, int(field.offset), ex.type)

	case .Swizzle:
		base := dx_place(g, ex.a)

		if base.dyn_component {
			base = dx_load(g, base)
		}

		return dx_swizzle(g, base, ex.swizzle[:ex.swizzle_count])

	case .Index:
		base := dx_place(g, ex.a)
		base_type := c.types[c.exprs[ex.a].type]
		index_expr := c.exprs[ex.b]

		if base_type.kind == .Vector {
			if base.dyn_component {
				base = dx_load(g, base)
			}

			if index_expr.kind == .Literal {
				return dx_swizzle(g, base, { u8(index_expr.ival) })
			}

			index := dx_keep(g, dx_expr(g, ex.b), 0)
			t := dx_temp(g, T_INT)
			dx_ins(g, DX_MOV, t, index)
			r := base
			r.dyn_component = true
			r.component_reg = t.reg
			r.component_comp = 0
			return r
		}

		stride := 16

		if base_type.kind == .Array {
			elem_size, elem_align := type_std140_layout(c, base_type.elem)
			elem_align = max(elem_align, 16)
			stride = (elem_size + elem_align - 1) / elem_align * elem_align
		}

		if index_expr.kind == .Literal {
			return dx_sub(g, base, int(index_expr.ival) * stride, ex.type)
		}

		if base.space != .Indexable && base.space != .Constants {
			scratch := dx_indexable(g, c.exprs[ex.a].type)
			dx_copy(g, scratch, base)
			base = scratch
		}

		index := dx_expr(g, ex.b)
		r := dx_sub(g, base, 0, ex.type)
		r.dyn_reg, r.dyn_comp = dx_index_register(g, index, u32(stride / 16), base)
		r.has_dyn = true
		return r
	}

	return dx_expr(g, e)
}

dx_convert :: proc(g: ^Dx, v: Dx_Value, from: Type_Index, to: Type_Index) -> Dx_Value {
	c := g.c
	fs := c.types[from].scalar
	ts := c.types[to].scalar

	if fs == ts {
		r := v
		r.type = to
		return r
	}

	if fs == .Bool {
		if ts == .Float {
			return dx_new(g, DX_AND, to, v, dx_imm_u(0x3f800000))
		}

		return dx_new(g, DX_AND, to, v, dx_imm_u(1))
	}

	switch ts {
	case .Float:
		return dx_new(g, fs == .Int ? DX_ITOF : DX_UTOF, to, v)

	case .Int:
		if fs == .Float {
			return dx_new(g, DX_FTOI, to, v)
		}

	case .Uint:
		if fs == .Float {
			return dx_new(g, DX_FTOU, to, v)
		}

	case .Bool:
		if fs == .Float {
			return dx_new(g, DX_NE, to, v, dx_imm_f(0))
		}

		return dx_new(g, DX_INE, to, v, dx_imm_u(0))

	case .None:
	}

	r := v
	r.type = to
	return r
}

dx_column :: proc(g: ^Dx, m: Dx_Value, k: int, n: int) -> Dx_Value {
	return dx_reg_at(m, u32(k), n, type_vec(.Float, n))
}

dx_div_int :: proc(g: ^Dx, t: Type_Index, a: Dx_Value, b: Dx_Value, remainder: bool) -> Dx_Value {
	c := g.c
	unsigned := retype(c, t, .Uint)
	abs_a := a
	abs_b := b
	signed := c.types[t].scalar == .Int

	if signed {
		abs_a = dx_new(g, DX_IMAX, unsigned, a, dx_neg(g, a))
		abs_b = dx_new(g, DX_IMAX, unsigned, b, dx_neg(g, b))
	}

	result := dx_temp(g, t)
	start := len(g.code)
	append(&g.code, DX_UDIV)

	if remainder {
		append(&g.code, 0x0000d000)
		dx_dst(g, result)
	} else {
		dx_dst(g, result)
		append(&g.code, 0x0000d000)
	}

	dx_src(g, abs_a, result)
	dx_src(g, abs_b, result)
	dx_end(g, start)

	if !signed {
		return result
	}

	sign: Dx_Value

	if remainder {
		sign = dx_new(g, DX_AND, t, a, dx_imm_u(0x80000000))
	} else {
		sign = dx_new(g, DX_XOR, t, a, b)
		dx_ins(g, DX_AND, sign, sign, dx_imm_u(0x80000000))
	}

	negated := dx_new(g, DX_INEG, t, result)
	return dx_new(g, DX_MOVC, t, sign, negated, result)
}

dx_matrix_times_vector :: proc(g: ^Dx, m: Dx_Value, v: Dx_Value, n: int) -> Dx_Value {
	t := type_vec(.Float, n)
	result := dx_temp(g, t)

	for k in 0..<n {
		column := dx_column(g, m, k, n)
		comp := dx_swizzle(g, v, { u8(k) })

		if k == 0 {
			dx_ins(g, DX_MUL, result, column, comp)
		} else {
			dx_ins(g, DX_MAD, result, column, comp, result)
		}
	}

	return result
}

dx_dot :: proc(g: ^Dx, a: Dx_Value, b: Dx_Value, n: int) -> Dx_Value {
	result := dx_temp(g, T_FLOAT)

	if n == 1 {
		dx_ins(g, DX_MUL, result, a, b)
		return result
	}

	start := len(g.code)
	append(&g.code, u32(DX_DP2 + n - 2))
	dx_dst(g, result)
	dx_src_n(g, a, n)
	dx_src_n(g, b, n)
	dx_end(g, start)
	return result
}

dx_equal :: proc(g: ^Dx, t: Type_Index, a: Dx_Value, b: Dx_Value) -> Dx_Value {
	c := g.c
	ty := c.types[t]

	#partial switch ty.kind {
	case .Scalar, .Vector:
		each := dx_new(g, ty.scalar == .Float ? DX_EQ : DX_IEQ, type_vec(.Bool, int(ty.size)), a, b)
		return dx_reduce(g, each, DX_AND)

	case .Matrix, .Array, .Struct:
		count := ty.kind == .Matrix ? int(ty.size) : ty.kind == .Array ? int(ty.len) : len(ty.fields)
		result: Dx_Value
		stride := 16

		if ty.kind == .Array {
			elem_size, elem_align := type_std140_layout(c, ty.elem)
			elem_align = max(elem_align, 16)
			stride = (elem_size + elem_align - 1) / elem_align * elem_align
		}

		for i in 0..<count {
			part_type: Type_Index
			offset := i * stride

			#partial switch ty.kind {
			case .Matrix:
				part_type = type_vec(.Float, int(ty.size))

			case .Array:
				part_type = ty.elem

			case .Struct:
				part_type = ty.fields[i].type
				offset = int(ty.fields[i].offset)
			}

			same := dx_equal(g, part_type, dx_sub(g, a, offset, part_type), dx_sub(g, b, offset, part_type))

			if i == 0 {
				result = dx_temp(g, T_BOOL)
				dx_ins(g, DX_MOV, result, same)
			} else {
				dx_ins(g, DX_AND, result, result, same)
			}
		}

		return result
	}

	return dx_imm_u(0xffffffff, T_BOOL)
}

dx_binop :: proc(g: ^Dx, op: Token_Kind, t: Type_Index, ta: Type_Index, tb: Type_Index, a: Dx_Value, b: Dx_Value) -> Dx_Value {
	c := g.c
	result := c.types[t]
	at := c.types[ta]
	bt := c.types[tb]

	#partial switch op {
	case .Eq_Eq:
		return dx_equal(g, ta, a, b)

	case .Not_Eq:
		return dx_new(g, DX_NOT, T_BOOL, dx_equal(g, ta, a, b))

	case .And_And:
		return dx_new(g, DX_AND, T_BOOL, a, b)

	case .Or_Or:
		return dx_new(g, DX_OR, T_BOOL, a, b)

	case .Xor_Xor:
		return dx_new(g, DX_XOR, T_BOOL, a, b)

	case .Lt, .Gt, .Le, .Ge:
		less := op == .Lt || op == .Gt
		swap := op == .Gt || op == .Le
		code: u32

		switch at.scalar {
		case .Float: code = less ? DX_LT : DX_GE
		case .Int: code = less ? DX_ILT : DX_IGE
		case .Uint: code = less ? DX_ULT : DX_UGE
		case .Bool, .None:
		}

		if swap {
			return dx_new(g, code, T_BOOL, b, a)
		}

		return dx_new(g, code, T_BOOL, a, b)

	case .Shl:
		return dx_new(g, DX_ISHL, t, a, b)

	case .Shr:
		return dx_new(g, at.scalar == .Int ? DX_ISHR : DX_USHR, t, a, b)

	case .Amp:
		return dx_new(g, DX_AND, t, a, b)

	case .Pipe:
		return dx_new(g, DX_OR, t, a, b)

	case .Caret:
		return dx_new(g, DX_XOR, t, a, b)
	}

	if result.kind == .Matrix {
		n := int(result.size)
		out := dx_temp(g, t)

		if op == .Star && at.kind == .Matrix && bt.kind == .Matrix {
			for k in 0..<n {
				column := dx_matrix_times_vector(g, a, dx_column(g, b, k, n), n)
				dx_ins(g, DX_MOV, dx_column(g, out, k, n), column)
			}

			return out
		}

		for k in 0..<n {
			ca := at.kind == .Matrix ? dx_column(g, a, k, n) : a
			cb := bt.kind == .Matrix ? dx_column(g, b, k, n) : b
			d := dx_column(g, out, k, n)

			#partial switch op {
			case .Plus: dx_ins(g, DX_ADD, d, ca, cb)
			case .Minus: dx_ins(g, DX_ADD, d, ca, dx_neg(g, cb))
			case .Star: dx_ins(g, DX_MUL, d, ca, cb)
			case .Slash: dx_ins(g, DX_DIV, d, ca, cb)
			}
		}

		return out
	}

	if at.kind == .Matrix {
		return dx_matrix_times_vector(g, a, b, int(at.size))
	}

	if bt.kind == .Matrix {
		n := int(bt.size)
		out := dx_temp(g, t)

		for k in 0..<n {
			dx_ins(g, DX_MOV, dx_swizzle(g, out, { u8(k) }), dx_dot(g, a, dx_column(g, b, k, n), n))
		}

		return out
	}

	is_float := result.scalar == .Float

	#partial switch op {
	case .Plus:
		return dx_new(g, is_float ? DX_ADD : DX_IADD, t, a, b)

	case .Minus:
		return dx_new(g, is_float ? DX_ADD : DX_IADD, t, a, dx_neg(g, b))

	case .Star:
		if is_float {
			return dx_new(g, DX_MUL, t, a, b)
		}

		out := dx_temp(g, t)
		start := len(g.code)
		append(&g.code, DX_IMUL, 0x0000d000)
		dx_dst(g, out)
		dx_src(g, a, out)
		dx_src(g, b, out)
		dx_end(g, start)
		return out

	case .Slash:
		if is_float {
			return dx_new(g, DX_DIV, t, a, b)
		}

		return dx_div_int(g, t, a, b, false)

	case .Percent:
		return dx_div_int(g, t, a, b, true)
	}

	return a
}

dx_construct :: proc(g: ^Dx, ex: Expr) -> Dx_Value {
	c := g.c
	ty := c.types[ex.type]
	args := c.expr_args[ex.args_start:ex.args_start + ex.args_count]
	first_type := c.exprs[args[0]].type
	first := c.types[first_type]

	if ty.kind == .Struct || ty.kind == .Array {
		out := dx_temp(g, ex.type)
		stride := 16

		if ty.kind == .Array {
			elem_size, elem_align := type_std140_layout(c, ty.elem)
			elem_align = max(elem_align, 16)
			stride = (elem_size + elem_align - 1) / elem_align * elem_align
		}

		for a, a_idx in args {
			offset := a_idx * stride
			part_type := ty.elem

			if ty.kind == .Struct {
				offset = int(ty.fields[a_idx].offset)
				part_type = ty.fields[a_idx].type
			}

			mark := g.top
			dx_copy(g, dx_sub(g, out, offset, part_type), dx_expr(g, a))
			g.top = mark
		}

		return out
	}

	if len(args) == 1 && (ty.kind == .Scalar || ty.kind == .Vector) && first.kind == ty.kind && first.size == ty.size {
		return dx_convert(g, dx_expr(g, args[0]), first_type, ex.type)
	}

	if len(args) == 1 && ty.kind == .Vector && first.kind == .Scalar {
		value := dx_expr(g, args[0])
		out := dx_temp(g, ex.type)
		dx_ins(g, DX_MOV, out, value)
		return out
	}

	if ty.kind == .Vector {
		out := dx_temp(g, ex.type)
		at := 0

		for a in args {
			value := dx_expr(g, a)
			arg_type := c.types[c.exprs[a].type]

			if arg_type.kind == .Matrix {
				m := int(arg_type.size)

				for i in 0..<m * m {
					if at >= int(ty.size) {
						break
					}

					dx_ins(g, DX_MOV, dx_swizzle(g, out, { u8(at) }), dx_element(g, value, i / m, i % m, m))
					at += 1
				}

				continue
			}

			take := min(int(value.count), int(ty.size) - at)

			if take <= 0 {
				break
			}

			comps: [4]u8

			for i in 0..<take {
				comps[i] = u8(at + i)
			}

			source := value

			if take < int(value.count) {
				first_comps := [4]u8 { 0, 1, 2, 3 }
				source = dx_swizzle(g, value, first_comps[:take])
			}

			dx_ins(g, DX_MOV, dx_swizzle(g, out, comps[:take]), source)
			at += take
		}

		return out
	}

	n := int(ty.size)
	out := dx_temp(g, ex.type)

	if len(args) == 1 && first.kind == .Matrix {
		source := dx_expr(g, args[0])
		m := int(first.size)

		for col in 0..<n {
			d := dx_column(g, out, col, n)
			identity := dx_imm4(0, 0, 0, 0, T_VEC4)
			identity.imm[col] = transmute(u32)f32(1)
			dx_ins(g, DX_MOV, d, identity)

			if col < m {
				keep := min(n, m)
				comps := [4]u8 { 0, 1, 2, 3 }
				dx_ins(g, DX_MOV, dx_swizzle(g, d, comps[:keep]), dx_swizzle(g, dx_column(g, source, col, m), comps[:keep]))
			}
		}

		return out
	}

	if len(args) == 1 && first.kind == .Scalar {
		value := dx_expr(g, args[0])

		for col in 0..<n {
			d := dx_column(g, out, col, n)
			dx_ins(g, DX_MOV, d, dx_imm_f(0))
			dx_ins(g, DX_MOV, dx_swizzle(g, d, { u8(col) }), value)
		}

		return out
	}

	at := 0

	for a in args {
		value := dx_expr(g, a)

		for i in 0..<int(value.count) {
			if at >= n * n {
				break
			}

			d := dx_swizzle(g, dx_column(g, out, at / n, n), { u8(at % n) })
			dx_ins(g, DX_MOV, d, dx_swizzle(g, value, { u8(i) }))
			at += 1
		}
	}

	return out
}

dx_element :: proc(g: ^Dx, m: Dx_Value, col: int, row: int, n: int) -> Dx_Value {
	return dx_swizzle(g, dx_column(g, m, col, n), { u8(row) })
}

dx_determinant :: proc(g: ^Dx, m: Dx_Value, n: int, rows: []int, cols: []int) -> Dx_Value {
	size := len(rows)

	if size == 1 {
		return dx_element(g, m, cols[0], rows[0], n)
	}

	if size == 2 {
		a := dx_element(g, m, cols[0], rows[0], n)
		b := dx_element(g, m, cols[1], rows[0], n)
		cc := dx_element(g, m, cols[0], rows[1], n)
		d := dx_element(g, m, cols[1], rows[1], n)
		bc := dx_new(g, DX_MUL, T_FLOAT, b, cc)
		return dx_new(g, DX_MAD, T_FLOAT, a, d, dx_neg(g, bc))
	}

	result := dx_temp(g, T_FLOAT)
	sub_cols: [3]int

	for k in 0..<size {
		at := 0

		for j in 0..<size {
			if j != k {
				sub_cols[at] = cols[j]
				at += 1
			}
		}

		minor := dx_determinant(g, m, n, rows[1:], sub_cols[:size - 1])
		entry := dx_element(g, m, cols[k], rows[0], n)

		if k % 2 == 1 {
			entry = dx_neg(g, entry)
		}

		if k == 0 {
			dx_ins(g, DX_MUL, result, entry, minor)
		} else {
			dx_ins(g, DX_MAD, result, entry, minor, result)
		}
	}

	return result
}

dx_inverse :: proc(g: ^Dx, m: Dx_Value, n: int, t: Type_Index) -> Dx_Value {
	all := [4]int { 0, 1, 2, 3 }
	out := dx_temp(g, t)
	det := dx_determinant(g, m, n, all[:n], all[:n])
	inv_det := dx_new(g, DX_DIV, T_FLOAT, dx_imm_f(1), det)
	sub_rows: [3]int
	sub_cols: [3]int

	for col in 0..<n {
		for row in 0..<n {
			at := 0

			for k in 0..<n {
				if k != col {
					sub_rows[at] = k
					at += 1
				}
			}

			at = 0

			for k in 0..<n {
				if k != row {
					sub_cols[at] = k
					at += 1
				}
			}

			mark := g.top
			cofactor := n == 1 ? dx_imm_f(1) : dx_determinant(g, m, n, sub_rows[:n - 1], sub_cols[:n - 1])

			if (row + col) % 2 == 1 {
				cofactor = dx_neg(g, cofactor)
			}

			dx_ins(g, DX_MUL, dx_element(g, out, col, row, n), cofactor, inv_det)
			g.top = mark
		}
	}

	return out
}

dx_atan :: proc(g: ^Dx, t: Type_Index, y: Dx_Value, x: Dx_Value, two_args: bool) -> Dx_Value {
	bool_type := retype(g.c, t, .Bool)
	abs_x := dx_abs(x)
	abs_y := two_args ? dx_abs(y) : dx_imm_f(1)
	r := dx_new(g, DX_MAX, t, abs_x, abs_y)
	dx_ins(g, DX_DIV, r, dx_imm_f(1), r)
	smaller := dx_new(g, DX_MIN, t, abs_x, abs_y)
	dx_ins(g, DX_MUL, r, r, smaller)
	s := dx_new(g, DX_MUL, t, r, r)
	z := dx_new(g, DX_MAD, t, s, dx_imm_f(0.0208351), dx_imm_f(-0.085133))
	dx_ins(g, DX_MAD, z, s, z, dx_imm_f(0.180141))
	dx_ins(g, DX_MAD, z, s, z, dx_imm_f(-0.3302995))
	dx_ins(g, DX_MAD, s, s, z, dx_imm_f(0.999866))
	dx_ins(g, DX_MUL, z, s, r)
	dx_ins(g, DX_MAD, z, z, dx_imm_f(-2), dx_imm_f(1.57079637))
	w: Dx_Value

	if two_args {
		w = dx_new(g, DX_LT, bool_type, abs_x, abs_y)
	} else {
		w = dx_new(g, DX_LT, bool_type, dx_imm_f(1), abs_x)
	}

	dx_ins(g, DX_AND, z, w, z)
	dx_ins(g, DX_MAD, r, r, s, z)

	if !two_args {
		low := dx_new(g, DX_MIN, t, x, dx_imm_f(1))
		dx_ins(g, DX_LT, w, low, dx_neg(g, low))
		return dx_new(g, DX_MOVC, t, w, dx_neg(g, r), r)
	}

	dx_ins(g, DX_LT, w, x, dx_neg(g, x))
	dx_ins(g, DX_AND, w, w, dx_imm_u(0xc0490fdb))
	dx_ins(g, DX_ADD, r, w, r)
	low := dx_new(g, DX_MIN, t, x, y)
	a := dx_new(g, DX_LT, bool_type, low, dx_neg(g, low))
	high := dx_new(g, DX_MAX, t, x, y)
	b := dx_new(g, DX_GE, bool_type, high, dx_neg(g, high))
	dx_ins(g, DX_AND, a, b, a)
	return dx_new(g, DX_MOVC, t, a, dx_neg(g, r), r)
}

dx_acos :: proc(g: ^Dx, t: Type_Index, x: Dx_Value) -> Dx_Value {
	bool_type := retype(g.c, t, .Bool)
	abs_x := dx_abs(x)
	r := dx_new(g, DX_MAD, t, abs_x, dx_imm_f(-0.0187293), dx_imm_f(0.0742610))
	dx_ins(g, DX_MAD, r, r, abs_x, dx_imm_f(-0.2121144))
	dx_ins(g, DX_MAD, r, r, abs_x, dx_imm_f(1.5707288))
	y := dx_new(g, DX_ADD, t, dx_neg(g, abs_x), dx_imm_f(1))
	dx_ins(g, DX_SQRT, y, y)
	z := dx_new(g, DX_MUL, t, y, r)
	dx_ins(g, DX_MAD, z, z, dx_imm_f(-2), dx_imm_f(3.14159274))
	w := dx_new(g, DX_LT, bool_type, x, dx_neg(g, x))
	dx_ins(g, DX_AND, z, w, z)
	dx_ins(g, DX_MAD, r, r, y, z)
	return r
}

dx_sample :: proc(g: ^Dx, opcode: u32, texture: Dx_Value, coord: Dx_Value, extra: Dx_Value, has_extra: bool) -> Dx_Value {
	out := dx_temp(g, T_VEC4)
	g.textures_used += { int(texture.reg) }
	start := len(g.code)
	append(&g.code, opcode)
	dx_dst(g, out)
	dx_src_n(g, coord, 2)
	append(&g.code, 0x00107e46, texture.reg, 0x00106000, texture.reg)

	if has_extra {
		dx_src_n(g, extra, 1)
	}

	dx_end(g, start)
	return out
}

dx_builtin :: proc(g: ^Dx, ex: Expr) -> Dx_Value {
	c := g.c
	arg_exprs := c.expr_args[ex.args_start:ex.args_start + ex.args_count]
	t := ex.type
	a: [3]Dx_Value
	at: [3]Type_Index

	for arg, i in arg_exprs {
		at[i] = c.exprs[arg].type

		if at[i] == T_SAMPLER_2D {
			a[i] = dx_place(g, arg)
			continue
		}

		value := dx_expr(g, arg)

		for later in arg_exprs[i + 1:] {
			value = dx_keep(g, value, later)
		}

		a[i] = value
	}

	scalar := c.types[at[0]].scalar
	n := int(c.types[at[0]].size)
	bool_type := retype(c, t, .Bool)

	switch ex.builtin {
	case .None:

	case .Radians:
		return dx_new(g, DX_MUL, t, a[0], dx_imm_f(0.0174532924))

	case .Degrees:
		return dx_new(g, DX_MUL, t, a[0], dx_imm_f(57.2957802))

	case .Sin, .Cos, .Tan:
		sine := dx_temp(g, t)
		cosine := dx_temp(g, t)
		start := len(g.code)
		append(&g.code, DX_SINCOS)
		dx_dst(g, sine)
		dx_dst(g, cosine)
		dx_src(g, a[0], sine)
		dx_end(g, start)

		if ex.builtin == .Sin {
			return sine
		}

		if ex.builtin == .Cos {
			return cosine
		}

		return dx_new(g, DX_DIV, t, sine, cosine)

	case .Asin:
		r := dx_acos(g, t, a[0])
		return dx_new(g, DX_ADD, t, dx_neg(g, r), dx_imm_f(1.57079637))

	case .Acos:
		return dx_acos(g, t, a[0])

	case .Atan:
		if len(arg_exprs) == 2 {
			return dx_atan(g, t, a[0], a[1], true)
		}

		return dx_atan(g, t, a[0], a[0], false)

	case .Sinh, .Cosh, .Tanh:
		scaled := dx_new(g, DX_MUL, t, a[0], dx_imm_f(1.44269502))
		grow := dx_new(g, DX_EXP, t, scaled)
		shrink := dx_new(g, DX_EXP, t, dx_neg(g, scaled))
		sum := dx_new(g, DX_ADD, t, grow, shrink)
		diff := dx_new(g, DX_ADD, t, grow, dx_neg(g, shrink))

		if ex.builtin == .Sinh {
			return dx_new(g, DX_MUL, t, diff, dx_imm_f(0.5))
		}

		if ex.builtin == .Cosh {
			return dx_new(g, DX_MUL, t, sum, dx_imm_f(0.5))
		}

		return dx_new(g, DX_DIV, t, diff, sum)

	case .Pow:
		r := dx_new(g, DX_LOG, t, a[0])
		dx_ins(g, DX_MUL, r, r, a[1])
		dx_ins(g, DX_EXP, r, r)
		return r

	case .Exp:
		r := dx_new(g, DX_MUL, t, a[0], dx_imm_f(1.44269502))
		dx_ins(g, DX_EXP, r, r)
		return r

	case .Log:
		r := dx_new(g, DX_LOG, t, a[0])
		dx_ins(g, DX_MUL, r, r, dx_imm_f(0.693147182))
		return r

	case .Exp2:
		return dx_new(g, DX_EXP, t, a[0])

	case .Log2:
		return dx_new(g, DX_LOG, t, a[0])

	case .Sqrt:
		return dx_new(g, DX_SQRT, t, a[0])

	case .Inversesqrt:
		return dx_new(g, DX_RSQ, t, a[0])

	case .Abs:
		if scalar == .Float {
			return dx_new(g, DX_MOV, t, dx_abs(a[0]))
		}

		return dx_new(g, DX_IMAX, t, a[0], dx_neg(g, a[0]))

	case .Sign:
		is_float := scalar == .Float
		positive := dx_new(g, is_float ? DX_LT : DX_ILT, bool_type, is_float ? dx_imm_f(0) : dx_imm_u(0), a[0])
		negative := dx_new(g, is_float ? DX_LT : DX_ILT, bool_type, a[0], is_float ? dx_imm_f(0) : dx_imm_u(0))
		positive.type = retype(c, t, .Int)
		negative.type = positive.type
		r := dx_new(g, DX_IADD, retype(c, t, .Int), dx_neg(g, positive), negative)

		if is_float {
			return dx_new(g, DX_ITOF, t, r)
		}

		return r

	case .Floor:
		return dx_new(g, DX_ROUND_NI, t, a[0])

	case .Trunc:
		return dx_new(g, DX_ROUND_Z, t, a[0])

	case .Round:
		return dx_new(g, DX_ROUND_NE, t, a[0])

	case .Ceil:
		return dx_new(g, DX_ROUND_PI, t, a[0])

	case .Fract:
		return dx_new(g, DX_FRC, t, a[0])

	case .Mod:
		r := dx_new(g, DX_DIV, t, a[0], a[1])
		dx_ins(g, DX_ROUND_NI, r, r)
		dx_ins(g, DX_MAD, r, dx_neg(g, r), a[1], a[0])
		return r

	case .Min:
		return dx_new(g, scalar == .Float ? DX_MIN : scalar == .Int ? DX_IMIN : DX_UMIN, t, a[0], a[1])

	case .Max:
		return dx_new(g, scalar == .Float ? DX_MAX : scalar == .Int ? DX_IMAX : DX_UMAX, t, a[0], a[1])

	case .Clamp:
		r := dx_new(g, scalar == .Float ? DX_MAX : scalar == .Int ? DX_IMAX : DX_UMAX, t, a[0], a[1])
		dx_ins(g, scalar == .Float ? DX_MIN : scalar == .Int ? DX_IMIN : DX_UMIN, r, r, a[2])
		return r

	case .Mix:
		if c.types[at[2]].scalar == .Bool {
			return dx_new(g, DX_MOVC, t, a[2], a[1], a[0])
		}

		r := dx_new(g, DX_ADD, t, a[1], dx_neg(g, a[0]))
		dx_ins(g, DX_MAD, r, a[2], r, a[0])
		return r

	case .Step:
		r := dx_new(g, DX_GE, t, a[1], a[0])
		dx_ins(g, DX_AND, r, r, dx_imm_u(0x3f800000))
		return r

	case .Smoothstep:
		range := dx_new(g, DX_ADD, t, a[1], dx_neg(g, a[0]))
		r := dx_new(g, DX_ADD, t, a[2], dx_neg(g, a[0]))
		dx_ins(g, DX_DIV, r, r, range)
		dx_ins(g, DX_MAX, r, r, dx_imm_f(0))
		dx_ins(g, DX_MIN, r, r, dx_imm_f(1))
		curve := dx_new(g, DX_MAD, t, r, dx_imm_f(-2), dx_imm_f(3))
		dx_ins(g, DX_MUL, r, r, r)
		dx_ins(g, DX_MUL, r, r, curve)
		return r

	case .Length:
		if n == 1 {
			return dx_new(g, DX_MOV, T_FLOAT, dx_abs(a[0]))
		}

		r := dx_dot(g, a[0], a[0], n)
		dx_ins(g, DX_SQRT, r, r)
		return r

	case .Distance:
		diff := dx_new(g, DX_ADD, at[0], a[0], dx_neg(g, a[1]))

		if n == 1 {
			return dx_new(g, DX_MOV, T_FLOAT, dx_abs(diff))
		}

		r := dx_dot(g, diff, diff, n)
		dx_ins(g, DX_SQRT, r, r)
		return r

	case .Dot:
		return dx_dot(g, a[0], a[1], n)

	case .Cross:
		left := dx_new(g, DX_MUL, t, dx_swizzle(g, a[0], { 2, 0, 1 }), dx_swizzle(g, a[1], { 1, 2, 0 }))
		return dx_new(g, DX_MAD, t, dx_swizzle(g, a[0], { 1, 2, 0 }), dx_swizzle(g, a[1], { 2, 0, 1 }), dx_neg(g, left))

	case .Normalize:
		d := dx_dot(g, a[0], a[0], n)
		dx_ins(g, DX_RSQ, d, d)
		return dx_new(g, DX_MUL, t, a[0], d)

	case .Reflect:
		d := dx_dot(g, a[1], a[0], n)
		dx_ins(g, DX_ADD, d, d, d)
		return dx_new(g, DX_MAD, t, a[1], dx_neg(g, d), a[0])

	case .Refract:
		d := dx_dot(g, a[1], a[0], n)
		k := dx_new(g, DX_MAD, T_FLOAT, dx_neg(g, d), d, dx_imm_f(1))
		dx_ins(g, DX_MUL, k, k, a[2])
		dx_ins(g, DX_MAD, k, dx_neg(g, k), a[2], dx_imm_f(1))
		root := dx_new(g, DX_SQRT, T_FLOAT, k)
		dx_ins(g, DX_MAD, root, a[2], d, root)
		r := dx_new(g, DX_MUL, t, a[0], a[2])
		dx_ins(g, DX_MAD, r, dx_neg(g, root), a[1], r)
		valid := dx_new(g, DX_GE, T_BOOL, k, dx_imm_f(0))
		dx_ins(g, DX_AND, r, r, valid)
		return r

	case .Matrix_Comp_Mult:
		out := dx_temp(g, t)

		for k in 0..<n {
			dx_ins(g, DX_MUL, dx_column(g, out, k, n), dx_column(g, a[0], k, n), dx_column(g, a[1], k, n))
		}

		return out

	case .Transpose:
		out := dx_temp(g, t)

		for col in 0..<n {
			for row in 0..<n {
				dx_ins(g, DX_MOV, dx_element(g, out, col, row, n), dx_element(g, a[0], row, col, n))
			}
		}

		return out

	case .Determinant:
		all := [4]int { 0, 1, 2, 3 }
		det := dx_determinant(g, a[0], n, all[:n], all[:n])
		return dx_new(g, DX_MOV, T_FLOAT, det)

	case .Inverse:
		return dx_inverse(g, a[0], n, t)

	case .Less_Than, .Less_Than_Equal, .Greater_Than, .Greater_Than_Equal:
		less := ex.builtin == .Less_Than || ex.builtin == .Greater_Than
		swap := ex.builtin == .Greater_Than || ex.builtin == .Less_Than_Equal
		code: u32

		switch scalar {
		case .Float: code = less ? DX_LT : DX_GE
		case .Int: code = less ? DX_ILT : DX_IGE
		case .Uint: code = less ? DX_ULT : DX_UGE
		case .Bool, .None:
		}

		if swap {
			return dx_new(g, code, t, a[1], a[0])
		}

		return dx_new(g, code, t, a[0], a[1])

	case .Equal:
		return dx_new(g, scalar == .Float ? DX_EQ : DX_IEQ, t, a[0], a[1])

	case .Not_Equal:
		return dx_new(g, scalar == .Float ? DX_NE : DX_INE, t, a[0], a[1])

	case .Any:
		copy := dx_new(g, DX_MOV, at[0], a[0])
		return dx_reduce(g, copy, DX_OR)

	case .All:
		copy := dx_new(g, DX_MOV, at[0], a[0])
		return dx_reduce(g, copy, DX_AND)

	case .Not:
		return dx_new(g, DX_NOT, t, a[0])

	case .Texture:
		if g.stage == .Vertex {
			return dx_sample(g, DX_SAMPLE_L, a[0], a[1], dx_imm_f(0), true)
		}

		if len(arg_exprs) == 3 {
			return dx_sample(g, DX_SAMPLE_B, a[0], a[1], a[2], true)
		}

		return dx_sample(g, DX_SAMPLE, a[0], a[1], {}, false)

	case .Texture_Lod:
		return dx_sample(g, DX_SAMPLE_L, a[0], a[1], a[2], true)

	case .Texel_Fetch:
		coord := dx_temp(g, T_IVEC4)
		dx_ins(g, DX_MOV, coord, dx_imm_u(0))
		dx_ins(g, DX_MOV, dx_swizzle(g, coord, { 0, 1 }), a[1])
		dx_ins(g, DX_MOV, dx_swizzle(g, coord, { 3 }), a[2])
		out := dx_temp(g, T_VEC4)
		g.textures_used += { int(a[0].reg) }
		start := len(g.code)
		append(&g.code, DX_LD)
		dx_dst(g, out)
		dx_src_n(g, coord, 4)
		append(&g.code, 0x00107e46, a[0].reg)
		dx_end(g, start)
		return out

	case .Texture_Size:
		out := dx_temp(g, T_IVEC4)
		g.textures_used += { int(a[0].reg) }
		start := len(g.code)
		append(&g.code, DX_RESINFO | 0x1000)
		dx_dst(g, out)
		dx_src_n(g, a[1], 1)
		append(&g.code, 0x00107e46, a[0].reg)
		dx_end(g, start)
		return dx_swizzle(g, out, { 0, 1 })

	case .DFdx:
		return dx_new(g, DX_DERIV_RTX, t, a[0])

	case .DFdy:
		return dx_new(g, DX_DERIV_RTY, t, a[0])

	case .Fwidth:
		dx := dx_new(g, DX_DERIV_RTX, t, a[0])
		dy := dx_new(g, DX_DERIV_RTY, t, a[0])
		return dx_new(g, DX_ADD, t, dx_abs(dx), dx_abs(dy))
	}

	return a[0]
}

dx_expr :: proc(g: ^Dx, e: Expr_Index) -> Dx_Value {
	c := g.c
	ex := c.exprs[e]

	switch ex.kind {
	case .None:

	case .Literal:
		if c.types[ex.type].scalar == .Float {
			return dx_imm_f(f32(ex.fval))
		}

		if ex.type == T_BOOL {
			return dx_imm_u(ex.ival != 0 ? 0xffffffff : 0, T_BOOL)
		}

		return dx_imm_u(u32(ex.ival), ex.type)

	case .Var, .Index, .Field, .Swizzle:
		return dx_load(g, dx_place(g, e))

	case .Binary:
		short_circuit := ex.op == .And_And || ex.op == .Or_Or

		if short_circuit && !dx_pure(c, ex.b) {
			result := dx_temp(g, T_BOOL)
			dx_ins(g, DX_MOV, result, dx_expr(g, ex.a))
			dx_test(g, ex.op == .And_And ? DX_IF | DX_TEST_NZ : DX_IF, result)
			dx_ins(g, DX_MOV, result, dx_expr(g, ex.b))
			dx_bare(g, DX_ENDIF)
			return result
		}

		a := dx_keep(g, dx_expr(g, ex.a), ex.b)
		b := dx_expr(g, ex.b)
		return dx_binop(g, ex.op, ex.type, c.exprs[ex.a].type, c.exprs[ex.b].type, a, b)

	case .Unary:
		if ex.op == .Inc || ex.op == .Dec {
			loc := dx_place(g, ex.a)
			old := dx_load(g, loc)
			scalar_type := type_vec(c.types[ex.type].scalar, 1)
			one := scalar_type == T_FLOAT ? dx_imm_f(1) : dx_imm_u(1, scalar_type)

			if ex.postfix {
				saved := dx_temp(g, ex.type)
				dx_copy(g, saved, old)
				old = saved
			}

			changed := dx_binop(g, ex.op == .Inc ? .Plus : .Minus, ex.type, ex.type, scalar_type, old, one)
			dx_store(g, loc, changed)
			return ex.postfix ? old : changed
		}

		a := dx_expr(g, ex.a)
		ty := c.types[ex.type]

		#partial switch ex.op {
		case .Not, .Tilde:
			return dx_new(g, DX_NOT, ex.type, a)

		case .Minus:
			if ty.kind == .Matrix {
				n := int(ty.size)
				out := dx_temp(g, ex.type)

				for k in 0..<n {
					dx_ins(g, DX_MOV, dx_column(g, out, k, n), dx_neg(g, dx_column(g, a, k, n)))
				}

				return out
			}

			if a.space == .Imm {
				return dx_neg(g, a)
			}

			if ty.scalar == .Float {
				return dx_new(g, DX_MOV, ex.type, dx_neg(g, a))
			}

			return dx_new(g, DX_INEG, ex.type, a)
		}

		return a

	case .Assign:
		loc := dx_place(g, ex.a)
		value := dx_expr(g, ex.b)

		if ex.op != .Assign {
			old := dx_load(g, loc)
			value = dx_binop(g, compound_op(ex.op), ex.type, ex.type, c.exprs[ex.b].type, old, value)
		}

		dx_store(g, loc, value)
		return value

	case .Ternary:
		cond := dx_expr(g, ex.a)
		ty := c.types[ex.type]

		if dx_pure(c, ex.b) && dx_pure(c, ex.c) && (ty.kind == .Scalar || ty.kind == .Vector) {
			a := dx_expr(g, ex.b)
			b := dx_expr(g, ex.c)
			return dx_new(g, DX_MOVC, ex.type, cond, a, b)
		}

		result := dx_temp(g, ex.type)
		dx_test(g, DX_IF | DX_TEST_NZ, cond)
		dx_copy(g, result, dx_expr(g, ex.b))
		dx_bare(g, DX_ELSE)
		dx_copy(g, result, dx_expr(g, ex.c))
		dx_bare(g, DX_ENDIF)
		return result

	case .Call:
		return dx_call(g, ex)

	case .Builtin_Call:
		return dx_builtin(g, ex)

	case .Construct:
		return dx_construct(g, ex)

	case .Comma:
		dx_expr(g, ex.a)
		return dx_expr(g, ex.b)
	}

	return {}
}
