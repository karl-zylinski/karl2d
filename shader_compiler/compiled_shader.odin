package karl2d_shader_compiler

import "base:runtime"

COMPILED_SHADER_MAGIC :: 0x4853324b
COMPILED_SHADER_VERSION :: 1
DXBC_INPUT_SEMANTIC :: "ATTR"

Input_Type :: enum u8 {
	F32,
	Vec2,
	Vec3,
	Vec4,
}

Compiled_Input :: struct {
	name: string,
	type: Input_Type,
	location: int,
}

Compiled_Constant :: struct {
	name: string,
	offset: int,
	size: int,
	default_value: []u8,
	rows: int,
	columns: int,
	array_len: int,
	array_stride: int,
}

Compiled_Texture :: struct {
	name: string,
}

Target_Code :: struct {
	vertex: []u8,
	fragment: []u8,
}

Compiled_Shader :: struct {
	bytes: []u8,
	targets: bit_set[Target],
	code: [Target]Target_Code,
	constants_size: int,
	num_inputs: int,
	num_constants: int,
	num_textures: int,
	num_files: int,
	vertex_textures: bit_set[0..<32; u32],
	tables_offset: int,
}

Const_Scalar :: struct {
	scalar: Scalar,
	ival: i64,
	fval: f64,
}

const_components :: proc(c: ^Compiler, e: Expr_Index, vals: ^[16]Const_Scalar, count: ^int) -> bool {
	ex := c.exprs[e]

	#partial switch ex.kind {
	case .Literal:
		if count^ >= 16 {
			return false
		}

		vals[count^] = { c.types[ex.type].scalar, ex.ival, ex.fval }
		count^ += 1
		return true

	case .Var:
		return const_components(c, c.vars[ex.var].init, vals, count)

	case .Unary:
		start := count^

		if !const_components(c, ex.a, vals, count) {
			return false
		}

		for i in start..<count^ {
			vals[i].ival = i64(-i32(vals[i].ival))
			vals[i].fval = -vals[i].fval
		}

		return true

	case .Construct:
		ty := c.types[ex.type]

		if ty.kind != .Scalar && ty.kind != .Vector && ty.kind != .Matrix {
			return false
		}

		args: [16]Const_Scalar
		num_args := 0

		for i in 0..<ex.args_count {
			arg := c.expr_args[ex.args_start + i]

			if c.types[c.exprs[arg].type].kind == .Matrix {
				return false
			}

			if !const_components(c, arg, &args, &num_args) {
				return false
			}
		}

		for i in 0..<num_args {
			a := args[i]

			if a.scalar == ty.scalar {
				continue
			}

			as_float := a.scalar == .Float ? a.fval : f64(a.ival)

			#partial switch ty.scalar {
			case .Float: args[i] = { .Float, 0, f64(f32(as_float)) }
			case .Int: args[i] = { .Int, i64(i32(as_float)), 0 }
			case .Uint: args[i] = { .Uint, i64(u32(as_float)), 0 }
			case .Bool: args[i] = { .Bool, as_float != 0 ? 1 : 0, 0 }
			}
		}

		needed := type_component_count(c, ex.type)

		if count^ + needed > 16 {
			return false
		}

		if ty.kind == .Matrix && num_args == 1 {
			n := int(ty.size)

			for i in 0..<needed {
				vals[count^ + i] = { .Float, 0, i / n == i % n ? args[0].fval : 0 }
			}
		} else if num_args == 1 {
			for i in 0..<needed {
				vals[count^ + i] = args[0]
			}
		} else {
			if num_args < needed {
				return false
			}

			for i in 0..<needed {
				vals[count^ + i] = args[i]
			}
		}

		count^ += needed
		return true
	}

	return false
}

const_default_bytes :: proc(c: ^Compiler, v: Var, dst: []u8) -> bool {
	vals: [16]Const_Scalar
	count := 0

	if !const_components(c, v.init, &vals, &count) {
		return false
	}

	ty := c.types[v.type]

	if count != type_component_count(c, v.type) {
		return false
	}

	rows := int(ty.size)

	for i in 0..<count {
		offset := i * 4

		if ty.kind == .Matrix {
			offset = (i / rows) * 16 + (i % rows) * 4
		}

		word: u32

		if vals[i].scalar == .Float {
			word = transmute(u32)f32(vals[i].fval)
		} else {
			word = u32(vals[i].ival)
		}

		dst[offset + 0] = u8(word)
		dst[offset + 1] = u8(word >> 8)
		dst[offset + 2] = u8(word >> 16)
		dst[offset + 3] = u8(word >> 24)
	}

	return true
}

put_u32 :: proc(buf: ^[dynamic]u8, value: u32) {
	append(buf, u8(value), u8(value >> 8), u8(value >> 16), u8(value >> 24))
}

set_u32 :: proc(buf: []u8, offset: int, value: u32) {
	buf[offset + 0] = u8(value)
	buf[offset + 1] = u8(value >> 8)
	buf[offset + 2] = u8(value >> 16)
	buf[offset + 3] = u8(value >> 24)
}

