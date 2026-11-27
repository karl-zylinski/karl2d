package karl2d_shader_compiler

import "core:slice"

DX_ADD :: 0
DX_AND :: 1
DX_BREAK :: 2
DX_BREAKC :: 3
DX_CONTINUE :: 7
DX_DERIV_RTX :: 11
DX_DERIV_RTY :: 12
DX_DISCARD :: 13
DX_DIV :: 14
DX_DP2 :: 15
DX_ELSE :: 18
DX_ENDIF :: 21
DX_ENDLOOP :: 22
DX_EQ :: 24
DX_EXP :: 25
DX_FRC :: 26
DX_FTOI :: 27
DX_FTOU :: 28
DX_GE :: 29
DX_IADD :: 30
DX_IF :: 31
DX_IEQ :: 32
DX_IGE :: 33
DX_ILT :: 34
DX_IMAX :: 36
DX_IMIN :: 37
DX_IMUL :: 38
DX_INE :: 39
DX_INEG :: 40
DX_ISHL :: 41
DX_ISHR :: 42
DX_ITOF :: 43
DX_LD :: 45
DX_LOG :: 47
DX_LOOP :: 48
DX_LT :: 49
DX_MAD :: 50
DX_MIN :: 51
DX_MAX :: 52
DX_MOV :: 54
DX_MOVC :: 55
DX_MUL :: 56
DX_NE :: 57
DX_NOT :: 59
DX_OR :: 60
DX_RESINFO :: 61
DX_RET :: 62
DX_ROUND_NE :: 64
DX_ROUND_NI :: 65
DX_ROUND_PI :: 66
DX_ROUND_Z :: 67
DX_RSQ :: 68
DX_SAMPLE :: 69
DX_SAMPLE_L :: 72
DX_SAMPLE_B :: 74
DX_SQRT :: 75
DX_SINCOS :: 77
DX_UDIV :: 78
DX_ULT :: 79
DX_UGE :: 80
DX_UMAX :: 83
DX_UMIN :: 84
DX_USHR :: 85
DX_UTOF :: 86
DX_XOR :: 87
DX_TEST_NZ :: 0x40000

Dx_Space :: enum u8 {
	Temp,
	Indexable,
	Constants,
	Input,
	Imm,
	Texture,
	Null,
}

Dx_Value :: struct {
	space: Dx_Space,
	count: u8,
	swizzle: [4]u8,
	neg: bool,
	abs: bool,
	has_dyn: bool,
	dyn_component: bool,
	bool_as_uint: bool,
	type: Type_Index,
	reg: u32,
	elem: u32,
	dyn_reg: u32,
	component_reg: u32,
	imm: [4]u32,
}

Dx_Frame :: struct {
	result: Dx_Value,
	wrap: bool,
	has_flag: bool,
	flag: Dx_Value,
}

Dx_Local :: struct {
	name: string,
	type: Type_Index,
	value: Dx_Value,
	start: int,
	end: int,
}

Dx_Marker :: struct {
	code_index: int,
	file: u16,
	line: i32,
}

Dx :: struct {
	c: ^Compiler,
	stage: Stage,
	code: [dynamic]u32,
	top: u32,
	max_temps: u32,
	indexables: [dynamic]u32,
	var_values: []Dx_Value,
	frames: [dynamic]Dx_Frame,
	loops: [dynamic]Stmt_Index,
	last_dst_register_index: int,
	last_dst: Dx_Value,
	pending_dst_register_index: int,
	pending_dst: Dx_Value,
	pending_dst_count: int,
	has_call_result: bool,
	call_result: Dx_Value,
	markers: [dynamic]Dx_Marker,
	locals: [dynamic]Dx_Local,
	mark_file: u16,
	mark_line: i32,
	constants_used: bool,
	constants_dynamic: bool,
	textures_used: bit_set[0..<32],
	position: Dx_Value,
	frag_depth: Dx_Value,
	uses_frag_depth: bool,
	uses_frag_coord: bool,
	uses_vertex_id: bool,
	uses_instance_id: bool,
	uses_front_facing: bool,
}

dx_local :: proc(g: ^Dx, vi: Var_Index, value: Dx_Value) {
	v := g.c.vars[vi]

	if v.name == "" {
		return
	}

	if value.space != .Temp && value.space != .Indexable && value.space != .Input {
		return
	}

	append(&g.locals, Dx_Local { v.name, v.type, value, len(g.code), -1 })
}

dx_close_locals :: proc(g: ^Dx, first: int, last: int) {
	for &l in g.locals[first:last] {
		if l.end == -1 {
			l.end = len(g.code)
		}
	}
}

dx_mark :: proc(g: ^Dx, file: u16, line: i32) {
	if line <= 0 {
		return
	}

	if file == g.mark_file && line == g.mark_line {
		return
	}

	g.mark_file = file
	g.mark_line = line
	append(&g.markers, Dx_Marker { len(g.code), file, line })
}

dx_regs :: proc(g: ^Dx, t: Type_Index) -> u32 {
	ty := g.c.types[t]

	if ty.kind == .Scalar || ty.kind == .Vector {
		return 1
	}

	size, _ := type_std140_layout(g.c, t)
	return u32(max(1, (size + 15) / 16))
}

