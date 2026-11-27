package karl2d_shader_compiler

Spv_Lvalue :: struct {
	ptr: u32,
	type: Type_Index,
	storage: u32,
	bool_as_uint: bool,
	swizzle_count: u8,
	swizzle: [4]u8,
}

spv_is_addressable :: proc(g: ^Spv, e: Expr_Index) -> bool {
	ex := g.c.exprs[e]

	#partial switch ex.kind {
	case .Var:
		return true

	case .Index, .Field, .Swizzle:
		return spv_is_addressable(g, ex.a)
	}

	return false
}

spv_lvalue :: proc(g: ^Spv, e: Expr_Index) -> Spv_Lvalue {
	c := g.c
	ex := c.exprs[e]

	#partial switch ex.kind {
	case .Var:
		v := c.vars[ex.var]

		if v.kind == .Uniform && v.type != T_SAMPLER_2D {
			member_type := spv_type(g, spv_uniform_type(g, v.type))
			ptr_type := spv_ptr_type(g, member_type, SPV_STORAGE_UNIFORM)
			ptr := spv_value(g, 65, ptr_type, g.constants_var, spv_const(g, T_INT, u32(g.var_member[ex.var])))

			return {
				ptr = ptr,
				type = v.type,
				storage = SPV_STORAGE_UNIFORM,
				bool_as_uint = c.types[v.type].scalar == .Bool,
			}
		}

		return { ptr = g.var_ids[ex.var], type = v.type, storage = g.var_storage[ex.var] }

	case .Index:
		base := spv_lvalue(g, ex.a)
		index := spv_expr(g, ex.b)

		if base.swizzle_count > 0 {
			compile_error(c, ex.file, ex.line, "Indexing a swizzle is not supported")
			return base
		}

		elem_type := base.bool_as_uint ? spv_uniform_type(g, ex.type) : ex.type
		ptr_type := spv_ptr_type(g, spv_type(g, elem_type), base.storage)

		return {
			ptr = spv_value(g, 65, ptr_type, base.ptr, index),
			type = ex.type,
			storage = base.storage,
			bool_as_uint = base.bool_as_uint,
		}

	case .Field:
		base := spv_lvalue(g, ex.a)
		ptr_type := spv_ptr_type(g, spv_type(g, ex.type), base.storage)

		return {
			ptr = spv_value(g, 65, ptr_type, base.ptr, spv_const(g, T_INT, u32(ex.field))),
			type = ex.type,
			storage = base.storage,
		}

	case .Swizzle:
		base := spv_lvalue(g, ex.a)
		result := base
		result.swizzle_count = ex.swizzle_count

		for i in 0..<int(ex.swizzle_count) {
			if base.swizzle_count > 0 {
				result.swizzle[i] = base.swizzle[ex.swizzle[i]]
			} else {
				result.swizzle[i] = ex.swizzle[i]
			}
		}

		return result
	}

	compile_error(c, ex.file, ex.line, "This expression cannot be written to")
	return {}
}

spv_swizzle :: proc(g: ^Spv, value: u32, scalar: Scalar, count: int, swizzle: [4]u8) -> u32 {
	if count == 1 {
		return spv_value(g, 81, spv_type(g, type_vec(scalar, 1)), value, u32(swizzle[0]))
	}

	type := spv_type(g, type_vec(scalar, count))

	switch count {
	case 2: return spv_value(g, 79, type, value, value, u32(swizzle[0]), u32(swizzle[1]))
	case 3: return spv_value(g, 79, type, value, value, u32(swizzle[0]), u32(swizzle[1]), u32(swizzle[2]))
	}

	return spv_value(g, 79, type, value, value, u32(swizzle[0]), u32(swizzle[1]), u32(swizzle[2]), u32(swizzle[3]))
}

spv_load :: proc(g: ^Spv, lv: Spv_Lvalue) -> u32 {
	c := g.c
	stored_type := lv.bool_as_uint ? spv_uniform_type(g, lv.type) : lv.type
	value := spv_value(g, 61, spv_type(g, stored_type), lv.ptr)

	if lv.bool_as_uint {
		value = spv_value(g, 171, spv_type(g, lv.type), value, spv_zero(g, stored_type))
	}

	if lv.swizzle_count > 0 {
		return spv_swizzle(g, value, c.types[lv.type].scalar, int(lv.swizzle_count), lv.swizzle)
	}

	return value
}

