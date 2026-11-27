package karl2d_shader_compiler

import "core:strconv"
import "core:strings"

MAX_CALL_ARGS :: 64

peek :: proc(c: ^Compiler) -> Token_Kind {
	return c.tokens[c.tok].kind
}

peek_at :: proc(c: ^Compiler, offset: int) -> Token_Kind {
	idx := c.tok + offset

	if idx >= len(c.tokens) {
		return .EOF
	}

	return c.tokens[idx].kind
}

advance :: proc(c: ^Compiler) -> Token {
	t := c.tokens[c.tok]

	if c.tok < len(c.tokens) - 1 {
		c.tok += 1
	}

	return t
}

accept :: proc(c: ^Compiler, kind: Token_Kind) -> bool {
	if c.tokens[c.tok].kind != kind {
		return false
	}

	advance(c)
	return true
}

expect :: proc(c: ^Compiler, kind: Token_Kind, what: string) -> Token {
	t := c.tokens[c.tok]

	if t.kind != kind {
		if t.kind == .EOF {
			last := c.tokens[max(c.tok - 1, 0)]
			compile_error(c, last.file, last.line, "Expected %s but the file ended", what)
		} else {
			compile_error(c, t.file, t.line, "Expected %s but found '%s'", what, t.text)
		}

		return t
	}

	advance(c)
	return t
}

new_expr :: proc(c: ^Compiler, e: Expr) -> Expr_Index {
	append(&c.exprs, e)
	return Expr_Index(len(c.exprs) - 1)
}

new_literal :: proc(c: ^Compiler, type: Type_Index, ival: i64, fval: f64, file: u16, line: i32) -> Expr_Index {
	return new_expr(c, Expr {
		kind = .Literal,
		type = type,
		ival = ival,
		fval = fval,
		file = file,
		line = line,
	})
}

lookup_type :: proc(c: ^Compiler, tok: Token) -> Type_Index {
	if known_names[tok.known].type != T_NONE {
		return known_names[tok.known].type
	}

	for i in int(T_FIRST_USER)..<len(c.types) {
		t := c.types[i]

		if t.kind == .Struct && t.name == tok.text {
			return Type_Index(i)
		}
	}

	return T_NONE
}

scalar_rank :: proc(s: Scalar) -> int {
	switch s {
	case .None: return 0
	case .Bool: return 0
	case .Int: return 1
	case .Uint: return 2
	case .Float: return 3
	}

	return 0
}

retype :: proc(c: ^Compiler, t: Type_Index, scalar: Scalar) -> Type_Index {
	ty := c.types[t]

	if ty.kind == .Scalar || ty.kind == .Vector {
		return type_vec(scalar, int(ty.size))
	}

	return t
}

fold_cast :: proc(c: ^Compiler, e: Expr_Index, to: Scalar) -> (ival: i64, fval: f64) {
	ex := c.exprs[e]
	from := c.types[ex.type].scalar

	switch to {
	case .Float:
		if from == .Float {
			return 0, f64(f32(ex.fval))
		}

		return 0, f64(f32(ex.ival))

	case .Int:
		if from == .Float {
			return i64(i32(ex.fval)), 0
		}

		return i64(i32(ex.ival)), 0

	case .Uint:
		if from == .Float {
			return i64(u32(ex.fval)), 0
		}

		return i64(u32(ex.ival)), 0

	case .Bool:
		if from == .Float {
			return ex.fval != 0 ? 1 : 0, 0
		}

		return ex.ival != 0 ? 1 : 0, 0

	case .None:
	}

	return 0, 0
}

make_cast :: proc(c: ^Compiler, e: Expr_Index, to: Type_Index) -> Expr_Index {
	ex := c.exprs[e]

	if ex.type == to {
		return e
	}

	to_type := c.types[to]

	if ex.kind == .Literal && to_type.kind == .Scalar {
		ival, fval := fold_cast(c, e, to_type.scalar)
		return new_literal(c, to, ival, fval, ex.file, ex.line)
	}

	args_start := i32(len(c.expr_args))
	append(&c.expr_args, e)

	return new_expr(c, Expr {
		kind = .Construct,
		type = to,
		args_start = args_start,
		args_count = 1,
		file = ex.file,
		line = ex.line,
	})
}

can_convert :: proc(c: ^Compiler, from: Type_Index, to: Type_Index) -> bool {
	if from == to {
		return true
	}

	ft := c.types[from]
	tt := c.types[to]

	if ft.kind != tt.kind {
		return false
	}

	if ft.kind != .Scalar && ft.kind != .Vector {
		return false
	}

	if ft.size != tt.size {
		return false
	}

	if ft.scalar == .Bool || tt.scalar == .Bool {
		return false
	}

	return scalar_rank(ft.scalar) < scalar_rank(tt.scalar)
}

convert_to :: proc(c: ^Compiler, e: Expr_Index, to: Type_Index, what: string) -> Expr_Index {
	ex := c.exprs[e]

	if ex.type == to {
		return e
	}

	if c.failed {
		return e
	}

	if !can_convert(c, ex.type, to) {
		compile_error(c, ex.file, ex.line, "Cannot convert %s from '%s' to '%s'", what, type_name(c, ex.type), type_name(c, to))
		return e
	}

	return make_cast(c, e, to)
}