dx_shape :: proc(g: ^Dx, v: ^Dx_Value, t: Type_Index, first_comp: int) {
	ty := g.c.types[t]
	v.type = t
	v.count = 4
	v.swizzle = { 0, 1, 2, 3 }

	if ty.kind == .Scalar || ty.kind == .Vector {
		v.count = ty.size

		for i in 0..<int(ty.size) {
			v.swizzle[i] = u8(first_comp + i)
		}
	}
}

dx_temp :: proc(g: ^Dx, t: Type_Index) -> Dx_Value {
	v := Dx_Value { space = .Temp, reg = g.top }
	dx_shape(g, &v, t, 0)
	g.top += dx_regs(g, t)
	g.max_temps = max(g.max_temps, g.top)
	return v
}

dx_indexable :: proc(g: ^Dx, t: Type_Index) -> Dx_Value {
	v := Dx_Value { space = .Indexable, reg = u32(len(g.indexables)) }
	dx_shape(g, &v, t, 0)
	append(&g.indexables, dx_regs(g, t))
	return v
}

dx_alloc_var :: proc(g: ^Dx, vi: Var_Index) -> Dx_Value {
	v := g.c.vars[vi]

	if v.dynamic_index {
		return dx_indexable(g, v.type)
	}

	return dx_temp(g, v.type)
}

dx_sub :: proc(g: ^Dx, v: Dx_Value, byte_offset: int, t: Type_Index) -> Dx_Value {
	r := v
	r.dyn_component = false
	r.neg = false
	r.abs = false

	if v.space == .Temp || v.space == .Input {
		r.reg += u32(byte_offset / 16)
	} else {
		r.elem += u32(byte_offset / 16)
	}

	dx_shape(g, &r, t, (byte_offset % 16) / 4)

	if r.bool_as_uint && g.c.types[t].kind != .Scalar && g.c.types[t].kind != .Vector {
		r.bool_as_uint = false
	}

	return r
}

dx_reg_at :: proc(v: Dx_Value, k: u32, count: int, t: Type_Index) -> Dx_Value {
	r := v

	if v.space == .Temp || v.space == .Input {
		r.reg += k
	} else {
		r.elem += k
	}

	r.count = u8(count)
	r.swizzle = { 0, 1, 2, 3 }
	r.type = t
	return r
}

dx_swizzle :: proc(g: ^Dx, v: Dx_Value, comps: []u8) -> Dx_Value {
	r := v
	r.count = u8(len(comps))
	r.type = type_vec(g.c.types[v.type].scalar, len(comps))

	for cidx, i in comps {
		r.swizzle[i] = v.swizzle[cidx]

		if v.space == .Imm {
			r.imm[i] = v.imm[v.count == 1 ? 0 : cidx]
		}
	}

	return r
}

dx_imm_u :: proc(value: u32, t := T_INT) -> Dx_Value {
	return { space = .Imm, count = 1, imm = { value, value, value, value }, type = t }
}

dx_imm_f :: proc(value: f32) -> Dx_Value {
	bits := transmute(u32)value
	return { space = .Imm, count = 1, imm = { bits, bits, bits, bits }, type = T_FLOAT }
}

dx_imm4 :: proc(a, b, c, d: u32, t: Type_Index) -> Dx_Value {
	return { space = .Imm, count = 4, imm = { a, b, c, d }, type = t, swizzle = { 0, 1, 2, 3 } }
}

dx_neg :: proc(g: ^Dx, v: Dx_Value) -> Dx_Value {
	r := v

	if v.space == .Imm {
		is_float := g.c.types[v.type].scalar == .Float

		for &word in r.imm {
			if is_float {
				word ~= 0x80000000
			} else {
				word = u32(-i32(word))
			}
		}

		return r
	}

	r.neg = !v.neg
	return r
}

dx_abs :: proc(v: Dx_Value) -> Dx_Value {
	r := v

	if v.space == .Imm {
		for &word in r.imm {
			word &= 0x7fffffff
		}

		return r
	}

	r.abs = true
	r.neg = false
	return r
}

dx_operand :: proc(g: ^Dx, v: Dx_Value, selection: u32) {
	if v.space == .Null {
		append(&g.code, 0x0000d000)
		return
	}

	token := u32(2) | selection
	dim2 := false

	#partial switch v.space {
	case .Temp:
		token |= 1 << 20

	case .Input:
		token |= 1 << 12 | 1 << 20

	case .Indexable:
		token |= 3 << 12 | 2 << 20
		dim2 = true

	case .Constants:
		token |= 8 << 12 | 2 << 20
		dim2 = true
		g.constants_used = true

		if v.has_dyn {
			g.constants_dynamic = true
		}
	}

	if dim2 && v.has_dyn {
		token |= (v.elem != 0 ? 3 : 2) << 25
	}

	if v.neg || v.abs {
		modifier := u32(1)

		if v.abs {
			modifier = v.neg ? 3 : 2
		}

		append(&g.code, token | 0x80000000, 1 | modifier << 6)
	} else {
		append(&g.code, token)
	}

	if !dim2 {
		append(&g.code, v.reg)
		return
	}

	append(&g.code, v.space == .Constants ? 0 : v.reg)

	if !v.has_dyn || v.elem != 0 {
		append(&g.code, v.elem)
	}

	if v.has_dyn {
		append(&g.code, 0x0010000a, v.dyn_reg)
	}
}