spv_store :: proc(g: ^Spv, lv: Spv_Lvalue, value: u32) {
	c := g.c

	if lv.swizzle_count == 0 {
		spv_code(g, 62, lv.ptr, value)
		return
	}

	ty := c.types[lv.type]

	if lv.swizzle_count == 1 {
		ptr_type := spv_ptr_type(g, spv_type(g, type_vec(ty.scalar, 1)), lv.storage)
		ptr := spv_value(g, 65, ptr_type, lv.ptr, spv_const(g, T_INT, u32(lv.swizzle[0])))
		spv_code(g, 62, ptr, value)
		return
	}

	type := spv_type(g, lv.type)
	old := spv_value(g, 61, type, lv.ptr)
	mapping: [4]u32

	for i in 0..<int(ty.size) {
		mapping[i] = u32(i)
	}

	for i in 0..<int(lv.swizzle_count) {
		mapping[lv.swizzle[i]] = u32(int(ty.size) + i)
	}

	merged: u32

	switch ty.size {
	case 2: merged = spv_value(g, 79, type, old, value, mapping[0], mapping[1])
	case 3: merged = spv_value(g, 79, type, old, value, mapping[0], mapping[1], mapping[2])
	case 4: merged = spv_value(g, 79, type, old, value, mapping[0], mapping[1], mapping[2], mapping[3])
	}

	spv_code(g, 62, lv.ptr, merged)
}

spv_splat :: proc(g: ^Spv, value: u32, from: Type_Index, to: Type_Index) -> u32 {
	c := g.c

	if c.types[from].kind != .Scalar || c.types[to].kind != .Vector {
		return value
	}

	type := spv_type(g, to)

	switch c.types[to].size {
	case 2: return spv_value(g, 80, type, value, value)
	case 3: return spv_value(g, 80, type, value, value, value)
	}

	return spv_value(g, 80, type, value, value, value, value)
}

spv_construct :: proc(g: ^Spv, type: Type_Index, parts: []u32) -> u32 {
	if g.terminated {
		spv_label(g, spv_id(g))
	}

	id := spv_id(g)
	append(&g.body, u32(len(parts) + 3) << 16 | 80, spv_type(g, type), id)
	append(&g.body, ..parts)
	return id
}

spv_matrix_columns :: proc(g: ^Spv, op: u32, t: Type_Index, ta: Type_Index, tb: Type_Index, a: u32, b: u32) -> u32 {
	c := g.c
	n := int(c.types[t].size)
	column_type := type_vec(.Float, n)
	column := spv_type(g, column_type)
	columns: [4]u32

	for i in 0..<n {
		ca := a
		cb := b

		if c.types[ta].kind == .Matrix {
			ca = spv_value(g, 81, column, a, u32(i))
		} else {
			ca = spv_splat(g, a, ta, column_type)
		}

		if c.types[tb].kind == .Matrix {
			cb = spv_value(g, 81, column, b, u32(i))
		} else {
			cb = spv_splat(g, b, tb, column_type)
		}

		columns[i] = spv_value(g, op, column, ca, cb)
	}

	return spv_construct(g, t, columns[:n])
}

spv_equal :: proc(g: ^Spv, t: Type_Index, a: u32, b: u32) -> u32 {
	c := g.c
	ty := c.types[t]
	bool_type := spv_type(g, T_BOOL)

	switch ty.kind {
	case .Scalar, .Vector:
		op: u32

		switch ty.scalar {
		case .Float: op = 180
		case .Int, .Uint: op = 170
		case .Bool: op = 164
		case .None:
		}

		if ty.kind == .Scalar {
			return spv_value(g, op, bool_type, a, b)
		}

		each := spv_value(g, op, spv_type(g, type_vec(.Bool, int(ty.size))), a, b)
		return spv_value(g, 155, bool_type, each)

	case .Matrix, .Array, .Struct:
		count := ty.kind == .Matrix ? int(ty.size) : ty.kind == .Array ? int(ty.len) : len(ty.fields)
		result: u32

		for i in 0..<count {
			part_type: Type_Index

			#partial switch ty.kind {
			case .Matrix: part_type = type_vec(.Float, int(ty.size))
			case .Array: part_type = ty.elem
			case .Struct: part_type = ty.fields[i].type
			}

			part := spv_type(g, part_type)
			pa := spv_value(g, 81, part, a, u32(i))
			pb := spv_value(g, 81, part, b, u32(i))
			same := spv_equal(g, part_type, pa, pb)

			if i == 0 {
				result = same
			} else {
				result = spv_value(g, 167, bool_type, result, same)
			}
		}

		return result

	case .None, .Void, .Sampler_2D:
	}

	return spv_const(g, T_BOOL, 1)
}