Binary_Types :: struct {
	a: Type_Index,
	b: Type_Index,
	result: Type_Index,
}

binary_types :: proc(c: ^Compiler, op: Token_Kind, ta: Type_Index, tb: Type_Index) -> (res: Binary_Types, ok: bool) {
	a := c.types[ta]
	b := c.types[tb]

	#partial switch op {
	case .Plus, .Minus, .Star, .Slash:
		if !type_is_numeric(c, ta) {
			return
		}

		if !type_is_numeric(c, tb) {
			return
		}

		common := scalar_rank(a.scalar) > scalar_rank(b.scalar) ? a.scalar : b.scalar
		res.a = retype(c, ta, common)
		res.b = retype(c, tb, common)

		if a.kind == .Scalar {
			res.result = res.b
			return res, true
		}

		if b.kind == .Scalar {
			res.result = res.a
			return res, true
		}

		if a.size != b.size {
			return
		}

		if a.kind == b.kind {
			res.result = res.a
			return res, true
		}

		if op != .Star {
			return
		}

		res.result = a.kind == .Vector ? res.a : res.b
		return res, true

	case .Percent, .Amp, .Pipe, .Caret:
		if !type_is_scalar_or_vector(c, ta) || !type_is_scalar_or_vector(c, tb) {
			return
		}

		if a.scalar != .Int && a.scalar != .Uint {
			return
		}

		if b.scalar != .Int && b.scalar != .Uint {
			return
		}

		common := scalar_rank(a.scalar) > scalar_rank(b.scalar) ? a.scalar : b.scalar
		res.a = retype(c, ta, common)
		res.b = retype(c, tb, common)

		if a.kind == .Scalar {
			res.result = res.b
			return res, true
		}

		if b.kind == .Scalar {
			res.result = res.a
			return res, true
		}

		if a.size != b.size {
			return
		}

		res.result = res.a
		return res, true

	case .Shl, .Shr:
		if !type_is_scalar_or_vector(c, ta) || !type_is_scalar_or_vector(c, tb) {
			return
		}

		if a.scalar != .Int && a.scalar != .Uint {
			return
		}

		if b.scalar != .Int && b.scalar != .Uint {
			return
		}

		if b.kind == .Vector && a.size != b.size {
			return
		}

		return { ta, tb, ta }, true

	case .Lt, .Gt, .Le, .Ge:
		if a.kind != .Scalar || b.kind != .Scalar {
			return
		}

		if a.scalar == .Bool || b.scalar == .Bool {
			return
		}

		common := scalar_rank(a.scalar) > scalar_rank(b.scalar) ? a.scalar : b.scalar
		return { type_vec(common, 1), type_vec(common, 1), T_BOOL }, true

	case .Eq_Eq, .Not_Eq:
		if type_contains_sampler(c, ta) || a.kind == .Void {
			return
		}

		if ta == tb {
			return { ta, tb, T_BOOL }, true
		}

		if can_convert(c, ta, tb) {
			return { tb, tb, T_BOOL }, true
		}

		if can_convert(c, tb, ta) {
			return { ta, ta, T_BOOL }, true
		}

		return

	case .And_And, .Or_Or, .Xor_Xor:
		if ta != T_BOOL || tb != T_BOOL {
			return
		}

		return { T_BOOL, T_BOOL, T_BOOL }, true
	}

	return
}

