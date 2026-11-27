package karl2d_shader_compiler

import "core:slice"

SPV_STORAGE_UNIFORM_CONSTANT :: 0
SPV_STORAGE_INPUT :: 1
SPV_STORAGE_UNIFORM :: 2
SPV_STORAGE_OUTPUT :: 3
SPV_STORAGE_PRIVATE :: 6
SPV_STORAGE_FUNCTION :: 7

SPV_CONSTANTS_BINDING :: 0
SPV_FIRST_TEXTURE_BINDING :: 1

Spv_Ptr_Type :: struct {
	pointee: u32,
	storage: u32,
	id: u32,
}

Spv_Const :: struct {
	type: u32,
	value: u32,
	id: u32,
}

Spv_Fn_Type :: struct {
	words: []u32,
	id: u32,
}

Spv :: struct {
	c: ^Compiler,
	stage: Stage,
	next_id: u32,
	debug: [dynamic]u32,
	annotations: [dynamic]u32,
	globals: [dynamic]u32,
	code: [dynamic]u32,
	fn_vars: [dynamic]u32,
	body: [dynamic]u32,
	interface: [dynamic]u32,
	ext_glsl: u32,
	type_ids: []u32,
	ptr_types: [dynamic]Spv_Ptr_Type,
	consts: [dynamic]Spv_Const,
	composite_consts: [dynamic]Spv_Const,
	fn_types: [dynamic]Spv_Fn_Type,
	var_ids: []u32,
	var_storage: []u32,
	var_member: []i32,
	func_ids: []u32,
	stmt_labels: []u32,
	file_ids: []u32,
	constants_var: u32,
	image_type: u32,
	cur_label: u32,
	terminated: bool,
	loop_merges: [dynamic]u32,
	loop_continues: [dynamic]u32,
	line_file: u16,
	line: i32,
	uses_image_query: bool,
	uses_frag_depth: bool,
}

spv_id :: proc(g: ^Spv) -> u32 {
	id := g.next_id
	g.next_id += 1
	return id
}

spv_op :: proc(buf: ^[dynamic]u32, opcode: u32, operands: ..u32) {
	append(buf, u32(len(operands) + 1) << 16 | opcode)
	append(buf, ..operands)
}

spv_op_string :: proc(buf: ^[dynamic]u32, opcode: u32, before: []u32, str: string, after: []u32 = {}) {
	str_words := len(str) / 4 + 1
	append(buf, u32(1 + len(before) + str_words + len(after)) << 16 | opcode)
	append(buf, ..before)
	start := len(buf)
	resize(buf, start + str_words)
	bytes := slice.to_bytes(buf[start:])
	copy(bytes, str)
	append(buf, ..after)
}

spv_name :: proc(g: ^Spv, id: u32, name: string) {
	spv_op_string(&g.debug, 5, { id }, name)
}

spv_decorate :: proc(g: ^Spv, id: u32, decoration: u32, values: ..u32) {
	append(&g.annotations, u32(len(values) + 3) << 16 | 71, id, decoration)
	append(&g.annotations, ..values)
}

spv_label :: proc(g: ^Spv, id: u32) {
	spv_op(&g.body, 248, id)
	g.cur_label = id
	g.terminated = false
	g.line = 0
}

spv_code :: proc(g: ^Spv, opcode: u32, operands: ..u32) {
	if g.terminated {
		spv_label(g, spv_id(g))
	}

	spv_op(&g.body, opcode, ..operands)
}

spv_value :: proc(g: ^Spv, opcode: u32, type: u32, operands: ..u32) -> u32 {
	if g.terminated {
		spv_label(g, spv_id(g))
	}

	id := spv_id(g)
	append(&g.body, u32(len(operands) + 3) << 16 | opcode, type, id)
	append(&g.body, ..operands)
	return id
}

spv_branch :: proc(g: ^Spv, target: u32) {
	if g.terminated {
		return
	}

	spv_op(&g.body, 249, target)
	g.terminated = true
}