spv_binop :: proc(g: ^Spv, op: Token_Kind, t: Type_Index, ta: Type_Index, tb: Type_Index, a: u32, b: u32) -> u32 {
	c := g.c
	result := c.types[t]
	at := c.types[ta]
	bt := c.types[tb]
	type := spv_type(g, t)

	#partial switch op {
	case .Eq_Eq:
		return spv_equal(g, ta, a, b)

	case .Not_Eq:
		return spv_value(g, 168, type, spv_equal(g, ta, a, b))

	case .Xor_Xor:
		return spv_value(g, 165, type, a, b)

	case .Lt, .Gt, .Le, .Ge:
		code: u32

		switch at.scalar {
		case .Float:
			#partial switch op {
			case .Lt: code = 184
			case .Gt: code = 186
			case .Le: code = 188
			case .Ge: code = 190
			}

		case .Int:
			#partial switch op {
			case .Lt: code = 177
			case .Gt: code = 173
			case .Le: code = 179
			case .Ge: code = 175
			}

		case .Uint:
			#partial switch op {
			case .Lt: code = 176
			case .Gt: code = 172
			case .Le: code = 178
			case .Ge: code = 174
			}

		case .Bool, .None:
		}

		return spv_value(g, code, type, a, b)

	case .Shl, .Shr:
		code := u32(196)

		if op == .Shr {
			code = at.scalar == .Int ? 195 : 194
		}

		return spv_value(g, code, type, a, spv_splat(g, b, tb, retype(c, ta, bt.scalar)))
	}

	if result.kind == .Matrix {
		if op == .Star {
			if at.kind == .Matrix && bt.kind == .Matrix {
				return spv_value(g, 146, type, a, b)
			}

			if at.kind == .Matrix {
				return spv_value(g, 143, type, a, b)
			}

			return spv_value(g, 143, type, b, a)
		}

		code: u32

		#partial switch op {
		case .Plus: code = 129
		case .Minus: code = 131
		case .Slash: code = 136
		}

		return spv_matrix_columns(g, code, t, ta, tb, a, b)
	}

	if at.kind == .Matrix {
		return spv_value(g, 145, type, a, b)
	}

	if bt.kind == .Matrix {
		return spv_value(g, 144, type, a, b)
	}

	if op == .Percent && result.scalar == .Int {
		sa := spv_splat(g, a, ta, t)
		sb := spv_splat(g, b, tb, t)
		quotient := spv_value(g, 135, type, sa, sb)
		return spv_value(g, 130, type, sa, spv_value(g, 132, type, quotient, sb))
	}

	code: u32

	#partial switch op {
	case .Plus: code = result.scalar == .Float ? 129 : 128
	case .Minus: code = result.scalar == .Float ? 131 : 130
	case .Star: code = result.scalar == .Float ? 133 : 132
	case .Slash:
		switch result.scalar {
		case .Float: code = 136
		case .Int: code = 135
		case .Uint: code = 134
		case .Bool, .None:
		}

	case .Percent: code = result.scalar == .Int ? 138 : 137
	case .Amp: code = 199
	case .Pipe: code = 197
	case .Caret: code = 198
	}

	return spv_value(g, code, type, spv_splat(g, a, ta, t), spv_splat(g, b, tb, t))
}

spv_convert :: proc(g: ^Spv, value: u32, from: Type_Index, to: Type_Index) -> u32 {
	c := g.c
	fs := c.types[from].scalar
	ts := c.types[to].scalar
	type := spv_type(g, to)

	if fs == ts {
		return value
	}

	if fs == .Bool {
		return spv_value(g, 169, type, value, spv_one(g, to), spv_zero(g, to))
	}

	switch ts {
	case .Float:
		return spv_value(g, fs == .Int ? 111 : 112, type, value)

	case .Int:
		return spv_value(g, fs == .Float ? 110 : 124, type, value)

	case .Uint:
		return spv_value(g, fs == .Float ? 109 : 124, type, value)

	case .Bool:
		if fs == .Float {
			return spv_value(g, 183, type, value, spv_zero(g, from))
		}

		return spv_value(g, 171, type, value, spv_zero(g, from))

	case .None:
	}

	return value
}