get_u32 :: proc(buf: []u8, offset: int) -> u32 {
	return u32(buf[offset]) | u32(buf[offset + 1]) << 8 | u32(buf[offset + 2]) << 16 | u32(buf[offset + 3]) << 24
}

put_blob :: proc(buf: ^[dynamic]u8, ref_offset: int, data: []u8) {
	set_u32(buf[:], ref_offset, u32(len(buf)))
	set_u32(buf[:], ref_offset + 4, u32(len(data)))
	append(buf, ..data)
}

HEADER_SIZE :: 36
TARGET_ENTRY_SIZE :: 16
INPUT_ENTRY_SIZE :: 16
CONSTANT_ENTRY_SIZE :: 40
TEXTURE_ENTRY_SIZE :: 8
FILE_ENTRY_SIZE :: 8

serialize_compiled_shader :: proc(c: ^Compiler, code: [Target]Target_Code, allocator: runtime.Allocator) -> []u8 {
	total := HEADER_SIZE + len(Target) * TARGET_ENTRY_SIZE
	total += len(c.inputs) * INPUT_ENTRY_SIZE + len(c.uniforms) * CONSTANT_ENTRY_SIZE
	total += len(c.textures) * TEXTURE_ENTRY_SIZE + len(c.files) * FILE_ENTRY_SIZE
	tables_size := total

	for tc in code {
		total += len(tc.vertex) + len(tc.fragment)
	}

	for i in c.inputs {
		total += len(c.vars[i].name)
	}

	for u in c.uniforms {
		size, _ := type_std140_layout(c, c.vars[u].type)
		total += len(c.vars[u].name) + size
	}

	for t in c.textures {
		total += len(c.vars[t].name)
	}

	for f in c.files {
		total += len(f.name)
	}

	buf := make([dynamic]u8, 0, total, allocator)
	resize(&buf, tables_size)
	targets_mask: u32

	for target in Target {
		if target in c.options.targets {
			targets_mask |= 1 << u32(target)
		}
	}

	set_u32(buf[:], 0, COMPILED_SHADER_MAGIC)
	set_u32(buf[:], 4, COMPILED_SHADER_VERSION)
	set_u32(buf[:], 8, targets_mask)
	set_u32(buf[:], 12, u32(c.constants_size))
	set_u32(buf[:], 16, u32(len(c.inputs)))
	set_u32(buf[:], 20, u32(len(c.uniforms)))
	set_u32(buf[:], 24, u32(len(c.textures)))
	set_u32(buf[:], 28, u32(len(c.files)))
	vertex_textures: u32

	for t, t_idx in c.textures {
		if .Vertex in c.vars[t].used && t_idx < 32 {
			vertex_textures |= 1 << u32(t_idx)
		}
	}

	set_u32(buf[:], 32, vertex_textures)
	at := HEADER_SIZE

	for tc in code {
		put_blob(&buf, at, tc.vertex)
		put_blob(&buf, at + 8, tc.fragment)
		at += TARGET_ENTRY_SIZE
	}

	for i in c.inputs {
		v := c.vars[i]
		put_blob(&buf, at, transmute([]u8)v.name)
		set_u32(buf[:], at + 8, u32(c.types[v.type].size) - 1)
		set_u32(buf[:], at + 12, u32(v.location))
		at += INPUT_ENTRY_SIZE
	}

	for u in c.uniforms {
		v := c.vars[u]
		size, _ := type_std140_layout(c, v.type)
		put_blob(&buf, at, transmute([]u8)v.name)
		set_u32(buf[:], at + 8, u32(v.offset))
		set_u32(buf[:], at + 12, u32(size))
		set_u32(buf[:], at + 16, 0)
		set_u32(buf[:], at + 20, 0)
		shape := c.types[v.type]
		array_len := 0
		array_stride := 0

		if shape.kind == .Array {
			array_len = int(shape.len)
			array_stride = size / array_len
			shape = c.types[shape.elem]
		}

		rows := 0
		columns := 0

		#partial switch shape.kind {
		case .Scalar, .Vector:
			rows = int(shape.size)
			columns = 1

		case .Matrix:
			rows = int(shape.size)
			columns = int(shape.size)
		}

		set_u32(buf[:], at + 24, u32(rows))
		set_u32(buf[:], at + 28, u32(columns))
		set_u32(buf[:], at + 32, u32(array_len))
		set_u32(buf[:], at + 36, u32(array_stride))

		if v.init != 0 {
			default_offset := len(buf)
			resize(&buf, default_offset + size)

			if const_default_bytes(c, v, buf[default_offset:]) {
				set_u32(buf[:], at + 16, u32(default_offset))
				set_u32(buf[:], at + 20, u32(size))
			} else {
				resize(&buf, default_offset)
				compile_error(c, v.file, v.line, "The default value of '%s' is too complex. Only numbers, vectors and matrices are supported", v.name)
			}
		}

		at += CONSTANT_ENTRY_SIZE
	}

	for t in c.textures {
		put_blob(&buf, at, transmute([]u8)c.vars[t].name)
		at += TEXTURE_ENTRY_SIZE
	}

	for f in c.files {
		put_blob(&buf, at, transmute([]u8)f.name)
		at += FILE_ENTRY_SIZE
	}

	return buf[:]
}