spv_type :: proc(g: ^Spv, t: Type_Index) -> u32 {
	if g.type_ids[t] != 0 {
		return g.type_ids[t]
	}

	c := g.c
	ty := c.types[t]
	id: u32

	switch ty.kind {
	case .None:
		id = spv_type(g, T_VOID)

	case .Void:
		id = spv_id(g)
		spv_op(&g.globals, 19, id)

	case .Scalar:
		id = spv_id(g)

		switch ty.scalar {
		case .Bool: spv_op(&g.globals, 20, id)
		case .Int: spv_op(&g.globals, 21, id, 32, 1)
		case .Uint: spv_op(&g.globals, 21, id, 32, 0)
		case .Float: spv_op(&g.globals, 22, id, 32)
		case .None:
		}

	case .Vector:
		elem := spv_type(g, type_vec(ty.scalar, 1))
		id = spv_id(g)
		spv_op(&g.globals, 23, id, elem, u32(ty.size))

	case .Matrix:
		column := spv_type(g, type_vec(.Float, int(ty.size)))
		id = spv_id(g)
		spv_op(&g.globals, 24, id, column, u32(ty.size))

	case .Sampler_2D:
		float_type := spv_type(g, T_FLOAT)
		g.image_type = spv_id(g)
		spv_op(&g.globals, 25, g.image_type, float_type, 1, 0, 0, 0, 1, 0)
		id = spv_id(g)
		spv_op(&g.globals, 27, id, g.image_type)

	case .Array:
		elem := spv_type(g, ty.elem)
		length := spv_const(g, T_UINT, u32(ty.len))
		id = spv_id(g)
		spv_op(&g.globals, 28, id, elem, length)
		spv_decorate(g, id, 6, u32(type_array_stride(c, t)))

	case .Struct:
		members := make([]u32, len(ty.fields) + 1, c.allocator)

		for f, f_idx in ty.fields {
			members[f_idx + 1] = spv_type(g, f.type)
		}

		id = spv_id(g)
		members[0] = id
		spv_op(&g.globals, 30, ..members)
		spv_name(g, id, ty.name)

		for f, f_idx in ty.fields {
			spv_member_layout(g, id, f_idx, f.type, int(f.offset))
			spv_op_string(&g.debug, 6, { id, u32(f_idx) }, f.name)
		}
	}

	g.type_ids[t] = id
	return id
}

spv_member_layout :: proc(g: ^Spv, struct_id: u32, member: int, type: Type_Index, offset: int) {
	spv_op(&g.annotations, 72, struct_id, u32(member), 35, u32(offset))
	ty := g.c.types[type]

	if ty.kind == .Array {
		ty = g.c.types[ty.elem]
	}

	if ty.kind == .Matrix {
		spv_op(&g.annotations, 72, struct_id, u32(member), 5)
		spv_op(&g.annotations, 72, struct_id, u32(member), 7, 16)
	}
}

spv_ptr_type :: proc(g: ^Spv, pointee: u32, storage: u32) -> u32 {
	for p in g.ptr_types {
		if p.pointee == pointee && p.storage == storage {
			return p.id
		}
	}

	id := spv_id(g)
	spv_op(&g.globals, 32, id, storage, pointee)
	append(&g.ptr_types, Spv_Ptr_Type { pointee, storage, id })
	return id
}

spv_const :: proc(g: ^Spv, t: Type_Index, value: u32) -> u32 {
	type := spv_type(g, t)

	for k in g.consts {
		if k.type == type && k.value == value {
			return k.id
		}
	}

	id := spv_id(g)

	if t == T_BOOL {
		spv_op(&g.globals, value != 0 ? 41 : 42, type, id)
	} else {
		spv_op(&g.globals, 43, type, id, value)
	}

	append(&g.consts, Spv_Const { type, value, id })
	return id
}

spv_const_splat :: proc(g: ^Spv, t: Type_Index, value: u32) -> u32 {
	ty := g.c.types[t]
	scalar := spv_const(g, type_vec(ty.scalar, 1), value)

	if ty.kind == .Scalar {
		return scalar
	}

	type := spv_type(g, t)

	for k in g.composite_consts {
		if k.type == type && k.value == scalar {
			return k.id
		}
	}

	id := spv_id(g)
	words := [6]u32 { type, id, scalar, scalar, scalar, scalar }
	spv_op(&g.globals, 44, ..words[:2 + int(ty.size)])

	append(&g.composite_consts, Spv_Const { type, scalar, id })
	return id
}

