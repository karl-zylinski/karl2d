package karl2d_shader_compiler

Builtin :: enum u8 {
	None,
	Radians,
	Degrees,
	Sin,
	Cos,
	Tan,
	Asin,
	Acos,
	Atan,
	Sinh,
	Cosh,
	Tanh,
	Pow,
	Exp,
	Log,
	Exp2,
	Log2,
	Sqrt,
	Inversesqrt,
	Abs,
	Sign,
	Floor,
	Trunc,
	Round,
	Ceil,
	Fract,
	Mod,
	Min,
	Max,
	Clamp,
	Mix,
	Step,
	Smoothstep,
	Length,
	Distance,
	Dot,
	Cross,
	Normalize,
	Reflect,
	Refract,
	Matrix_Comp_Mult,
	Transpose,
	Determinant,
	Inverse,
	Less_Than,
	Less_Than_Equal,
	Greater_Than,
	Greater_Than_Equal,
	Equal,
	Not_Equal,
	Any,
	All,
	Not,
	Texture,
	Texture_Lod,
	Texture_Grad,
	Texel_Fetch,
	Texture_Size,
	DFdx,
	DFdy,
	Fwidth,
}

builtin_names := [Builtin]string {
	.None = "",
	.Radians = "radians",
	.Degrees = "degrees",
	.Sin = "sin",
	.Cos = "cos",
	.Tan = "tan",
	.Asin = "asin",
	.Acos = "acos",
	.Atan = "atan",
	.Sinh = "sinh",
	.Cosh = "cosh",
	.Tanh = "tanh",
	.Pow = "pow",
	.Exp = "exp",
	.Log = "log",
	.Exp2 = "exp2",
	.Log2 = "log2",
	.Sqrt = "sqrt",
	.Inversesqrt = "inversesqrt",
	.Abs = "abs",
	.Sign = "sign",
	.Floor = "floor",
	.Trunc = "trunc",
	.Round = "round",
	.Ceil = "ceil",
	.Fract = "fract",
	.Mod = "mod",
	.Min = "min",
	.Max = "max",
	.Clamp = "clamp",
	.Mix = "mix",
	.Step = "step",
	.Smoothstep = "smoothstep",
	.Length = "length",
	.Distance = "distance",
	.Dot = "dot",
	.Cross = "cross",
	.Normalize = "normalize",
	.Reflect = "reflect",
	.Refract = "refract",
	.Matrix_Comp_Mult = "matrixCompMult",
	.Transpose = "transpose",
	.Determinant = "determinant",
	.Inverse = "inverse",
	.Less_Than = "lessThan",
	.Less_Than_Equal = "lessThanEqual",
	.Greater_Than = "greaterThan",
	.Greater_Than_Equal = "greaterThanEqual",
	.Equal = "equal",
	.Not_Equal = "notEqual",
	.Any = "any",
	.All = "all",
	.Not = "not",
	.Texture = "texture",
	.Texture_Lod = "textureLod",
	.Texture_Grad = "textureGrad",
	.Texel_Fetch = "texelFetch",
	.Texture_Size = "textureSize",
	.DFdx = "dFdx",
	.DFdy = "dFdy",
	.Fwidth = "fwidth",
}

builtin_compare_op :: proc(b: Builtin) -> Token_Kind {
	#partial switch b {
	case .Less_Than: return .Lt
	case .Less_Than_Equal: return .Le
	case .Greater_Than: return .Gt
	case .Greater_Than_Equal: return .Ge
	case .Equal: return .Eq_Eq
	}

	return .Not_Eq
}