dx_dst :: proc(g: ^Dx, d: Dx_Value) {
	mask: u32

	for i in 0..<int(d.count) {
		mask |= 1 << d.swizzle[i]
	}

	clean := d
	clean.neg = false
	clean.abs = false
	g.pending_dst_count += 1
	g.pending_dst_register_index = len(g.code) + 1
	g.pending_dst = d
	dx_operand(g, clean, mask << 4)
}

dx_src :: proc(g: ^Dx, v: Dx_Value, d: Dx_Value) {
	if v.space == .Null {
		append(&g.code, 0x0000d000)
		return
	}

	if v.space == .Imm {
		if d.count == 1 {
			append(&g.code, 0x00004001, v.imm[0])
			return
		}

		values: [4]u32

		for i in 0..<int(d.count) {
			values[d.swizzle[i]] = v.imm[v.count == 1 ? 0 : i]
		}

		append(&g.code, 0x00004002, values[0], values[1], values[2], values[3])
		return
	}

	if d.count == 1 {
		dx_operand(g, v, 8 | u32(v.swizzle[0]) << 4)
		return
	}

	swz := [4]u8 { v.swizzle[0], v.swizzle[0], v.swizzle[0], v.swizzle[0] }

	for i in 0..<int(d.count) {
		swz[d.swizzle[i]] = v.swizzle[v.count == 1 ? 0 : i]
	}

	dx_operand(g, v, 4 | (u32(swz[0]) | u32(swz[1]) << 2 | u32(swz[2]) << 4 | u32(swz[3]) << 6) << 4)
}

dx_positional :: proc(count: int) -> Dx_Value {
	return { count = u8(count), swizzle = { 0, 1, 2, 3 } }
}

dx_end :: proc(g: ^Dx, start: int) {
	g.code[start] |= u32(len(g.code) - start) << 24
	g.last_dst_register_index = -1

	if g.pending_dst_count == 1 && g.pending_dst.space == .Temp {
		g.last_dst_register_index = g.pending_dst_register_index
		g.last_dst = g.pending_dst
	}

	g.pending_dst_count = 0
}

dx_bare :: proc(g: ^Dx, opcode: u32) {
	append(&g.code, opcode | 1 << 24)
	g.last_dst_register_index = -1
}

dx_ins :: proc(g: ^Dx, opcode: u32, d: Dx_Value, srcs: ..Dx_Value) {
	start := len(g.code)
	append(&g.code, opcode)
	dx_dst(g, d)

	for s in srcs {
		dx_src(g, s, d)
	}

	dx_end(g, start)
}

dx_is_whole_temp :: proc(g: ^Dx, v: Dx_Value) -> bool {
	ty := g.c.types[v.type]

	if v.space != .Temp || v.neg || v.abs || v.dyn_component || v.bool_as_uint {
		return false
	}

	if ty.kind != .Scalar && ty.kind != .Vector {
		return false
	}

	for i in 0..<int(v.count) {
		if int(v.swizzle[i]) != i {
			return false
		}
	}

	return true
}

dx_move_result :: proc(g: ^Dx, dst: Dx_Value, src: Dx_Value, fresh_from: u32) {
	if g.last_dst_register_index >= 0 && dx_is_whole_temp(g, dst) && dx_is_whole_temp(g, src) {
		last := g.last_dst

		if src.reg >= fresh_from && src.reg == last.reg && src.count == last.count && dst.count == src.count && dx_is_whole_temp(g, last) {
			g.code[g.last_dst_register_index] = dst.reg
			g.last_dst.reg = dst.reg
			return
		}
	}

	dx_copy(g, dst, src)
}

dx_imm_is :: proc(v: Dx_Value, n: int, value: f32) -> bool {
	if v.space != .Imm {
		return false
	}

	for i in 0..<n {
		if transmute(f32)v.imm[v.count == 1 ? 0 : i] != value {
			return false
		}
	}

	return true
}

dx_reciprocal :: proc(v: Dx_Value) -> (r: Dx_Value, ok: bool) {
	if v.space != .Imm {
		return v, false
	}

	r = v

	for i in 0..<(v.count == 1 ? 4 : int(v.count)) {
		x := transmute(f32)v.imm[i]

		if x == 0 {
			return v, false
		}

		r.imm[i] = transmute(u32)(1 / x)
	}

	return r, true
}

dx_new_folded :: proc(g: ^Dx, opcode: u32, t: Type_Index, a: Dx_Value, b: Dx_Value) -> Dx_Value {
	n := int(g.c.types[t].size)
	identity := opcode == DX_ADD ? f32(0) : f32(1)

	if a.space == .Imm && b.space == .Imm {
		r := dx_imm4(0, 0, 0, 0, t)
		r.count = u8(n)

		for i in 0..<n {
			x := transmute(f32)a.imm[a.count == 1 ? 0 : i]
			y := transmute(f32)b.imm[b.count == 1 ? 0 : i]
			r.imm[i] = transmute(u32)(opcode == DX_ADD ? x + y : x * y)
		}

		return r
	}

	if int(b.count) == n && dx_imm_is(a, n, identity) {
		return b
	}

	if int(a.count) == n && dx_imm_is(b, n, identity) {
		return a
	}

	return dx_new(g, opcode, t, a, b)
}

dx_new :: proc(g: ^Dx, opcode: u32, t: Type_Index, srcs: ..Dx_Value) -> Dx_Value {
	d := dx_temp(g, t)
	dx_ins(g, opcode, d, ..srcs)
	return d
}