spv_flatten :: proc(g: ^Spv, value: u32, type: Type_Index, out: ^[16]u32, count: ^int) {
	c := g.c
	ty := c.types[type]

	#partial switch ty.kind {
	case .Scalar:
		if count^ < 16 {
			out[count^] = value
			count^ += 1
		}

	case .Vector:
		scalar := spv_type(g, type_vec(ty.scalar, 1))

		for i in 0..<int(ty.size) {
			if count^ < 16 {
				out[count^] = spv_value(g, 81, scalar, value, u32(i))
				count^ += 1
			}
		}

	case .Matrix:
		scalar := spv_type(g, T_FLOAT)

		for col in 0..<int(ty.size) {
			for row in 0..<int(ty.size) {
				if count^ < 16 {
					out[count^] = spv_value(g, 81, scalar, value, u32(col), u32(row))
					count^ += 1
				}
			}
		}
	}
}

spv_construct_expr :: proc(g: ^Spv, ex: Expr) -> u32 {
	c := g.c
	ty := c.types[ex.type]
	args := c.expr_args[ex.args_start:ex.args_start + ex.args_count]
	first_type := c.exprs[args[0]].type
	first := c.types[first_type]

	if ty.kind == .Struct || ty.kind == .Array {
		parts := make([]u32, len(args), c.allocator)

		for a, a_idx in args {
			parts[a_idx] = spv_expr(g, a)
		}

		return spv_construct(g, ex.type, parts)
	}

	if len(args) == 1 && (ty.kind == .Scalar || ty.kind == .Vector) && first.kind == ty.kind && first.size == ty.size {
		return spv_convert(g, spv_expr(g, args[0]), first_type, ex.type)
	}

	if len(args) == 1 && ty.kind == .Vector && first.kind == .Scalar {
		return spv_splat(g, spv_expr(g, args[0]), first_type, ex.type)
	}

	scalars: [16]u32
	count := 0

	if ty.kind == .Matrix && len(args) == 1 && first.kind == .Matrix {
		source := spv_expr(g, args[0])
		n := int(ty.size)
		float_type := spv_type(g, T_FLOAT)
		one := spv_one(g, T_FLOAT)
		zero := spv_zero(g, T_FLOAT)

		for col in 0..<n {
			for row in 0..<n {
				if col < int(first.size) && row < int(first.size) {
					scalars[count] = spv_value(g, 81, float_type, source, u32(col), u32(row))
				} else {
					scalars[count] = col == row ? one : zero
				}

				count += 1
			}
		}
	} else if ty.kind == .Matrix && len(args) == 1 && first.kind == .Scalar {
		value := spv_expr(g, args[0])
		n := int(ty.size)
		zero := spv_zero(g, T_FLOAT)

		for i in 0..<n * n {
			scalars[i] = i / n == i % n ? value : zero
		}

		count = n * n
	} else {
		for a in args {
			spv_flatten(g, spv_expr(g, a), c.exprs[a].type, &scalars, &count)
		}
	}

	if ty.kind == .Vector {
		return spv_construct(g, ex.type, scalars[:int(ty.size)])
	}

	n := int(ty.size)
	columns: [4]u32
	column_type := type_vec(.Float, n)

	for col in 0..<n {
		columns[col] = spv_construct(g, column_type, scalars[col * n:col * n + n])
	}

	return spv_construct(g, ex.type, columns[:n])
}

spv_sampler_ptr :: proc(g: ^Spv, e: Expr_Index) -> u32 {
	ex := g.c.exprs[e]

	if ex.kind != .Var {
		compile_error(g.c, ex.file, ex.line, "A sampler2D must be passed by its name")
		return 0
	}

	return g.var_ids[ex.var]
}

spv_ext :: proc(g: ^Spv, type: u32, inst: u32, args: ..u32) -> u32 {
	switch len(args) {
	case 1: return spv_value(g, 12, type, g.ext_glsl, inst, args[0])
	case 2: return spv_value(g, 12, type, g.ext_glsl, inst, args[0], args[1])
	}

	return spv_value(g, 12, type, g.ext_glsl, inst, args[0], args[1], args[2])
}