fold_binary :: proc(c: ^Compiler, op: Token_Kind, a: Expr_Index, b: Expr_Index, result_type: Type_Index) -> (e: Expr_Index, ok: bool) {
	ea := c.exprs[a]
	eb := c.exprs[b]

	if ea.kind != .Literal || eb.kind != .Literal {
		return
	}

	operand := c.types[ea.type]

	if operand.kind != .Scalar || c.types[eb.type].kind != .Scalar {
		return
	}

	ival: i64
	fval: f64

	switch operand.scalar {
	case .Float:
		x := f32(ea.fval)
		y := f32(eb.fval)

		#partial switch op {
		case .Plus: fval = f64(x + y)
		case .Minus: fval = f64(x - y)
		case .Star: fval = f64(x * y)
		case .Slash:
			if y == 0 {
				return
			}

			fval = f64(x / y)

		case .Lt: ival = x < y ? 1 : 0
		case .Gt: ival = x > y ? 1 : 0
		case .Le: ival = x <= y ? 1 : 0
		case .Ge: ival = x >= y ? 1 : 0
		case .Eq_Eq: ival = x == y ? 1 : 0
		case .Not_Eq: ival = x != y ? 1 : 0
		case: return
		}

	case .Int:
		x := i32(ea.ival)
		y := i32(eb.ival)

		#partial switch op {
		case .Plus: ival = i64(x + y)
		case .Minus: ival = i64(x - y)
		case .Star: ival = i64(x * y)
		case .Slash:
			if y == 0 || (y == -1 && x == min(i32)) {
				return
			}

			ival = i64(x / y)

		case .Percent:
			if y == 0 || (y == -1 && x == min(i32)) {
				return
			}

			ival = i64(x % y)

		case .Amp: ival = i64(x & y)
		case .Pipe: ival = i64(x | y)
		case .Caret: ival = i64(x ~ y)
		case .Shl: ival = i64(x << u32(y & 31))
		case .Shr: ival = i64(x >> u32(y & 31))
		case .Lt: ival = x < y ? 1 : 0
		case .Gt: ival = x > y ? 1 : 0
		case .Le: ival = x <= y ? 1 : 0
		case .Ge: ival = x >= y ? 1 : 0
		case .Eq_Eq: ival = x == y ? 1 : 0
		case .Not_Eq: ival = x != y ? 1 : 0
		case: return
		}

	case .Uint:
		x := u32(ea.ival)
		y := u32(eb.ival)

		#partial switch op {
		case .Plus: ival = i64(x + y)
		case .Minus: ival = i64(x - y)
		case .Star: ival = i64(x * y)
		case .Slash:
			if y == 0 {
				return
			}

			ival = i64(x / y)

		case .Percent:
			if y == 0 {
				return
			}

			ival = i64(x % y)

		case .Amp: ival = i64(x & y)
		case .Pipe: ival = i64(x | y)
		case .Caret: ival = i64(x ~ y)
		case .Shl: ival = i64(x << (y & 31))
		case .Shr: ival = i64(x >> (y & 31))
		case .Lt: ival = x < y ? 1 : 0
		case .Gt: ival = x > y ? 1 : 0
		case .Le: ival = x <= y ? 1 : 0
		case .Ge: ival = x >= y ? 1 : 0
		case .Eq_Eq: ival = x == y ? 1 : 0
		case .Not_Eq: ival = x != y ? 1 : 0
		case: return
		}

	case .Bool:
		x := ea.ival != 0
		y := eb.ival != 0

		#partial switch op {
		case .And_And: ival = x && y ? 1 : 0
		case .Or_Or: ival = x || y ? 1 : 0
		case .Xor_Xor: ival = x != y ? 1 : 0
		case .Eq_Eq: ival = x == y ? 1 : 0
		case .Not_Eq: ival = x != y ? 1 : 0
		case: return
		}

	case .None:
		return
	}

	return new_literal(c, result_type, ival, fval, ea.file, ea.line), true
}

check_binary :: proc(c: ^Compiler, op_tok: Token, a: Expr_Index, b: Expr_Index) -> Expr_Index {
	if c.failed {
		return a
	}

	ta := c.exprs[a].type
	tb := c.exprs[b].type
	types, types_ok := binary_types(c, op_tok.kind, ta, tb)

	if !types_ok {
		compile_error(c, op_tok.file, op_tok.line, "Operator '%s' cannot be used with '%s' and '%s'", op_tok.text, type_name(c, ta), type_name(c, tb))
		return a
	}

	ca := make_cast(c, a, types.a)
	cb := make_cast(c, b, types.b)
	folded, folded_ok := fold_binary(c, op_tok.kind, ca, cb, types.result)

	if folded_ok {
		return folded
	}

	return new_expr(c, Expr {
		kind = .Binary,
		op = op_tok.kind,
		type = types.result,
		a = ca,
		b = cb,
		file = op_tok.file,
		line = op_tok.line,
	})
}

is_lvalue :: proc(c: ^Compiler, e: Expr_Index) -> bool {
	ex := c.exprs[e]

	#partial switch ex.kind {
	case .Var:
		v := c.vars[ex.var]

		if v.is_const {
			return false
		}

		switch v.kind {
		case .Local, .Param, .Global, .Output:
			return true

		case .Uniform, .Input:
			return false

		case .Builtin:
			return v.builtin == .Position || v.builtin == .Frag_Depth
		}

	case .Index, .Field:
		return is_lvalue(c, ex.a)

	case .Swizzle:
		for i in 0..<int(ex.swizzle_count) {
			for j in 0..<i {
				if ex.swizzle[i] == ex.swizzle[j] {
					return false
				}
			}
		}

		return is_lvalue(c, ex.a)
	}

	return false
}

expr_root :: proc(c: ^Compiler, e: Expr_Index) -> Expr_Index {
	root := e

	for {
		ex := c.exprs[root]

		if ex.kind != .Index && ex.kind != .Field && ex.kind != .Swizzle {
			return root
		}

		root = ex.a
	}
}

mark_written :: proc(c: ^Compiler, e: Expr_Index) {
	root := c.exprs[expr_root(c, e)]

	if root.kind == .Var {
		c.vars[root.var].written = true
	}
}

mark_dynamic_index :: proc(c: ^Compiler, e: Expr_Index) {
	root := c.exprs[expr_root(c, e)]

	if root.kind == .Var {
		c.vars[root.var].dynamic_index = true
	}
}