dx_test :: proc(g: ^Dx, opcode: u32, cond: Dx_Value) {
	start := len(g.code)
	append(&g.code, opcode)
	dx_src(g, cond, dx_positional(1))
	dx_end(g, start)
}

dx_copy :: proc(g: ^Dx, dst: Dx_Value, src: Dx_Value) {
	ty := g.c.types[dst.type]

	if ty.kind == .Scalar || ty.kind == .Vector {
		if src.bool_as_uint {
			clean := src
			clean.bool_as_uint = false
			dx_ins(g, DX_INE, dst, clean, dx_imm_u(0))
			return
		}

		dx_ins(g, DX_MOV, dst, src)
		return
	}

	for k in 0..<dx_regs(g, dst.type) {
		dx_ins(g, DX_MOV, dx_reg_at(dst, k, 4, T_VEC4), dx_reg_at(src, k, 4, T_VEC4))
	}
}

dx_reduce :: proc(g: ^Dx, v: Dx_Value, opcode: u32) -> Dx_Value {
	first := dx_swizzle(g, v, { 0 })

	for i in 1..<int(v.count) {
		dx_ins(g, opcode, first, first, dx_swizzle(g, v, { u8(i) }))
	}

	return first
}

dx_component_mask :: proc(g: ^Dx, loc: Dx_Value) -> Dx_Value {
	index := Dx_Value { space = .Temp, reg = loc.component_reg, count = 1, type = T_INT }
	return dx_new(g, DX_IEQ, type_vec(.Int, int(loc.count)), index, dx_imm4(0, 1, 2, 3, T_IVEC4))
}

dx_load :: proc(g: ^Dx, loc: Dx_Value) -> Dx_Value {
	c := g.c

	if loc.dyn_component {
		n := int(loc.count)
		scalar := c.types[loc.type].scalar
		vec := loc
		vec.dyn_component = false
		source := dx_load(g, vec)
		mask := dx_component_mask(g, loc)
		picked := dx_new(g, DX_AND, type_vec(.Int, n), mask, source)
		result := dx_reduce(g, picked, DX_OR)
		result.type = type_vec(scalar, 1)
		return result
	}

	if loc.bool_as_uint {
		t := dx_temp(g, loc.type)
		dx_copy(g, t, loc)
		return t
	}

	return loc
}

dx_store :: proc(g: ^Dx, loc: Dx_Value, value: Dx_Value) {
	if loc.dyn_component {
		vec := loc
		vec.dyn_component = false
		mask := dx_component_mask(g, loc)
		dx_ins(g, DX_MOVC, vec, mask, value, vec)
		return
	}

	dx_copy(g, loc, value)
}

dx_var_value :: proc(g: ^Dx, vi: Var_Index) -> Dx_Value {
	c := g.c
	v := c.vars[vi]

	if v.kind == .Uniform && v.type != T_SAMPLER_2D {
		r := Dx_Value { space = .Constants, elem = u32(v.offset / 16) }
		dx_shape(g, &r, v.type, int(v.offset % 16) / 4)
		r.bool_as_uint = c.types[v.type].scalar == .Bool
		return r
	}

	if v.kind == .Builtin {
		#partial switch v.builtin {
		case .Frag_Coord: g.uses_frag_coord = true
		case .Vertex_ID: g.uses_vertex_id = true
		case .Instance_ID: g.uses_instance_id = true
		case .Front_Facing: g.uses_front_facing = true
		case .Frag_Depth: g.uses_frag_depth = true
		}
	}

	return g.var_values[vi]
}

dx_always_returns :: proc(c: ^Compiler, first: Stmt_Index) -> bool {
	s := first

	for s != 0 {
		st := c.stmts[s]

		#partial switch st.kind {
		case .Return:
			return true

		case .Block:
			if dx_always_returns(c, st.first) {
				return true
			}

		case .If:
			if st.else_body != 0 && dx_always_returns(c, st.body) && dx_always_returns(c, st.else_body) {
				return true
			}
		}

		s = st.next
	}

	return false
}

dx_is_guard :: proc(c: ^Compiler, st: Stmt) -> bool {
	if st.kind != .If || st.else_body != 0 || st.next == 0 {
		return false
	}

	s := st.next

	for s != 0 {
		if c.stmts[s].kind == .Case || c.stmts[s].kind == .Default {
			return false
		}

		s = c.stmts[s].next
	}

	return dx_always_returns(c, st.body)
}

dx_returns :: proc(c: ^Compiler, first: Stmt_Index, tail: bool, in_loop: bool, wrap: ^bool, flag: ^bool) {
	s := first

	for s != 0 {
		st := c.stmts[s]
		is_tail := tail && st.next == 0

		#partial switch st.kind {
		case .Return:
			if !is_tail {
				wrap^ = true
			}

			if in_loop {
				wrap^ = true
				flag^ = true
			}

		case .Block:
			dx_returns(c, st.first, is_tail, in_loop, wrap, flag)

		case .If:
			dx_returns(c, st.body, is_tail || (tail && dx_is_guard(c, st)), in_loop, wrap, flag)
			dx_returns(c, st.else_body, is_tail, in_loop, wrap, flag)

		case .For, .While, .Do_While:
			dx_returns(c, st.body, false, true, wrap, flag)

		case .Switch:
			dx_returns(c, st.first, false, true, wrap, flag)
		}

		s = st.next
	}
}