spv_builtin :: proc(g: ^Spv, ex: Expr) -> u32 {
	c := g.c
	arg_exprs := c.expr_args[ex.args_start:ex.args_start + ex.args_count]
	type := spv_type(g, ex.type)
	a: [3]u32
	t: [3]Type_Index
	first := 0

	#partial switch ex.builtin {
	case .Texture, .Texture_Lod, .Texel_Fetch, .Texture_Size:
		first = 1
	}

	for i in first..<len(arg_exprs) {
		a[i] = spv_expr(g, arg_exprs[i])
		t[i] = c.exprs[arg_exprs[i]].type
	}

	scalar := c.types[t[first]].scalar
	simple: u32

	switch ex.builtin {
	case .None:
	case .Radians: simple = 11
	case .Degrees: simple = 12
	case .Sin: simple = 13
	case .Cos: simple = 14
	case .Tan: simple = 15
	case .Asin: simple = 16
	case .Acos: simple = 17
	case .Atan: simple = len(arg_exprs) == 2 ? 25 : 18
	case .Sinh: simple = 19
	case .Cosh: simple = 20
	case .Tanh: simple = 21
	case .Pow: simple = 26
	case .Exp: simple = 27
	case .Log: simple = 28
	case .Exp2: simple = 29
	case .Log2: simple = 30
	case .Sqrt: simple = 31
	case .Inversesqrt: simple = 32
	case .Floor: simple = 8
	case .Trunc: simple = 3
	case .Round: simple = 1
	case .Ceil: simple = 9
	case .Fract: simple = 10
	case .Length: simple = 66
	case .Distance: simple = 67
	case .Cross: simple = 68
	case .Normalize: simple = 69
	case .Reflect: simple = 71
	case .Refract: simple = 72
	case .Determinant: simple = 33
	case .Inverse: simple = 34
	case .Abs: simple = scalar == .Float ? 4 : 5
	case .Sign: simple = scalar == .Float ? 6 : 7

	case .Mod:
		return spv_value(g, 141, type, a[0], spv_splat(g, a[1], t[1], ex.type))

	case .Min, .Max, .Clamp:
		inst: u32

		#partial switch ex.builtin {
		case .Min: inst = scalar == .Float ? 37 : scalar == .Uint ? 38 : 39
		case .Max: inst = scalar == .Float ? 40 : scalar == .Uint ? 41 : 42
		case .Clamp: inst = scalar == .Float ? 43 : scalar == .Uint ? 44 : 45
		}

		for i in 1..<len(arg_exprs) {
			a[i] = spv_splat(g, a[i], t[i], ex.type)
		}

		return spv_ext(g, type, inst, ..a[:len(arg_exprs)])

	case .Mix:
		if c.types[t[2]].scalar == .Bool {
			return spv_value(g, 169, type, a[2], a[1], a[0])
		}

		return spv_ext(g, type, 46, a[0], a[1], spv_splat(g, a[2], t[2], ex.type))

	case .Step:
		return spv_ext(g, type, 48, spv_splat(g, a[0], t[0], ex.type), a[1])

	case .Smoothstep:
		return spv_ext(g, type, 49, spv_splat(g, a[0], t[0], ex.type), spv_splat(g, a[1], t[1], ex.type), a[2])

	case .Dot:
		if c.types[t[0]].kind == .Scalar {
			return spv_value(g, 133, type, a[0], a[1])
		}

		return spv_value(g, 148, type, a[0], a[1])

	case .Matrix_Comp_Mult:
		return spv_matrix_columns(g, 133, ex.type, t[0], t[1], a[0], a[1])

	case .Transpose:
		return spv_value(g, 84, type, a[0])

	case .Less_Than, .Less_Than_Equal, .Greater_Than, .Greater_Than_Equal, .Equal, .Not_Equal:
		code: u32

		switch scalar {
		case .Float:
			#partial switch ex.builtin {
			case .Less_Than: code = 184
			case .Less_Than_Equal: code = 188
			case .Greater_Than: code = 186
			case .Greater_Than_Equal: code = 190
			case .Equal: code = 180
			case .Not_Equal: code = 183
			}

		case .Int:
			#partial switch ex.builtin {
			case .Less_Than: code = 177
			case .Less_Than_Equal: code = 179
			case .Greater_Than: code = 173
			case .Greater_Than_Equal: code = 175
			case .Equal: code = 170
			case .Not_Equal: code = 171
			}

		case .Uint:
			#partial switch ex.builtin {
			case .Less_Than: code = 176
			case .Less_Than_Equal: code = 178
			case .Greater_Than: code = 172
			case .Greater_Than_Equal: code = 174
			case .Equal: code = 170
			case .Not_Equal: code = 171
			}

		case .Bool:
			code = ex.builtin == .Equal ? 164 : 165

		case .None:
		}

		return spv_value(g, code, type, a[0], a[1])

	case .Any:
		return spv_value(g, 154, type, a[0])

	case .All:
		return spv_value(g, 155, type, a[0])

	case .Not:
		return spv_value(g, 168, type, a[0])

	case .DFdx:
		return spv_value(g, 207, type, a[0])

	case .DFdy:
		return spv_value(g, 208, type, a[0])

	case .Fwidth:
		return spv_value(g, 209, type, a[0])

	case .Texture, .Texture_Lod, .Texel_Fetch, .Texture_Size:
		sampled := spv_value(g, 61, spv_type(g, T_SAMPLER_2D), spv_sampler_ptr(g, arg_exprs[0]))

		#partial switch ex.builtin {
		case .Texture:
			if g.stage == .Vertex {
				return spv_value(g, 88, type, sampled, a[1], 2, spv_zero(g, T_FLOAT))
			}

			if len(arg_exprs) == 3 {
				return spv_value(g, 87, type, sampled, a[1], 1, a[2])
			}

			return spv_value(g, 87, type, sampled, a[1])

		case .Texture_Lod:
			return spv_value(g, 88, type, sampled, a[1], 2, a[2])

		case .Texel_Fetch:
			image := spv_value(g, 100, g.image_type, sampled)
			return spv_value(g, 95, type, image, a[1], 2, a[2])

		case .Texture_Size:
			g.uses_image_query = true
			image := spv_value(g, 100, g.image_type, sampled)
			return spv_value(g, 103, type, image, a[1])
		}
	}

	return spv_ext(g, type, simple, ..a[:len(arg_exprs)])
}