expr_is_pure :: proc(c: ^Compiler, e: Expr_Index) -> bool {
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

	if !expr_is_pure(c, ex.a) || !expr_is_pure(c, ex.b) || !expr_is_pure(c, ex.c) {
		return false
	}

	for i in 0..<ex.args_count {
		if !expr_is_pure(c, c.expr_args[ex.args_start + i]) {
			return false
		}
	}

	return true
}

compound_op :: proc(kind: Token_Kind) -> Token_Kind {
	#partial switch kind {
	case .Add_Assign: return .Plus
	case .Sub_Assign: return .Minus
	case .Mul_Assign: return .Star
	case .Div_Assign: return .Slash
	case .Mod_Assign: return .Percent
	case .And_Assign: return .Amp
	case .Or_Assign: return .Pipe
	case .Xor_Assign: return .Caret
	case .Shl_Assign: return .Shl
	case .Shr_Assign: return .Shr
	}

	return .EOF
}

check_assign :: proc(c: ^Compiler, op_tok: Token, lhs: Expr_Index, rhs: Expr_Index) -> Expr_Index {
	if c.failed {
		return lhs
	}

	if !is_lvalue(c, lhs) {
		compile_error(c, op_tok.file, op_tok.line, "The left side of '%s' cannot be assigned to", op_tok.text)
		return lhs
	}

	mark_written(c, lhs)
	lhs_type := c.exprs[lhs].type
	value := rhs

	if op_tok.kind == .Assign {
		value = convert_to(c, rhs, lhs_type, "assigned value")
	} else {
		rhs_type := c.exprs[rhs].type
		types, types_ok := binary_types(c, compound_op(op_tok.kind), lhs_type, rhs_type)

		if !types_ok || types.a != lhs_type || types.result != lhs_type {
			compile_error(c, op_tok.file, op_tok.line, "Operator '%s' cannot be used with '%s' and '%s'", op_tok.text, type_name(c, lhs_type), type_name(c, rhs_type))
			return lhs
		}

		value = make_cast(c, rhs, types.b)
	}

	return new_expr(c, Expr {
		kind = .Assign,
		op = op_tok.kind,
		type = lhs_type,
		a = lhs,
		b = value,
		file = op_tok.file,
		line = op_tok.line,
	})
}

parse_expr :: proc(c: ^Compiler) -> Expr_Index {
	e := parse_assign(c)

	for peek(c) == .Comma {
		tok := advance(c)
		r := parse_assign(c)

		e = new_expr(c, Expr {
			kind = .Comma,
			type = c.exprs[r].type,
			a = e,
			b = r,
			file = tok.file,
			line = tok.line,
		})
	}

	return e
}

parse_assign :: proc(c: ^Compiler) -> Expr_Index {
	lhs := parse_ternary(c)
	k := peek(c)

	if k >= .Assign && k <= .Shr_Assign {
		tok := advance(c)
		rhs := parse_assign(c)
		return check_assign(c, tok, lhs, rhs)
	}

	return lhs
}

parse_ternary :: proc(c: ^Compiler) -> Expr_Index {
	cond := parse_binary(c, 1)

	if peek(c) != .Question {
		return cond
	}

	tok := advance(c)
	a := parse_assign(c)
	expect(c, .Colon, "':'")
	b := parse_assign(c)

	if c.failed {
		return cond
	}

	if c.exprs[cond].type != T_BOOL {
		compile_error(c, tok.file, tok.line, "The condition of '?' must be a bool")
		return cond
	}

	ta := c.exprs[a].type
	tb := c.exprs[b].type

	if can_convert(c, ta, tb) {
		a = make_cast(c, a, tb)
	} else if can_convert(c, tb, ta) {
		b = make_cast(c, b, ta)
	} else {
		compile_error(c, tok.file, tok.line, "The two results of '?' have different types: '%s' and '%s'", type_name(c, ta), type_name(c, tb))
		return cond
	}

	return new_expr(c, Expr {
		kind = .Ternary,
		type = c.exprs[a].type,
		a = cond,
		b = a,
		c = b,
		file = tok.file,
		line = tok.line,
	})
}

binary_precedence :: proc(kind: Token_Kind) -> int {
	#partial switch kind {
	case .Or_Or: return 1
	case .Xor_Xor: return 2
	case .And_And: return 3
	case .Pipe: return 4
	case .Caret: return 5
	case .Amp: return 6
	case .Eq_Eq, .Not_Eq: return 7
	case .Lt, .Gt, .Le, .Ge: return 8
	case .Shl, .Shr: return 9
	case .Plus, .Minus: return 10
	case .Star, .Slash, .Percent: return 11
	}

	return 0
}

parse_binary :: proc(c: ^Compiler, min_precedence: int) -> Expr_Index {
	lhs := parse_unary(c)

	for {
		prec := binary_precedence(peek(c))

		if prec < min_precedence || prec == 0 {
			break
		}

		tok := advance(c)
		rhs := parse_binary(c, prec + 1)
		lhs = check_binary(c, tok, lhs, rhs)
	}

	return lhs
}