dx_epilogue :: proc(g: ^Dx) {
	c := g.c

	if g.stage == .Vertex {
		out := Dx_Value { space = .Temp, reg = 0, count = 4, swizzle = { 0, 1, 2, 3 }, type = T_VEC4 }
		dx_output(g, 0, out, g.position)

		for vary, vary_idx in c.varyings {
			value := g.var_values[vary.vertex_var]
			dx_output(g, u32(vary_idx + 1), value, value)
		}
	} else {
		value := g.var_values[c.frag_output]
		dx_output(g, 0, value, value)

		if g.uses_frag_depth {
			start := len(g.code)
			append(&g.code, DX_MOV, 0x0000c001)
			dx_src(g, g.frag_depth, dx_positional(1))
			dx_end(g, start)
		}
	}

	dx_bare(g, DX_RET)
}

dx_output :: proc(g: ^Dx, register: u32, shape: Dx_Value, value: Dx_Value) {
	mask := (u32(1) << shape.count) - 1
	d := shape
	d.swizzle = { 0, 1, 2, 3 }
	start := len(g.code)
	append(&g.code, DX_MOV, 0x00102002 | mask << 4, register)
	dx_src(g, value, d)
	dx_end(g, start)
}

dx_loop_step :: proc(g: ^Dx, loop: Stmt) {
	if loop.kind == .Do_While {
		dx_test(g, DX_BREAKC, dx_expr(g, loop.expr))
	} else if loop.post != 0 {
		dx_expr(g, loop.post)
	}
}

dx_stmts :: proc(g: ^Dx, first: Stmt_Index) {
	c := g.c
	s := first
	first_local := len(g.locals)

	stmts: for s != 0 && !c.failed {
		st := c.stmts[s]
		mark := g.top

		if st.kind != .Block {
			dx_mark(g, st.file, st.line)
		}

		switch st.kind {
		case .None:

		case .Block:
			dx_stmts(g, st.first)
			g.top = mark

		case .Decl:
			value := dx_alloc_var(g, st.var)
			g.var_values[st.var] = value
			decl_mark := g.top
			dx_local(g, st.var, value)

			if st.expr != 0 {
				if c.exprs[st.expr].kind == .Call && value.space == .Temp {
					g.has_call_result = true
					g.call_result = value
				}

				init := dx_expr(g, st.expr)
				g.has_call_result = false
				v := c.vars[st.var]

				if init.space == .Imm && init.count == c.types[v.type].size && !v.written && !v.dynamic_index {
					g.var_values[st.var] = init
				} else if init.space != value.space || init.reg != value.reg || init.space != .Temp {
					dx_move_result(g, value, init, decl_mark)
				}
			}

			g.top = decl_mark

		case .Expr:
			if c.exprs[st.expr].kind == .Assign {
				dx_assign(g, c.exprs[st.expr], true, mark)
			} else {
				dx_expr(g, st.expr)
			}

			g.top = mark

		case .If:
			cond := dx_expr(g, st.expr)
			dx_test(g, DX_IF | DX_TEST_NZ, cond)
			g.top = mark
			dx_stmts(g, st.body)
			g.top = mark

			if dx_is_guard(c, st) {
				dx_bare(g, DX_ELSE)
				dx_stmts(g, st.next)
				g.top = mark
				dx_bare(g, DX_ENDIF)
				break stmts
			}

			if st.else_body != 0 {
				dx_bare(g, DX_ELSE)
				dx_stmts(g, st.else_body)
				g.top = mark
			}

			dx_bare(g, DX_ENDIF)

		case .For, .While, .Do_While:
			loop_first_local := len(g.locals)
			dx_stmts(g, st.first)
			loop_last_local := len(g.locals)

			for &l in g.locals[loop_first_local:loop_last_local] {
				l.end = -1
			}

			loop_mark := g.top
			dx_bare(g, DX_LOOP)

			if st.kind != .Do_While && st.expr != 0 {
				cond := dx_expr(g, st.expr)
				dx_test(g, DX_BREAKC, cond)
				g.top = loop_mark
			}

			frame := g.frames[len(g.frames) - 1]
			append(&g.loops, s)
			dx_stmts(g, st.body)
			pop(&g.loops)
			g.top = loop_mark

			dx_loop_step(g, st)

			g.top = loop_mark
			dx_bare(g, DX_ENDLOOP)

			if frame.has_flag {
				dx_test(g, DX_BREAKC | DX_TEST_NZ, frame.flag)
			}

			dx_close_locals(g, loop_first_local, loop_last_local)
			g.top = mark

		case .Return:
			frame := g.frames[len(g.frames) - 1]

			if len(g.frames) == 1 {
				dx_epilogue(g)
				break
			}

			if st.expr != 0 {
				dx_move_result(g, frame.result, dx_expr(g, st.expr), mark)
			}

			g.top = mark

			if !frame.wrap {
				break
			}

			if frame.has_flag {
				dx_ins(g, DX_MOV, frame.flag, dx_imm_u(0xffffffff))
			}

			dx_bare(g, DX_BREAK)

		case .Break:
			dx_bare(g, DX_BREAK)

		case .Continue:
			loop := c.stmts[g.loops[len(g.loops) - 1]]

			dx_loop_step(g, loop)

			g.top = mark
			dx_bare(g, DX_CONTINUE)

		case .Discard:
			dx_test(g, DX_DISCARD | DX_TEST_NZ, dx_imm_u(0xffffffff))

		case .Switch:
			dx_test(g, 76, dx_expr(g, st.expr))
			g.top = mark
			frame := g.frames[len(g.frames) - 1]
			dx_stmts(g, st.first)
			dx_bare(g, 23)

			if frame.has_flag {
				dx_test(g, DX_BREAKC | DX_TEST_NZ, frame.flag)
			}

		case .Case:
			dx_test(g, 6, dx_expr(g, st.expr))

		case .Default:
			dx_bare(g, 10)
		}

		s = st.next
	}

	dx_close_locals(g, first_local, len(g.locals))
}