spv_one :: proc(g: ^Spv, t: Type_Index) -> u32 {
	if g.c.types[t].scalar == .Float {
		return spv_const_splat(g, t, transmute(u32)f32(1))
	}

	return spv_const_splat(g, t, 1)
}

spv_zero :: proc(g: ^Spv, t: Type_Index) -> u32 {
	return spv_const_splat(g, t, 0)
}

spv_uniform_type :: proc(g: ^Spv, t: Type_Index) -> Type_Index {
	if g.c.types[t].scalar == .Bool {
		return retype(g.c, t, .Uint)
	}

	return t
}

spv_local :: proc(g: ^Spv, t: Type_Index) -> u32 {
	id := spv_id(g)
	spv_op(&g.fn_vars, 59, spv_ptr_type(g, spv_type(g, t), SPV_STORAGE_FUNCTION), id, SPV_STORAGE_FUNCTION)
	return id
}

spv_global :: proc(g: ^Spv, v: Var_Index, storage: u32) -> u32 {
	var := g.c.vars[v]
	id := spv_id(g)
	spv_op(&g.globals, 59, spv_ptr_type(g, spv_type(g, var.type), storage), id, storage)
	spv_name(g, id, var.name)
	g.var_ids[v] = id
	g.var_storage[v] = storage

	if storage == SPV_STORAGE_INPUT || storage == SPV_STORAGE_OUTPUT {
		append(&g.interface, id)
	}

	return id
}

spv_line :: proc(g: ^Spv, file: u16, line: i32) {
	if line <= 0 {
		return
	}

	if g.terminated {
		spv_label(g, spv_id(g))
	}

	if file == g.line_file && line == g.line {
		return
	}

	g.line_file = file
	g.line = line
	spv_op(&g.body, 8, g.file_ids[file], u32(line), 0)
}

spv_fn_type :: proc(g: ^Spv, f: Func) -> u32 {
	c := g.c
	words := make([]u32, len(f.params) + 1, c.allocator)
	words[0] = spv_type(g, f.return_type)

	for p, p_idx in f.params {
		v := c.vars[p]
		type := spv_type(g, v.type)

		if v.type == T_SAMPLER_2D {
			words[p_idx + 1] = spv_ptr_type(g, type, SPV_STORAGE_UNIFORM_CONSTANT)
		} else if v.param_qualifier == .In {
			words[p_idx + 1] = type
		} else {
			words[p_idx + 1] = spv_ptr_type(g, type, SPV_STORAGE_FUNCTION)
		}
	}

	for ft in g.fn_types {
		if slice.equal(ft.words, words) {
			return ft.id
		}
	}

	id := spv_id(g)
	append(&g.globals, u32(len(words) + 2) << 16 | 33, id)
	append(&g.globals, ..words)
	append(&g.fn_types, Spv_Fn_Type { words, id })
	return id
}