parse_unary :: proc(c: ^Compiler) -> Expr_Index {
	k := peek(c)

	if k != .Minus && k != .Plus && k != .Not && k != .Tilde && k != .Inc && k != .Dec {
		return parse_postfix(c)
	}

	tok := advance(c)
	a := parse_unary(c)

	if c.failed {
		return a
	}

	ea := c.exprs[a]
	ty := c.types[ea.type]

	#partial switch k {
	case .Plus, .Minus:
		if !type_is_numeric(c, ea.type) {
			compile_error(c, tok.file, tok.line, "Operator '%s' cannot be used with '%s'", tok.text, type_name(c, ea.type))
			return a
		}

		if k == .Plus {
			return a
		}

		if ea.kind == .Literal {
			if ty.scalar == .Float {
				return new_literal(c, ea.type, 0, -ea.fval, tok.file, tok.line)
			}

			if ty.scalar == .Int {
				return new_literal(c, ea.type, i64(-i32(ea.ival)), 0, tok.file, tok.line)
			}
		}

	case .Not:
		if ea.type != T_BOOL {
			compile_error(c, tok.file, tok.line, "Operator '!' needs a bool but got '%s'", type_name(c, ea.type))
			return a
		}

		if ea.kind == .Literal {
			return new_literal(c, T_BOOL, ea.ival != 0 ? 0 : 1, 0, tok.file, tok.line)
		}

	case .Tilde:
		if !type_is_scalar_or_vector(c, ea.type) || (ty.scalar != .Int && ty.scalar != .Uint) {
			compile_error(c, tok.file, tok.line, "Operator '~' needs an integer but got '%s'", type_name(c, ea.type))
			return a
		}

	case .Inc, .Dec:
		if !type_is_numeric(c, ea.type) || !is_lvalue(c, a) {
			compile_error(c, tok.file, tok.line, "Operator '%s' needs a numeric variable", tok.text)
			return a
		}

		mark_written(c, a)
	}

	return new_expr(c, Expr {
		kind = .Unary,
		op = k,
		type = ea.type,
		a = a,
		file = tok.file,
		line = tok.line,
	})
}

swizzle_index :: proc(ch: u8) -> (index: u8, set: u8, ok: bool) {
	switch ch {
	case 'x': return 0, 0, true
	case 'y': return 1, 0, true
	case 'z': return 2, 0, true
	case 'w': return 3, 0, true
	case 'r': return 0, 1, true
	case 'g': return 1, 1, true
	case 'b': return 2, 1, true
	case 'a': return 3, 1, true
	case 's': return 0, 2, true
	case 't': return 1, 2, true
	case 'p': return 2, 2, true
	case 'q': return 3, 2, true
	}

	return 0, 0, false
}

parse_postfix :: proc(c: ^Compiler) -> Expr_Index {
	e := parse_primary(c)

	for !c.failed {
		k := peek(c)

		if k == .LBracket {
			tok := advance(c)
			idx := parse_expr(c)
			expect(c, .RBracket, "']'")

			if c.failed {
				return e
			}

			idx_type := c.exprs[idx].type

			if idx_type != T_INT && idx_type != T_UINT {
				compile_error(c, tok.file, tok.line, "An index must be an int but got '%s'", type_name(c, idx_type))
				return e
			}

			base := c.types[c.exprs[e].type]
			result: Type_Index
			limit: int

			#partial switch base.kind {
			case .Array:
				result = base.elem
				limit = int(base.len)

			case .Vector:
				result = type_vec(base.scalar, 1)
				limit = int(base.size)

			case .Matrix:
				result = type_vec(.Float, int(base.size))
				limit = int(base.size)

			case:
				compile_error(c, tok.file, tok.line, "'%s' cannot be indexed", type_name(c, c.exprs[e].type))
				return e
			}

			idx_expr := c.exprs[idx]

			if idx_expr.kind == .Literal && (idx_expr.ival < 0 || int(idx_expr.ival) >= limit) {
				compile_error(c, tok.file, tok.line, "Index %d is out of range, the size is %d", idx_expr.ival, limit)
				return e
			}

			if idx_expr.kind != .Literal && base.kind != .Vector {
				mark_dynamic_index(c, e)
			}

			e = new_expr(c, Expr {
				kind = .Index,
				type = result,
				a = e,
				b = idx,
				file = tok.file,
				line = tok.line,
			})

			continue
		}

		if k == .Dot {
			advance(c)
			name := expect(c, .Ident, "a field name")

			if c.failed {
				return e
			}

			base_type := c.exprs[e].type
			base := c.types[base_type]

			if name.text == "length" && peek(c) == .LParen && (base.kind == .Array || base.kind == .Vector || base.kind == .Matrix) {
				advance(c)
				expect(c, .RParen, "')'")
				e = new_literal(c, T_INT, base.kind == .Array ? i64(base.len) : i64(base.size), 0, name.file, name.line)
				continue
			}

			if base.kind == .Struct {
				field := -1

				for f, f_idx in base.fields {
					if f.name == name.text {
						field = f_idx
						break
					}
				}

				if field == -1 {
					compile_error(c, name.file, name.line, "'%s' has no field called '%s'", base.name, name.text)
					return e
				}

				e = new_expr(c, Expr {
					kind = .Field,
					type = base.fields[field].type,
					a = e,
					field = i32(field),
					file = name.file,
					line = name.line,
				})

				continue
			}

			if base.kind != .Vector || len(name.text) > 4 {
				compile_error(c, name.file, name.line, "'%s' has no field called '%s'", type_name(c, base_type), name.text)
				return e
			}

			sw := Expr {
				kind = .Swizzle,
				a = e,
				swizzle_count = u8(len(name.text)),
				type = type_vec(base.scalar, len(name.text)),
				file = name.file,
				line = name.line,
			}

			first_set: u8

			for i in 0..<len(name.text) {
				index, set, sw_ok := swizzle_index(name.text[i])

				if i == 0 {
					first_set = set
				}

				if !sw_ok || set != first_set || index >= base.size {
					compile_error(c, name.file, name.line, "'%s' is not a valid swizzle of '%s'", name.text, base.name)
					return e
				}

				sw.swizzle[i] = index
			}

			e = new_expr(c, sw)
			continue
		}

		if k == .Inc || k == .Dec {
			tok := advance(c)

			if !type_is_numeric(c, c.exprs[e].type) || !is_lvalue(c, e) {
				compile_error(c, tok.file, tok.line, "Operator '%s' needs a numeric variable", tok.text)
				return e
			}

			mark_written(c, e)

			e = new_expr(c, Expr {
				kind = .Unary,
				op = k,
				postfix = true,
				type = c.exprs[e].type,
				a = e,
				file = tok.file,
				line = tok.line,
			})

			continue
		}

		break
	}

	return e
}