dx_call :: proc(g: ^Dx, ex: Expr) -> Dx_Value {
	c := g.c
	f := c.funcs[ex.func]
	args := c.expr_args[ex.args_start:ex.args_start + ex.args_count]
	result: Dx_Value

	if g.has_call_result {
		result = g.call_result
		g.has_call_result = false
	} else if f.return_type != T_VOID {
		result = dx_temp(g, f.return_type)
	}

	mark := g.top
	storage := make([]Dx_Value, len(args), c.allocator)
	targets := make([]Dx_Value, len(args), c.allocator)

	for arg, arg_idx in args {
		param := c.vars[f.params[arg_idx]]

		if param.type == T_SAMPLER_2D {
			storage[arg_idx] = dx_place(g, arg)
			continue
		}

		if param.param_qualifier == .In {
			arg_mark := g.top
			value := dx_expr(g, arg)
			root := c.exprs[arg]

			for root.kind == .Index || root.kind == .Field || root.kind == .Swizzle {
				root = c.exprs[root.a]
			}

			from_global := root.kind == .Var && c.vars[root.var].kind == .Global

			if !param.written && !param.dynamic_index && !from_global {
				for later in args[arg_idx + 1:] {
					value = dx_keep(g, value, later)
				}

				storage[arg_idx] = value
				continue
			}

			storage[arg_idx] = dx_alloc_var(g, f.params[arg_idx])
			dx_move_result(g, storage[arg_idx], value, arg_mark)
			continue
		}

		storage[arg_idx] = dx_alloc_var(g, f.params[arg_idx])
		targets[arg_idx] = dx_place(g, arg)

		if param.param_qualifier == .Inout {
			dx_copy(g, storage[arg_idx], dx_load(g, targets[arg_idx]))
		}
	}

	params_first_local := len(g.locals)

	for p, p_idx in f.params {
		g.var_values[p] = storage[p_idx]
		dx_local(g, p, storage[p_idx])
	}

	frame := Dx_Frame { result = result }
	dx_returns(c, c.stmts[f.body].first, true, false, &frame.wrap, &frame.has_flag)

	if frame.has_flag {
		frame.flag = dx_temp(g, T_BOOL)
		dx_ins(g, DX_MOV, frame.flag, dx_imm_u(0))
	}

	if frame.wrap {
		dx_bare(g, DX_LOOP)
	}

	call_file := g.mark_file
	call_line := g.mark_line
	append(&g.frames, frame)
	dx_stmts(g, c.stmts[f.body].first)
	pop(&g.frames)
	dx_close_locals(g, params_first_local, len(g.locals))
	dx_mark(g, call_file, call_line)

	if frame.wrap {
		dx_bare(g, DX_BREAK)
		dx_bare(g, DX_ENDLOOP)
	}

	for p, p_idx in f.params {
		param := c.vars[p]

		if param.type == T_SAMPLER_2D || param.param_qualifier == .In {
			continue
		}

		dx_store(g, targets[p_idx], storage[p_idx])
	}

	g.top = mark
	return result
}

Dx_Signature_Element :: struct {
	name: string,
	index: u32,
	system_value: u32,
	component_type: u32,
	register: u32,
	mask: u32,
	rw_mask: u32,
}

dx_signature :: proc(g: ^Dx, elements: []Dx_Signature_Element) -> []u8 {
	buf := make([dynamic]u8, 0, 8 + len(elements) * 24 + 64, g.c.allocator)
	put_u32(&buf, u32(len(elements)))
	put_u32(&buf, 8)
	names_start := 8 + len(elements) * 24
	resize(&buf, names_start)

	for e, e_idx in elements {
		name_offset := -1

		for prev, prev_idx in elements[:e_idx] {
			if prev.name == e.name {
				name_offset = int(get_u32(buf[:], 8 + prev_idx * 24))
				break
			}
		}

		if name_offset == -1 {
			name_offset = len(buf)
			append(&buf, e.name)
			append(&buf, 0)
		}

		at := 8 + e_idx * 24
		set_u32(buf[:], at, u32(name_offset))
		set_u32(buf[:], at + 4, e.index)
		set_u32(buf[:], at + 8, e.system_value)
		set_u32(buf[:], at + 12, e.component_type)
		set_u32(buf[:], at + 16, e.register)
		set_u32(buf[:], at + 20, e.mask | e.rw_mask << 8)
	}

	for len(buf) % 4 != 0 {
		append(&buf, 0xab)
	}

	return buf[:]
}

dx_component_type :: proc(g: ^Dx, t: Type_Index) -> u32 {
	switch g.c.types[t].scalar {
	case .Uint: return 1
	case .Int: return 2
	case .Float: return 3
	case .Bool, .None:
	}

	return 3
}