spv_stmts :: proc(g: ^Spv, first: Stmt_Index) {
	c := g.c
	s := first

	for s != 0 {
		st := c.stmts[s]

		if st.kind != .Block && st.kind != .Case && st.kind != .Default {
			spv_line(g, st.file, st.line)
		}

		switch st.kind {
		case .None:

		case .Block:
			spv_stmts(g, st.first)

		case .Decl:
			id := spv_local(g, c.vars[st.var].type)
			spv_name(g, id, c.vars[st.var].name)
			g.var_ids[st.var] = id
			g.var_storage[st.var] = SPV_STORAGE_FUNCTION

			if st.expr != 0 {
				value := spv_expr(g, st.expr)
				spv_code(g, 62, id, value)
			}

		case .Expr:
			spv_expr(g, st.expr)

		case .If:
			cond := spv_expr(g, st.expr)
			then_label := spv_id(g)
			merge_label := spv_id(g)
			else_label := merge_label

			if st.else_body != 0 {
				else_label = spv_id(g)
			}

			spv_code(g, 247, merge_label, 0)
			spv_code(g, 250, cond, then_label, else_label)
			spv_label(g, then_label)
			spv_stmts(g, st.body)
			spv_branch(g, merge_label)

			if st.else_body != 0 {
				spv_label(g, else_label)
				spv_stmts(g, st.else_body)
				spv_branch(g, merge_label)
			}

			spv_label(g, merge_label)

		case .For, .While:
			spv_stmts(g, st.first)
			header := spv_id(g)
			cond_label := spv_id(g)
			body_label := spv_id(g)
			continue_label := spv_id(g)
			merge_label := spv_id(g)
			spv_branch(g, header)
			spv_label(g, header)
			spv_code(g, 246, merge_label, continue_label, 0)
			spv_branch(g, cond_label)
			spv_label(g, cond_label)

			if st.expr != 0 {
				spv_line(g, st.file, st.line)
				cond := spv_expr(g, st.expr)
				spv_code(g, 250, cond, body_label, merge_label)
				g.terminated = true
			} else {
				spv_branch(g, body_label)
			}

			spv_label(g, body_label)
			append(&g.loop_merges, merge_label)
			append(&g.loop_continues, continue_label)
			spv_stmts(g, st.body)
			pop(&g.loop_merges)
			pop(&g.loop_continues)
			spv_branch(g, continue_label)
			spv_label(g, continue_label)

			if st.post != 0 {
				spv_line(g, st.file, st.line)
				spv_expr(g, st.post)
			}

			spv_branch(g, header)
			spv_label(g, merge_label)

		case .Do_While:
			header := spv_id(g)
			body_label := spv_id(g)
			continue_label := spv_id(g)
			merge_label := spv_id(g)
			spv_branch(g, header)
			spv_label(g, header)
			spv_code(g, 246, merge_label, continue_label, 0)
			spv_branch(g, body_label)
			spv_label(g, body_label)
			append(&g.loop_merges, merge_label)
			append(&g.loop_continues, continue_label)
			spv_stmts(g, st.body)
			pop(&g.loop_merges)
			pop(&g.loop_continues)
			spv_branch(g, continue_label)
			spv_label(g, continue_label)
			cond := spv_expr(g, st.expr)
			spv_code(g, 250, cond, header, merge_label)
			g.terminated = true
			spv_label(g, merge_label)

		case .Return:
			if st.expr != 0 {
				value := spv_expr(g, st.expr)
				spv_code(g, 254, value)
			} else {
				spv_code(g, 253)
			}

			g.terminated = true

		case .Break:
			spv_code(g, 249, g.loop_merges[len(g.loop_merges) - 1])
			g.terminated = true

		case .Continue:
			spv_code(g, 249, g.loop_continues[len(g.loop_continues) - 1])
			g.terminated = true

		case .Discard:
			spv_code(g, 252)
			g.terminated = true

		case .Switch:
			selector := spv_expr(g, st.expr)
			merge_label := spv_id(g)
			default_label := merge_label
			targets := make([dynamic]u32, 0, 16, c.allocator)
			label: u32
			previous_was_label := false
			each := st.first

			for each != 0 {
				es := c.stmts[each]

				if es.kind != .Case && es.kind != .Default {
					previous_was_label = false
					each = es.next
					continue
				}

				if !previous_was_label {
					label = spv_id(g)
				}

				previous_was_label = true
				g.stmt_labels[each] = label

				if es.kind == .Default {
					default_label = label
				} else {
					append(&targets, u32(c.exprs[es.expr].ival), label)
				}

				each = es.next
			}

			spv_code(g, 247, merge_label, 0)
			append(&g.body, u32(len(targets) + 3) << 16 | 251, selector, default_label)
			append(&g.body, ..targets[:])
			g.terminated = true
			append(&g.loop_merges, merge_label)
			spv_stmts(g, st.first)
			pop(&g.loop_merges)
			spv_branch(g, merge_label)
			spv_label(g, merge_label)

		case .Case, .Default:
			if g.terminated || g.cur_label != g.stmt_labels[s] {
				spv_branch(g, g.stmt_labels[s])
				spv_label(g, g.stmt_labels[s])
			}
		}

		s = st.next
	}
}