spv_expr :: proc(g: ^Spv, e: Expr_Index) -> u32 {
	c := g.c
	ex := c.exprs[e]
	type := spv_type(g, ex.type)

	switch ex.kind {
	case .None:

	case .Literal:
		if c.types[ex.type].scalar == .Float {
			return spv_const(g, ex.type, transmute(u32)f32(ex.fval))
		}

		return spv_const(g, ex.type, u32(ex.ival))

	case .Var:
		return spv_load(g, spv_lvalue(g, e))

	case .Index:
		if spv_is_addressable(g, e) {
			return spv_load(g, spv_lvalue(g, e))
		}

		base := spv_expr(g, ex.a)
		index := c.exprs[ex.b]

		if index.kind == .Literal {
			return spv_value(g, 81, type, base, u32(index.ival))
		}

		base_type := c.exprs[ex.a].type

		if c.types[base_type].kind == .Vector {
			return spv_value(g, 77, type, base, spv_expr(g, ex.b))
		}

		temp := spv_local(g, base_type)
		spv_code(g, 62, temp, base)
		ptr := spv_value(g, 65, spv_ptr_type(g, type, SPV_STORAGE_FUNCTION), temp, spv_expr(g, ex.b))
		return spv_value(g, 61, type, ptr)

	case .Field:
		if spv_is_addressable(g, e) {
			return spv_load(g, spv_lvalue(g, e))
		}

		return spv_value(g, 81, type, spv_expr(g, ex.a), u32(ex.field))

	case .Swizzle:
		if spv_is_addressable(g, e) {
			return spv_load(g, spv_lvalue(g, e))
		}

		return spv_swizzle(g, spv_expr(g, ex.a), c.types[ex.type].scalar, int(ex.swizzle_count), ex.swizzle)

	case .Binary:
		if ex.op == .And_And || ex.op == .Or_Or {
			a := spv_expr(g, ex.a)
			a_label := g.cur_label
			rhs_label := spv_id(g)
			merge_label := spv_id(g)
			spv_code(g, 247, merge_label, 0)

			if ex.op == .And_And {
				spv_code(g, 250, a, rhs_label, merge_label)
			} else {
				spv_code(g, 250, a, merge_label, rhs_label)
			}

			spv_label(g, rhs_label)
			b := spv_expr(g, ex.b)
			b_label := g.cur_label
			spv_branch(g, merge_label)
			spv_label(g, merge_label)
			return spv_value(g, 245, type, a, a_label, b, b_label)
		}

		a := spv_expr(g, ex.a)
		b := spv_expr(g, ex.b)
		return spv_binop(g, ex.op, ex.type, c.exprs[ex.a].type, c.exprs[ex.b].type, a, b)

	case .Unary:
		if ex.op == .Inc || ex.op == .Dec {
			lv := spv_lvalue(g, ex.a)
			old := spv_load(g, lv)
			scalar_type := type_vec(c.types[ex.type].scalar, 1)
			changed := spv_binop(g, ex.op == .Inc ? .Plus : .Minus, ex.type, ex.type, scalar_type, old, spv_one(g, scalar_type))
			spv_store(g, lv, changed)
			return ex.postfix ? old : changed
		}

		a := spv_expr(g, ex.a)

		#partial switch ex.op {
		case .Not:
			return spv_value(g, 168, type, a)

		case .Tilde:
			return spv_value(g, 200, type, a)

		case .Minus:
			ty := c.types[ex.type]

			if ty.kind == .Matrix {
				return spv_value(g, 143, type, a, spv_const(g, T_FLOAT, transmute(u32)f32(-1)))
			}

			return spv_value(g, ty.scalar == .Float ? 127 : 126, type, a)
		}

		return a

	case .Assign:
		lv := spv_lvalue(g, ex.a)
		value := spv_expr(g, ex.b)

		if ex.op != .Assign {
			old := spv_load(g, lv)
			value = spv_binop(g, compound_op(ex.op), ex.type, ex.type, c.exprs[ex.b].type, old, value)
		}

		spv_store(g, lv, value)
		return value

	case .Ternary:
		cond := spv_expr(g, ex.a)
		then_label := spv_id(g)
		else_label := spv_id(g)
		merge_label := spv_id(g)
		spv_code(g, 247, merge_label, 0)
		spv_code(g, 250, cond, then_label, else_label)
		spv_label(g, then_label)
		a := spv_expr(g, ex.b)
		a_label := g.cur_label
		spv_branch(g, merge_label)
		spv_label(g, else_label)
		b := spv_expr(g, ex.c)
		b_label := g.cur_label
		spv_branch(g, merge_label)
		spv_label(g, merge_label)
		return spv_value(g, 245, type, a, a_label, b, b_label)

	case .Call:
		f := c.funcs[ex.func]
		args := c.expr_args[ex.args_start:ex.args_start + ex.args_count]
		words := make([]u32, len(args) + 3, c.allocator)
		lvalues := make([]Spv_Lvalue, len(args), c.allocator)

		for arg, arg_idx in args {
			param := c.vars[f.params[arg_idx]]

			if param.type == T_SAMPLER_2D {
				words[arg_idx + 3] = spv_sampler_ptr(g, arg)
				continue
			}

			if param.param_qualifier == .In {
				words[arg_idx + 3] = spv_expr(g, arg)
				continue
			}

			temp := spv_local(g, param.type)
			lvalues[arg_idx] = spv_lvalue(g, arg)

			if param.param_qualifier == .Inout {
				spv_code(g, 62, temp, spv_load(g, lvalues[arg_idx]))
			}

			words[arg_idx + 3] = temp
		}

		if g.terminated {
			spv_label(g, spv_id(g))
		}

		result := spv_id(g)
		words[0] = type
		words[1] = result
		words[2] = g.func_ids[ex.func]
		append(&g.body, u32(len(words) + 1) << 16 | 57)
		append(&g.body, ..words)

		for arg_idx in 0..<len(args) {
			param := c.vars[f.params[arg_idx]]

			if param.type == T_SAMPLER_2D || param.param_qualifier == .In {
				continue
			}

			value := spv_value(g, 61, spv_type(g, param.type), words[arg_idx + 3])
			spv_store(g, lvalues[arg_idx], value)
		}

		return result

	case .Builtin_Call:
		return spv_builtin(g, ex)

	case .Construct:
		return spv_construct_expr(g, ex)

	case .Comma:
		spv_expr(g, ex.a)
		return spv_expr(g, ex.b)
	}

	return 0
}