unify_builtin_args :: proc(
	c: ^Compiler,
	args: []Expr_Index,
	float_only: bool,
	scalar_ok: bit_set[0..<4],
	tok: Token,
) -> Type_Index {
	base := float_only ? Scalar.Float : Scalar.Int
	size := 1

	for a in args {
		at := c.exprs[a].type
		ty := c.types[at]

		if !type_is_scalar_or_vector(c, at) || ty.scalar == .Bool {
			compile_error(c, tok.file, tok.line, "'%s' cannot take a '%s'", tok.text, type_name(c, at))
			return T_NONE
		}

		if scalar_rank(ty.scalar) > scalar_rank(base) {
			base = ty.scalar
		}

		size = max(size, int(ty.size))
	}

	for a, a_idx in args {
		at := c.exprs[a].type
		ty := c.types[at]

		if int(ty.size) != size && !(ty.size == 1 && a_idx in scalar_ok) {
			compile_error(c, tok.file, tok.line, "The arguments of '%s' have different sizes", tok.text)
			return T_NONE
		}

		args[a_idx] = make_cast(c, a, retype(c, at, base))
	}

	return type_vec(base, size)
}

check_builtin_call :: proc(c: ^Compiler, b: Builtin, args: []Expr_Index, tok: Token) -> Type_Index {
	count := len(args)
	min_args := 1
	max_args := 1

	#partial switch b {
	case .Atan:
		max_args = 2

	case .Pow, .Mod, .Min, .Max, .Step, .Distance, .Dot, .Cross, .Reflect, .Matrix_Comp_Mult,
	     .Less_Than, .Less_Than_Equal, .Greater_Than, .Greater_Than_Equal, .Equal, .Not_Equal, .Texture_Size:
		min_args = 2
		max_args = 2

	case .Clamp, .Mix, .Smoothstep, .Refract, .Texture_Lod, .Texel_Fetch:
		min_args = 3
		max_args = 3

	case .Texture:
		min_args = 2
		max_args = 3

	case .Texture_Grad:
		min_args = 4
		max_args = 4
	}

	if count < min_args || count > max_args {
		compile_error(c, tok.file, tok.line, "'%s' takes %d arguments but got %d", tok.text, min_args, count)
		return T_NONE
	}

	switch b {
	case .None:

	case .Radians, .Degrees, .Sin, .Cos, .Tan, .Asin, .Acos, .Atan, .Sinh, .Cosh, .Tanh, .Pow, .Exp, .Log,
	     .Exp2, .Log2, .Sqrt, .Inversesqrt, .Floor, .Trunc, .Round, .Ceil, .Fract, .Normalize, .Reflect,
	     .DFdx, .DFdy, .Fwidth:
		return unify_builtin_args(c, args, true, {}, tok)

	case .Length, .Distance, .Dot:
		unify_builtin_args(c, args, true, {}, tok)
		return T_FLOAT

	case .Abs, .Sign:
		t := unify_builtin_args(c, args, false, {}, tok)

		if c.types[t].scalar == .Uint {
			compile_error(c, tok.file, tok.line, "'%s' cannot take a '%s'", tok.text, type_name(c, t))
			return T_NONE
		}

		return t

	case .Mod:
		return unify_builtin_args(c, args, true, { 1 }, tok)

	case .Min, .Max:
		return unify_builtin_args(c, args, false, { 1 }, tok)

	case .Clamp:
		t := unify_builtin_args(c, args, false, { 1, 2 }, tok)

		if c.failed {
			return T_NONE
		}

		if c.types[c.exprs[args[1]].type].size != c.types[c.exprs[args[2]].type].size {
			compile_error(c, tok.file, tok.line, "The limits of 'clamp' must have the same size")
			return T_NONE
		}

		return t

	case .Mix:
		selector := c.types[c.exprs[args[2]].type]

		if selector.scalar == .Bool {
			t := unify_builtin_args(c, args[:2], true, {}, tok)

			if c.failed {
				return T_NONE
			}

			if selector.size != c.types[t].size {
				compile_error(c, tok.file, tok.line, "The selector of 'mix' must have the same size as the values")
				return T_NONE
			}

			return t
		}

		return unify_builtin_args(c, args, true, { 2 }, tok)

	case .Step:
		return unify_builtin_args(c, args, true, { 0 }, tok)

	case .Smoothstep:
		t := unify_builtin_args(c, args, true, { 0, 1 }, tok)

		if c.failed {
			return T_NONE
		}

		if c.types[c.exprs[args[0]].type].size != c.types[c.exprs[args[1]].type].size {
			compile_error(c, tok.file, tok.line, "The edges of 'smoothstep' must have the same size")
			return T_NONE
		}

		return t

	case .Cross:
		t := unify_builtin_args(c, args, true, {}, tok)

		if c.failed {
			return T_NONE
		}

		if t != T_VEC3 {
			compile_error(c, tok.file, tok.line, "'cross' needs two vec3")
			return T_NONE
		}

		return t

	case .Refract:
		t := unify_builtin_args(c, args[:2], true, {}, tok)

		if c.failed {
			return T_NONE
		}

		args[2] = convert_to(c, args[2], T_FLOAT, "the last argument of 'refract'")
		return t

	case .Matrix_Comp_Mult, .Transpose, .Inverse, .Determinant:
		t := c.exprs[args[0]].type

		if c.types[t].kind != .Matrix {
			compile_error(c, tok.file, tok.line, "'%s' needs a matrix but got '%s'", tok.text, type_name(c, t))
			return T_NONE
		}

		if count == 2 && c.exprs[args[1]].type != t {
			compile_error(c, tok.file, tok.line, "'%s' needs two matrices of the same size", tok.text)
			return T_NONE
		}

		if b == .Determinant {
			return T_FLOAT
		}

		return t

	case .Less_Than, .Less_Than_Equal, .Greater_Than, .Greater_Than_Equal, .Equal, .Not_Equal:
		ta := c.exprs[args[0]].type
		tb := c.exprs[args[1]].type

		if c.types[ta].kind != .Vector || c.types[tb].kind != .Vector {
			compile_error(c, tok.file, tok.line, "'%s' needs two vectors", tok.text)
			return T_NONE
		}

		if c.types[ta].scalar == .Bool {
			if ta != tb || (b != .Equal && b != .Not_Equal) {
				compile_error(c, tok.file, tok.line, "'%s' cannot take '%s' and '%s'", tok.text, type_name(c, ta), type_name(c, tb))
				return T_NONE
			}

			return ta
		}

		t := unify_builtin_args(c, args, false, {}, tok)

		if c.failed {
			return T_NONE
		}

		return type_vec(.Bool, int(c.types[t].size))

	case .Any, .All, .Not:
		t := c.exprs[args[0]].type

		if c.types[t].kind != .Vector || c.types[t].scalar != .Bool {
			compile_error(c, tok.file, tok.line, "'%s' needs a bvec but got '%s'", tok.text, type_name(c, t))
			return T_NONE
		}

		if b == .Not {
			return t
		}

		return T_BOOL

	case .Texture, .Texture_Lod, .Texture_Grad, .Texel_Fetch, .Texture_Size:
		if c.exprs[args[0]].type != T_SAMPLER_2D {
			compile_error(c, tok.file, tok.line, "The first argument of '%s' must be a sampler2D", tok.text)
			return T_NONE
		}

		if b == .Texture_Size {
			args[1] = convert_to(c, args[1], T_INT, "the mip level")
			return T_IVEC2
		}

		if b == .Texel_Fetch {
			args[1] = convert_to(c, args[1], T_IVEC2, "the texel position")
			args[2] = convert_to(c, args[2], T_INT, "the mip level")
			return T_VEC4
		}

		args[1] = convert_to(c, args[1], T_VEC2, "the texture coordinate")

		if b == .Texture_Grad {
			args[2] = convert_to(c, args[2], T_VEC2, "the x gradient")
			args[3] = convert_to(c, args[3], T_VEC2, "the y gradient")
			return T_VEC4
		}

		if count == 3 {
			args[2] = convert_to(c, args[2], T_FLOAT, b == .Texture ? "the mip bias" : "the mip level")

			if b == .Texture {
				mark_fragment_only(c, Token { file = tok.file, line = tok.line, text = "texture with a mip bias" })
			}
		}

		return T_VEC4
	}

	return T_NONE
}