spv_function :: proc(g: ^Spv, fi: Func_Index) {
	c := g.c
	f := c.funcs[fi]
	fn_type := spv_fn_type(g, f)
	clear(&g.fn_vars)
	clear(&g.body)
	g.terminated = false
	g.line = 0
	entry_label := spv_id(g)
	g.cur_label = entry_label
	spv_op(&g.code, 54, spv_type(g, f.return_type), g.func_ids[fi], 0, fn_type)
	spv_name(g, g.func_ids[fi], f.name)

	for p in f.params {
		v := c.vars[p]
		type := spv_type(g, v.type)
		param := spv_id(g)

		if v.type == T_SAMPLER_2D {
			spv_op(&g.code, 55, spv_ptr_type(g, type, SPV_STORAGE_UNIFORM_CONSTANT), param)
			g.var_ids[p] = param
			g.var_storage[p] = SPV_STORAGE_UNIFORM_CONSTANT
			continue
		}

		g.var_storage[p] = SPV_STORAGE_FUNCTION

		if v.param_qualifier != .In {
			spv_op(&g.code, 55, spv_ptr_type(g, type, SPV_STORAGE_FUNCTION), param)
			g.var_ids[p] = param
			continue
		}

		spv_op(&g.code, 55, type, param)
		local := spv_local(g, v.type)
		spv_op(&g.body, 62, local, param)
		g.var_ids[p] = local

		if v.name != "" {
			spv_name(g, local, v.name)
		}
	}

	if fi == c.main_funcs[g.stage] {
		for d in c.decls {
			if d.kind != .Var {
				continue
			}

			v := c.vars[d.index]

			if v.kind != .Global || v.init == 0 || g.stage not_in v.used {
				continue
			}

			spv_line(g, v.file, v.line)
			value := spv_expr(g, v.init)
			spv_code(g, 62, g.var_ids[d.index], value)
		}
	}

	spv_stmts(g, f.body)

	if !g.terminated {
		if f.return_type == T_VOID {
			spv_op(&g.body, 253)
		} else {
			spv_op(&g.body, 255)
		}
	}

	spv_op(&g.code, 248, entry_label)
	append(&g.code, ..g.fn_vars[:])
	append(&g.code, ..g.body[:])
	spv_op(&g.code, 56)
}