parse_args :: proc(c: ^Compiler, args: ^[MAX_CALL_ARGS]Expr_Index) -> int {
	count := 0

	if accept(c, .RParen) {
		return 0
	}

	if peek(c) == .Ident && c.tokens[c.tok].text == "void" && peek_at(c, 1) == .RParen {
		advance(c)
		advance(c)
		return 0
	}

	for !c.failed {
		if count >= MAX_CALL_ARGS {
			t := c.tokens[c.tok]
			compile_error(c, t.file, t.line, "Too many arguments")
			return 0
		}

		args[count] = parse_assign(c)
		count += 1

		if accept(c, .Comma) {
			continue
		}

		expect(c, .RParen, "')'")
		break
	}

	return count
}

store_args :: proc(c: ^Compiler, args: []Expr_Index) -> (start: i32, count: i32) {
	start = i32(len(c.expr_args))
	append(&c.expr_args, ..args)
	return start, i32(len(args))
}

parse_primary :: proc(c: ^Compiler) -> Expr_Index {
	tok := advance(c)

	#partial switch tok.kind {
	case .Int_Lit, .Uint_Lit:
		value: u64
		value_ok: bool

		if len(tok.text) > 2 && (tok.text[1] == 'x' || tok.text[1] == 'X') {
			value, value_ok = strconv.parse_u64_of_base(tok.text[2:], 16)
		} else if len(tok.text) > 1 && tok.text[0] == '0' {
			value, value_ok = strconv.parse_u64_of_base(tok.text[1:], 8)
		} else {
			value, value_ok = strconv.parse_u64_of_base(tok.text, 10)
		}

		if !value_ok || value > 0xffffffff {
			compile_error(c, tok.file, tok.line, "'%s' is not a valid integer", tok.text)
			return 0
		}

		if tok.kind == .Uint_Lit {
			return new_literal(c, T_UINT, i64(u32(value)), 0, tok.file, tok.line)
		}

		return new_literal(c, T_INT, i64(i32(u32(value))), 0, tok.file, tok.line)

	case .Float_Lit:
		value, value_ok := strconv.parse_f64(tok.text)

		if !value_ok {
			compile_error(c, tok.file, tok.line, "'%s' is not a valid number", tok.text)
			return 0
		}

		return new_literal(c, T_FLOAT, 0, f64(f32(value)), tok.file, tok.line)

	case .Kw_True:
		return new_literal(c, T_BOOL, 1, 0, tok.file, tok.line)

	case .Kw_False:
		return new_literal(c, T_BOOL, 0, 0, tok.file, tok.line)

	case .LParen:
		e := parse_expr(c)
		expect(c, .RParen, "')'")
		return e

	case .Ident:
		type := lookup_type(c, tok)

		if type != T_NONE {
			return parse_construct(c, tok, type)
		}

		v := lookup_var(c, tok)

		if peek(c) == .LParen {
			if v != 0 && c.vars[v].kind != .Global && c.vars[v].kind != .Uniform {
				compile_error(c, tok.file, tok.line, "'%s' is a variable here, so it cannot be called. A variable with the same name as a function hides the function", tok.text)
				return 0
			}

			advance(c)
			return parse_call(c, tok)
		}

		if v == 0 {
			if is_unsupported_type_name(tok.text) {
				compile_error(c, tok.file, tok.line, "The type '%s' is not supported", tok.text)
				return 0
			}

			compile_error(c, tok.file, tok.line, "'%s' is not declared", tok.text)
			return 0
		}

		var := c.vars[v]

		if var.has_const_value {
			return new_literal(c, var.type, var.ival, var.fval, tok.file, tok.line)
		}

		return new_expr(c, Expr {
			kind = .Var,
			type = var.type,
			var = v,
			file = tok.file,
			line = tok.line,
		})
	}

	if tok.kind == .EOF {
		last := c.tokens[max(c.tok - 1, 0)]
		compile_error(c, last.file, last.line, "Expected an expression but the file ended")
		return 0
	}

	compile_error(c, tok.file, tok.line, "Expected an expression but found '%s'", tok.text)
	return 0
}