get_blob :: proc(bytes: []u8, ref_offset: int) -> (data: []u8, ok: bool) {
	offset := int(get_u32(bytes, ref_offset))
	length := int(get_u32(bytes, ref_offset + 4))

	if offset > len(bytes) {
		return nil, false
	}

	if length > len(bytes) - offset {
		return nil, false
	}

	return bytes[offset:offset + length], true
}

compiled_shader_from_bytes :: proc(bytes: []u8) -> (cs: Compiled_Shader, ok: bool) {
	if len(bytes) < HEADER_SIZE + len(Target) * TARGET_ENTRY_SIZE {
		return
	}

	if get_u32(bytes, 0) != COMPILED_SHADER_MAGIC {
		return
	}

	if get_u32(bytes, 4) != COMPILED_SHADER_VERSION {
		return
	}

	cs.bytes = bytes
	targets_mask := get_u32(bytes, 8)
	cs.constants_size = int(get_u32(bytes, 12))
	cs.num_inputs = int(get_u32(bytes, 16))
	cs.num_constants = int(get_u32(bytes, 20))
	cs.num_textures = int(get_u32(bytes, 24))
	cs.num_files = int(get_u32(bytes, 28))
	cs.vertex_textures = transmute(bit_set[0..<32; u32])get_u32(bytes, 32)
	at := HEADER_SIZE

	for target in Target {
		if targets_mask & (1 << u32(target)) != 0 {
			cs.targets += { target }
		}

		cs.code[target].vertex = get_blob(bytes, at) or_return
		cs.code[target].fragment = get_blob(bytes, at + 8) or_return
		at += TARGET_ENTRY_SIZE
	}

	cs.tables_offset = at
	tables_end := at + cs.num_inputs * INPUT_ENTRY_SIZE + cs.num_constants * CONSTANT_ENTRY_SIZE
	tables_end += cs.num_textures * TEXTURE_ENTRY_SIZE + cs.num_files * FILE_ENTRY_SIZE

	if tables_end > len(bytes) {
		return {}, false
	}

	for i in 0..<cs.num_inputs {
		get_blob(bytes, at + i * INPUT_ENTRY_SIZE) or_return
	}

	at += cs.num_inputs * INPUT_ENTRY_SIZE

	for i in 0..<cs.num_constants {
		get_blob(bytes, at + i * CONSTANT_ENTRY_SIZE) or_return
		get_blob(bytes, at + i * CONSTANT_ENTRY_SIZE + 16) or_return
	}

	at += cs.num_constants * CONSTANT_ENTRY_SIZE

	for i in 0..<cs.num_textures + cs.num_files {
		get_blob(bytes, at + i * TEXTURE_ENTRY_SIZE) or_return
	}

	return cs, true
}

compiled_shader_input :: proc(cs: Compiled_Shader, index: int) -> Compiled_Input {
	at := cs.tables_offset + index * INPUT_ENTRY_SIZE
	name, _ := get_blob(cs.bytes, at)

	return {
		name = string(name),
		type = Input_Type(get_u32(cs.bytes, at + 8)),
		location = int(get_u32(cs.bytes, at + 12)),
	}
}

compiled_shader_constant :: proc(cs: Compiled_Shader, index: int) -> Compiled_Constant {
	at := cs.tables_offset + cs.num_inputs * INPUT_ENTRY_SIZE + index * CONSTANT_ENTRY_SIZE
	name, _ := get_blob(cs.bytes, at)
	default_value, _ := get_blob(cs.bytes, at + 16)

	return {
		name = string(name),
		offset = int(get_u32(cs.bytes, at + 8)),
		size = int(get_u32(cs.bytes, at + 12)),
		default_value = default_value,
		rows = int(get_u32(cs.bytes, at + 24)),
		columns = int(get_u32(cs.bytes, at + 28)),
		array_len = int(get_u32(cs.bytes, at + 32)),
		array_stride = int(get_u32(cs.bytes, at + 36)),
	}
}

compiled_shader_texture :: proc(cs: Compiled_Shader, index: int) -> Compiled_Texture {
	at := cs.tables_offset + cs.num_inputs * INPUT_ENTRY_SIZE + cs.num_constants * CONSTANT_ENTRY_SIZE
	at += index * TEXTURE_ENTRY_SIZE
	name, _ := get_blob(cs.bytes, at)
	return { name = string(name) }
}

compiled_shader_file :: proc(cs: Compiled_Shader, index: int) -> string {
	at := cs.tables_offset + cs.num_inputs * INPUT_ENTRY_SIZE + cs.num_constants * CONSTANT_ENTRY_SIZE
	at += (cs.num_textures + index) * TEXTURE_ENTRY_SIZE
	name, _ := get_blob(cs.bytes, at)
	return string(name)
}