emit_spirv :: proc(c: ^Compiler, stage: Stage) -> []u8 {
	context.allocator = c.allocator

	g := &Spv {
		c = c,
		stage = stage,
		next_id = 1,
		type_ids = make([]u32, len(c.types) + 64),
		var_ids = make([]u32, len(c.vars)),
		var_storage = make([]u32, len(c.vars)),
		var_member = make([]i32, len(c.vars)),
		func_ids = make([]u32, len(c.funcs)),
		stmt_labels = make([]u32, len(c.stmts)),
		file_ids = make([]u32, len(c.files)),
	}

	g.debug = make([dynamic]u32, 0, 256)
	g.annotations = make([dynamic]u32, 0, 128)
	g.globals = make([dynamic]u32, 0, 512)
	g.code = make([dynamic]u32, 0, 4096)
	g.fn_vars = make([dynamic]u32, 0, 128)
	g.body = make([dynamic]u32, 0, 2048)
	g.ext_glsl = spv_id(g)

	for f, f_idx in c.files {
		g.file_ids[f_idx] = spv_id(g)
		spv_op_string(&g.debug, 7, { g.file_ids[f_idx] }, f.name)
	}

	for f, f_idx in c.files {
		if len(f.source) < 200000 {
			spv_op_string(&g.debug, 3, { 2, 330, g.file_ids[f_idx] }, string(f.source))
		} else {
			spv_op(&g.debug, 3, 2, 330, g.file_ids[f_idx])
		}
	}
	constants_used := false

	for u, u_idx in c.uniforms {
		g.var_member[u] = i32(u_idx)

		if stage in c.vars[u].used {
			constants_used = true
		}
	}

	if constants_used {
		members := make([]u32, len(c.uniforms) + 1)

		for u, u_idx in c.uniforms {
			members[u_idx + 1] = spv_type(g, spv_uniform_type(g, c.vars[u].type))
		}

		block := spv_id(g)
		members[0] = block
		spv_op(&g.globals, 30, ..members)
		spv_name(g, block, CONSTANTS_BLOCK_NAME)
		spv_decorate(g, block, 2)

		for u, u_idx in c.uniforms {
			v := c.vars[u]
			spv_member_layout(g, block, u_idx, v.type, int(v.offset))
			spv_op_string(&g.debug, 6, { block, u32(u_idx) }, v.name)
		}

		g.constants_var = spv_id(g)
		spv_op(&g.globals, 59, spv_ptr_type(g, block, SPV_STORAGE_UNIFORM), g.constants_var, SPV_STORAGE_UNIFORM)
		spv_decorate(g, g.constants_var, 34, 0)
		spv_decorate(g, g.constants_var, 33, SPV_CONSTANTS_BINDING)
	}

	for t, t_idx in c.textures {
		if stage not_in c.vars[t].used {
			continue
		}

		id := spv_global(g, t, SPV_STORAGE_UNIFORM_CONSTANT)
		spv_decorate(g, id, 34, 0)
		spv_decorate(g, id, 33, u32(SPV_FIRST_TEXTURE_BINDING + t_idx))
	}

	if stage == .Vertex {
		for i in c.inputs {
			id := spv_global(g, i, SPV_STORAGE_INPUT)
			spv_decorate(g, id, 30, u32(c.vars[i].location))
		}
	}

	for vary, vary_idx in c.varyings {
		v := stage == .Vertex ? vary.vertex_var : vary.fragment_var

		if v == 0 {
			continue
		}

		id := spv_global(g, v, stage == .Vertex ? SPV_STORAGE_OUTPUT : SPV_STORAGE_INPUT)
		spv_decorate(g, id, 30, u32(vary_idx))

		switch c.vars[v].interpolation {
		case .Smooth:
		case .Flat: spv_decorate(g, id, 14)
		}
	}

	if stage == .Fragment {
		id := spv_global(g, c.frag_output, SPV_STORAGE_OUTPUT)
		spv_decorate(g, id, 30, 0)
	}

	for vi in 1..<len(c.vars) {
		v := c.vars[vi]

		if stage not_in v.used {
			continue
		}

		if v.kind == .Global {
			spv_global(g, Var_Index(vi), SPV_STORAGE_PRIVATE)
			continue
		}

		if v.kind != .Builtin {
			continue
		}

		builtin: u32
		storage := u32(SPV_STORAGE_INPUT)

		switch v.builtin {
		case .None:
		case .Position:
			builtin = 0
			storage = SPV_STORAGE_OUTPUT

		case .Frag_Coord: builtin = 15
		case .Vertex_ID: builtin = 42
		case .Instance_ID: builtin = 43
		case .Front_Facing: builtin = 17
		case .Frag_Depth:
			builtin = 22
			storage = SPV_STORAGE_OUTPUT
			g.uses_frag_depth = true
		}

		id := spv_global(g, Var_Index(vi), storage)
		spv_decorate(g, id, 11, builtin)
	}

	for fi in 1..<len(c.funcs) {
		if stage in c.funcs[fi].used {
			g.func_ids[fi] = spv_id(g)
		}
	}

	for d in c.decls {
		if d.kind != .Func {
			continue
		}

		if stage not_in c.funcs[d.index].used {
			continue
		}

		spv_function(g, Func_Index(d.index))
	}

	main_id := g.func_ids[c.main_funcs[stage]]
	out := make([dynamic]u32, 0, 64 + len(g.debug) + len(g.annotations) + len(g.globals) + len(g.code))
	append(&out, 0x07230203, 0x00010000, 0, g.next_id, 0)
	spv_op(&out, 17, 1)

	if g.uses_image_query {
		spv_op(&out, 17, 50)
	}

	spv_op_string(&out, 11, { g.ext_glsl }, "GLSL.std.450")
	spv_op(&out, 14, 0, 1)
	spv_op_string(&out, 15, { stage == .Vertex ? 0 : 4, main_id }, "main", g.interface[:])

	if stage == .Fragment {
		spv_op(&out, 16, main_id, 7)

		if g.uses_frag_depth {
			spv_op(&out, 16, main_id, 12)
		}
	}

	append(&out, ..g.debug[:])
	append(&out, ..g.annotations[:])
	append(&out, ..g.globals[:])
	append(&out, ..g.code[:])
	return slice.to_bytes(out[:])
}