lookup_var :: proc(c: ^Compiler, tok: Token) -> Var_Index {
	#reverse for v in c.scope {
		if c.vars[v].name == tok.text {
			return v
		}
	}

	builtin := known_names[tok.known].builtin_var
	type: Type_Index

	switch builtin {
	case .None:
		return 0

	case .Position, .Frag_Coord:
		type = T_VEC4

	case .Vertex_ID, .Instance_ID:
		type = T_INT

	case .Front_Facing:
		type = T_BOOL

	case .Frag_Depth:
		type = T_FLOAT
	}

	if builtin == .Frag_Coord {
		c.uses_frag_coord_flip = true
	}

	for i in 1..<len(c.vars) {
		if c.vars[i].kind == .Builtin && c.vars[i].builtin == builtin {
			return Var_Index(i)
		}
	}

	append(&c.vars, Var {
		name = tok.text,
		type = type,
		kind = .Builtin,
		builtin = builtin,
		location = -1,
	})

	return Var_Index(len(c.vars) - 1)
}

parse_construct :: proc(c: ^Compiler, tok: Token, base_type: Type_Index) -> Expr_Index {
	type := base_type
	unsized_array := false

	if accept(c, .LBracket) {
		if accept(c, .RBracket) {
			unsized_array = true
		} else {
			length := parse_const_int(c, "an array size")
			expect(c, .RBracket, "']'")

			if c.failed {
				return 0
			}

			type = type_array(c, base_type, length)
		}
	}

	expect(c, .LParen, "'('")
	args: [MAX_CALL_ARGS]Expr_Index
	count := parse_args(c, &args)

	if c.failed {
		return 0
	}

	if unsized_array {
		type = type_array(c, base_type, count)
	}

	ty := c.types[type]

	if count == 0 {
		compile_error(c, tok.file, tok.line, "'%s(...)' needs at least one value", tok.text)
		return 0
	}

	switch ty.kind {
	case .Scalar:
		if count != 1 {
			compile_error(c, tok.file, tok.line, "'%s(...)' takes exactly one value", tok.text)
			return 0
		}

		arg_type := c.types[c.exprs[args[0]].type]

		if arg_type.kind == .Vector {
			args[0] = new_expr(c, Expr {
				kind = .Swizzle,
				a = args[0],
				swizzle_count = 1,
				type = type_vec(arg_type.scalar, 1),
				file = tok.file,
				line = tok.line,
			})
		} else if arg_type.kind != .Scalar {
			compile_error(c, tok.file, tok.line, "Cannot make a '%s' from a '%s'", tok.text, type_name(c, c.exprs[args[0]].type))
			return 0
		}

		return make_cast(c, args[0], type)

	case .Vector:
		total := 0

		for i in 0..<count {
			arg_type_idx := c.exprs[args[i]].type
			arg_type := c.types[arg_type_idx]

			if arg_type.kind != .Scalar && arg_type.kind != .Vector && arg_type.kind != .Matrix {
				compile_error(c, tok.file, tok.line, "Cannot use a '%s' to make a '%s'", type_name(c, arg_type_idx), tok.text)
				return 0
			}

			if total >= int(ty.size) {
				compile_error(c, tok.file, tok.line, "Too many values for '%s'", tok.text)
				return 0
			}

			total += type_component_count(c, arg_type_idx)

			if arg_type.kind == .Matrix && ty.scalar != .Float {
				compile_error(c, tok.file, tok.line, "Cannot use a '%s' to make a '%s'", type_name(c, arg_type_idx), tok.text)
				return 0
			}

			args[i] = make_cast(c, args[i], retype(c, arg_type_idx, ty.scalar))
		}

		if total < int(ty.size) && !(count == 1 && total == 1) {
			compile_error(c, tok.file, tok.line, "Too few values for '%s'", tok.text)
			return 0
		}

	case .Matrix:
		first := c.types[c.exprs[args[0]].type]

		if count == 1 && first.kind == .Matrix {
			break
		}

		total := 0

		for i in 0..<count {
			arg_type_idx := c.exprs[args[i]].type
			arg_type := c.types[arg_type_idx]

			if arg_type.kind != .Scalar && arg_type.kind != .Vector {
				compile_error(c, tok.file, tok.line, "Cannot use a '%s' to make a '%s'", type_name(c, arg_type_idx), tok.text)
				return 0
			}

			total += int(arg_type.size)
			args[i] = make_cast(c, args[i], retype(c, arg_type_idx, .Float))
		}

		if total != int(ty.size) * int(ty.size) && !(count == 1 && total == 1) {
			compile_error(c, tok.file, tok.line, "'%s' needs %d values but got %d", tok.text, int(ty.size) * int(ty.size), total)
			return 0
		}

	case .Struct:
		if count != len(ty.fields) {
			compile_error(c, tok.file, tok.line, "'%s' has %d fields but got %d values", tok.text, len(ty.fields), count)
			return 0
		}

		for i in 0..<count {
			args[i] = convert_to(c, args[i], ty.fields[i].type, "field value")
		}

	case .Array:
		if count != int(ty.len) {
			compile_error(c, tok.file, tok.line, "The array has %d elements but got %d values", ty.len, count)
			return 0
		}

		for i in 0..<count {
			args[i] = convert_to(c, args[i], ty.elem, "array element")
		}

	case .None, .Void, .Sampler_2D:
		compile_error(c, tok.file, tok.line, "'%s' cannot be constructed", tok.text)
		return 0
	}

	if c.failed {
		return 0
	}

	args_start, args_count := store_args(c, args[:count])

	return new_expr(c, Expr {
		kind = .Construct,
		type = type,
		args_start = args_start,
		args_count = args_count,
		file = tok.file,
		line = tok.line,
	})
}