dx_decl :: proc(out: ^[dynamic]u32, opcode: u32, operand: u32, register: u32, extra: ..u32) {
	append(out, opcode | u32(3 + len(extra)) << 24, operand, register)
	append(out, ..extra)
}

emit_dxbc :: proc(c: ^Compiler, stage: Stage) -> []u8 {
	context.allocator = c.allocator

	g := &Dx {
		c = c,
		stage = stage,
		var_values = make([]Dx_Value, len(c.vars)),
	}

	g.code = make([dynamic]u32, 0, 4096)
	main_func := c.funcs[c.main_funcs[stage]]
	append(&g.markers, Dx_Marker { 0, main_func.file, main_func.line })
	g.mark_file = main_func.file
	g.mark_line = main_func.line
	inputs := make([dynamic]Dx_Signature_Element, 0, 16)
	outputs := make([dynamic]Dx_Signature_Element, 0, 16)
	varying_base := u32(1)
	vertex_id_register := u32(len(c.inputs))
	instance_id_register := u32(len(c.inputs) + 1)
	front_facing_register := u32(len(c.varyings) + 1)

	for t, t_idx in c.textures {
		g.var_values[t] = { space = .Texture, reg = u32(t_idx), type = T_SAMPLER_2D }
	}

	if stage == .Vertex {
		for i, i_idx in c.inputs {
			v := Dx_Value { space = .Input, reg = u32(i_idx) }
			dx_shape(g, &v, c.vars[i].type, 0)
			g.var_values[i] = v
		}
	}

	for vary, vary_idx in c.varyings {
		if stage == .Vertex {
			continue
		}

		if vary.fragment_var == 0 {
			continue
		}

		v := Dx_Value { space = .Input, reg = varying_base + u32(vary_idx) }
		dx_shape(g, &v, c.vars[vary.fragment_var].type, 0)
		g.var_values[vary.fragment_var] = v
	}

	if stage == .Vertex {
		g.position = dx_temp(g, T_VEC4)
		dx_ins(g, DX_MOV, g.position, dx_imm4(0, 0, 0, transmute(u32)f32(1), T_VEC4))

		for vary in c.varyings {
			v := dx_temp(g, c.vars[vary.vertex_var].type)
			dx_ins(g, DX_MOV, v, dx_imm_u(0))
			g.var_values[vary.vertex_var] = v
		}
	} else {
		v := dx_temp(g, T_VEC4)
		dx_ins(g, DX_MOV, v, dx_imm_u(0))
		g.var_values[c.frag_output] = v
		g.frag_depth = dx_temp(g, T_FLOAT)
	}

	for vi in 1..<len(c.vars) {
		v := c.vars[vi]

		if stage not_in v.used {
			continue
		}

		if v.kind == .Global {
			g.var_values[vi] = dx_alloc_var(g, Var_Index(vi))
			continue
		}

		if v.kind != .Builtin {
			continue
		}

		value := Dx_Value { space = .Input }

		switch v.builtin {
		case .None:
		case .Position: value = g.position
		case .Frag_Coord: value.reg = 0
		case .Vertex_ID: value.reg = vertex_id_register
		case .Instance_ID: value.reg = instance_id_register
		case .Front_Facing: value.reg = front_facing_register
		case .Frag_Depth: value = g.frag_depth
		}

		if value.space == .Input {
			dx_shape(g, &value, v.type, 0)
		}

		g.var_values[vi] = value
	}

	for vi in 1..<len(c.vars) {
		v := c.vars[vi]

		if stage not_in v.used && (stage != .Fragment || Var_Index(vi) != c.frag_output) {
			continue
		}

		if v.kind == .Global || v.kind == .Input || v.kind == .Output {
			dx_local(g, Var_Index(vi), g.var_values[vi])
		}
	}

	for d in c.decls {
		if d.kind != .Var {
			continue
		}

		v := c.vars[d.index]

		if v.kind != .Global || v.init == 0 || stage not_in v.used {
			continue
		}

		mark := g.top
		dx_mark(g, v.file, v.line)
		dx_copy(g, g.var_values[d.index], dx_expr(g, v.init))
		g.top = mark
	}

	main := c.funcs[c.main_funcs[stage]]
	dx_mark(g, main.file, main.line)
	append(&g.frames, Dx_Frame {})
	dx_stmts(g, c.stmts[main.body].first)
	dx_epilogue(g)

	if c.failed {
		return nil
	}

	shader := make([dynamic]u32, 0, len(g.code) + 128)
	append(&shader, stage == .Vertex ? 0x00010040 : 0x00000040, 0)

	if g.constants_used {
		append(&shader, 89 | 4 << 24 | (g.constants_dynamic ? 0x800 : 0), 0x00208e46, 0, u32(c.constants_size / 16))
	}

	for t in 0..<len(c.textures) {
		if t in g.textures_used {
			dx_decl(&shader, 90, 0x00106000, u32(t))
		}
	}

	for t in 0..<len(c.textures) {
		if t in g.textures_used {
			dx_decl(&shader, 88 | 0x1800, 0x00107000, u32(t), 0x5555)
		}
	}

	if stage == .Vertex {
		for i, i_idx in c.inputs {
			v := c.vars[i]
			mask := (u32(1) << c.types[v.type].size) - 1

			append(&inputs, Dx_Signature_Element {
				name = DXBC_INPUT_SEMANTIC,
				index = u32(v.location),
				component_type = 3,
				register = u32(i_idx),
				mask = mask,
				rw_mask = mask,
			})

			dx_decl(&shader, 95, 0x00101002 | mask << 4, u32(i_idx))
		}

		if g.uses_vertex_id {
			append(&inputs, Dx_Signature_Element { name = "SV_VertexID", system_value = 6, component_type = 1, register = vertex_id_register, mask = 1, rw_mask = 1 })
			dx_decl(&shader, 96, 0x00101012, vertex_id_register, 6)
		}

		if g.uses_instance_id {
			append(&inputs, Dx_Signature_Element { name = "SV_InstanceID", system_value = 8, component_type = 1, register = instance_id_register, mask = 1, rw_mask = 1 })
			dx_decl(&shader, 96, 0x00101012, instance_id_register, 8)
		}

		append(&outputs, Dx_Signature_Element { name = "SV_Position", system_value = 1, component_type = 3, register = 0, mask = 0xf })
		dx_decl(&shader, 103, 0x001020f2, 0, 1)

		for vary, vary_idx in c.varyings {
			v := c.vars[vary.vertex_var]
			mask := (u32(1) << c.types[v.type].size) - 1

			append(&outputs, Dx_Signature_Element {
				name = "TEXCOORD",
				index = u32(vary_idx),
				component_type = dx_component_type(g, v.type),
				register = varying_base + u32(vary_idx),
				mask = mask,
				rw_mask = ~mask & 0xf,
			})

			dx_decl(&shader, 101, 0x00102002 | mask << 4, varying_base + u32(vary_idx))
		}
	} else {
		append(&inputs, Dx_Signature_Element { name = "SV_Position", system_value = 1, component_type = 3, register = 0, mask = 0xf, rw_mask = g.uses_frag_coord ? 0xf : 0 })

		if g.uses_frag_coord {
			dx_decl(&shader, 100 | 4 << 11, 0x001010f2, 0, 1)
		}

		for vary, vary_idx in c.varyings {
			v := c.vars[vary.vertex_var]
			mask := (u32(1) << c.types[v.type].size) - 1
			used := vary.fragment_var != 0 && stage in c.vars[vary.fragment_var].used

			append(&inputs, Dx_Signature_Element {
				name = "TEXCOORD",
				index = u32(vary_idx),
				component_type = dx_component_type(g, v.type),
				register = varying_base + u32(vary_idx),
				mask = mask,
				rw_mask = used ? mask : 0,
			})

			if !used {
				continue
			}

			interpolation := u32(2)

			switch v.interpolation {
			case .Smooth:
			case .Flat: interpolation = 1
			}

			dx_decl(&shader, 98 | interpolation << 11, 0x00101002 | mask << 4, varying_base + u32(vary_idx))
		}

		if g.uses_front_facing {
			append(&inputs, Dx_Signature_Element { name = "SV_IsFrontFace", system_value = 9, component_type = 1, register = front_facing_register, mask = 1, rw_mask = 1 })
			dx_decl(&shader, 99 | 1 << 11, 0x00101012, front_facing_register, 9)
		}

		append(&outputs, Dx_Signature_Element { name = "SV_Target", component_type = 3, register = 0, mask = 0xf })
		dx_decl(&shader, 101, 0x001020f2, 0)

		if g.uses_frag_depth {
			append(&outputs, Dx_Signature_Element { name = "SV_Depth", component_type = 3, register = 0xffffffff, mask = 1, rw_mask = 0xe })
			append(&shader, 101 | 2 << 24, 0x0000c001)
		}
	}

	if g.max_temps > 0 {
		append(&shader, 104 | 2 << 24, g.max_temps)
	}

	for size, idx in g.indexables {
		append(&shader, 105 | 4 << 24, u32(idx), size, 4)
	}

	body_start := len(shader)
	append(&shader, ..g.code[:])
	shader[1] = u32(len(shader))

	chunks := [5]Dxbc_Chunk {
		{ "RDEF", emit_rdef(c, stage, g.constants_used, g.textures_used) },
		{ "ISGN", dx_signature(g, inputs[:]) },
		{ "OSGN", dx_signature(g, outputs[:]) },
		{ "SHDR", slice.to_bytes(shader[:]) },
		{},
	}

	if c.options.no_debug_info {
		return dxbc_build_container(chunks[:4], c.allocator)
	}

	lines := make([dynamic]Spdb_Line, 0, len(g.code) / 4)
	marker := 0
	at := 0

	for at < len(g.code) {
		for marker + 1 < len(g.markers) && g.markers[marker + 1].code_index <= at {
			marker += 1
		}

		append(&lines, Spdb_Line { u32(body_start + at) * 4, g.markers[marker].file, g.markers[marker].line })
		at += int(g.code[at] >> 24 & 0x7f)
	}

	locals := make([dynamic]Spdb_Local, 0, len(g.locals))

	for l in g.locals {
		end := l.end == -1 ? len(g.code) : l.end

		if end <= l.start {
			continue
		}

		append(&locals, Spdb_Local {
			name = l.name,
			type = l.type,
			register_kind = l.value.space == .Indexable ? 3 : l.value.space == .Input ? 1 : 0,
			register = l.value.reg,
			offset = u32(body_start + l.start) * 4,
			length = u32(end - l.start) * 4,
		})
	}

	chunks[4] = { "SPDB", emit_spdb(c, stage, shader[:], body_start, lines[:], locals[:]) }
	return dxbc_build_container(chunks[:], c.allocator)
}