parse_call :: proc(c: ^Compiler, tok: Token) -> Expr_Index {
	args: [MAX_CALL_ARGS]Expr_Index
	count := parse_args(c, &args)

	if c.failed {
		return 0
	}

	found_name := false
	match := Func_Index(0)

	for pass in 0..<2 {
		for fi in 1..<len(c.funcs) {
			f := c.funcs[fi]

			if f.name != tok.text {
				continue
			}

			if f.stage != .Shared && f.stage != c.stage {
				continue
			}

			found_name = true

			if len(f.params) != count {
				continue
			}

			params_ok := true

			for p, p_idx in f.params {
				param := c.vars[p]
				arg_type := c.exprs[args[p_idx]].type

				if arg_type == param.type {
					continue
				}

				if pass == 1 && param.param_qualifier == .In && can_convert(c, arg_type, param.type) {
					continue
				}

				params_ok = false
				break
			}

			if params_ok {
				match = Func_Index(fi)
				break
			}
		}

		if match != 0 {
			break
		}
	}

	if match != 0 {
		f := c.funcs[match]

		if match == c.cur_func {
			compile_error(c, tok.file, tok.line, "'%s' calls itself, recursion is not allowed", tok.text)
			return 0
		}

		for p, p_idx in f.params {
			param := c.vars[p]

			if param.param_qualifier != .In {
				if !is_lvalue(c, args[p_idx]) {
					compile_error(c, tok.file, tok.line, "Argument %d of '%s' must be a variable that can be written to", p_idx + 1, tok.text)
					return 0
				}

				mark_written(c, args[p_idx])
				continue
			}

			args[p_idx] = make_cast(c, args[p_idx], param.type)
		}

		args_start, args_count := store_args(c, args[:count])

		return new_expr(c, Expr {
			kind = .Call,
			type = f.return_type,
			func = match,
			args_start = args_start,
			args_count = args_count,
			file = tok.file,
			line = tok.line,
		})
	}

	if found_name {
		given := strings.builder_make(c.allocator)

		for i in 0..<count {
			if i > 0 {
				strings.write_string(&given, ", ")
			}

			strings.write_string(&given, type_name(c, c.exprs[args[i]].type))
		}

		compile_error(c, tok.file, tok.line, "No version of '%s' takes the arguments (%s)", tok.text, strings.to_string(given))
		return 0
	}

	builtin := known_names[tok.known].builtin

	if builtin == .None {
		compile_error(c, tok.file, tok.line, "'%s' is not a known function", tok.text)
		return 0
	}

	result := check_builtin_call(c, builtin, args[:count], tok)

	if c.failed {
		return 0
	}

	if builtin == .DFdx || builtin == .DFdy || builtin == .Fwidth {
		mark_fragment_only(c, tok)
	}

	if builtin == .DFdy {
		c.uses_frag_coord_flip = true
	}

	args_start, args_count := store_args(c, args[:count])

	return new_expr(c, Expr {
		kind = .Builtin_Call,
		type = result,
		builtin = builtin,
		args_start = args_start,
		args_count = args_count,
		file = tok.file,
		line = tok.line,
	})
}

parse_const_int :: proc(c: ^Compiler, what: string) -> int {
	tok := c.tokens[c.tok]
	e := parse_ternary(c)

	if c.failed {
		return 0
	}

	ex := c.exprs[e]

	if ex.kind != .Literal || (ex.type != T_INT && ex.type != T_UINT) {
		compile_error(c, tok.file, tok.line, "Expected %s that is a constant integer", what)
		return 0
	}

	if ex.ival <= 0 || ex.ival > i64(max(i32)) {
		compile_error(c, tok.file, tok.line, "%d is not valid as %s", ex.ival, what)
		return 0
	}

	return int(ex.ival)
}
