package karl2d_shader_compiler

Scalar :: enum u8 {
	None,
	Bool,
	Int,
	Uint,
	Float,
}

Type_Kind :: enum u8 {
	None,
	Void,
	Scalar,
	Vector,
	Matrix,
	Sampler_2D,
	Struct,
	Array,
}

Field :: struct {
	name: string,
	type: Type_Index,
	offset: i32,
}

Type :: struct {
	kind: Type_Kind,
	scalar: Scalar,
	size: u8,
	stage: Stage,
	elem: Type_Index,
	len: i32,
	name: string,
	fields: []Field,
}

T_NONE :: Type_Index(0)
T_VOID :: Type_Index(1)
T_BOOL :: Type_Index(2)
T_INT :: Type_Index(3)
T_UINT :: Type_Index(4)
T_FLOAT :: Type_Index(5)
T_BVEC2 :: Type_Index(6)
T_BVEC3 :: Type_Index(7)
T_BVEC4 :: Type_Index(8)
T_IVEC2 :: Type_Index(9)
T_IVEC3 :: Type_Index(10)
T_IVEC4 :: Type_Index(11)
T_UVEC2 :: Type_Index(12)
T_UVEC3 :: Type_Index(13)
T_UVEC4 :: Type_Index(14)
T_VEC2 :: Type_Index(15)
T_VEC3 :: Type_Index(16)
T_VEC4 :: Type_Index(17)
T_MAT2 :: Type_Index(18)
T_MAT3 :: Type_Index(19)
T_MAT4 :: Type_Index(20)
T_SAMPLER_2D :: Type_Index(21)
T_FIRST_USER :: Type_Index(22)

init_types :: proc(c: ^Compiler) {
	append(&c.types, Type {})
	append(&c.types, Type { kind = .Void, name = "void" })
	append(&c.types, Type { kind = .Scalar, scalar = .Bool, size = 1, name = "bool" })
	append(&c.types, Type { kind = .Scalar, scalar = .Int, size = 1, name = "int" })
	append(&c.types, Type { kind = .Scalar, scalar = .Uint, size = 1, name = "uint" })
	append(&c.types, Type { kind = .Scalar, scalar = .Float, size = 1, name = "float" })
	append(&c.types, Type { kind = .Vector, scalar = .Bool, size = 2, name = "bvec2" })
	append(&c.types, Type { kind = .Vector, scalar = .Bool, size = 3, name = "bvec3" })
	append(&c.types, Type { kind = .Vector, scalar = .Bool, size = 4, name = "bvec4" })
	append(&c.types, Type { kind = .Vector, scalar = .Int, size = 2, name = "ivec2" })
	append(&c.types, Type { kind = .Vector, scalar = .Int, size = 3, name = "ivec3" })
	append(&c.types, Type { kind = .Vector, scalar = .Int, size = 4, name = "ivec4" })
	append(&c.types, Type { kind = .Vector, scalar = .Uint, size = 2, name = "uvec2" })
	append(&c.types, Type { kind = .Vector, scalar = .Uint, size = 3, name = "uvec3" })
	append(&c.types, Type { kind = .Vector, scalar = .Uint, size = 4, name = "uvec4" })
	append(&c.types, Type { kind = .Vector, scalar = .Float, size = 2, name = "vec2" })
	append(&c.types, Type { kind = .Vector, scalar = .Float, size = 3, name = "vec3" })
	append(&c.types, Type { kind = .Vector, scalar = .Float, size = 4, name = "vec4" })
	append(&c.types, Type { kind = .Matrix, scalar = .Float, size = 2, name = "mat2" })
	append(&c.types, Type { kind = .Matrix, scalar = .Float, size = 3, name = "mat3" })
	append(&c.types, Type { kind = .Matrix, scalar = .Float, size = 4, name = "mat4" })
	append(&c.types, Type { kind = .Sampler_2D, name = "sampler2D" })
}

type_vec :: proc(scalar: Scalar, size: int) -> Type_Index {
	if size == 1 {
		return Type_Index(int(T_BOOL) + int(scalar) - 1)
	}

	return Type_Index(int(T_BVEC2) + (int(scalar) - 1) * 3 + size - 2)
}

type_mat :: proc(size: int) -> Type_Index {
	return Type_Index(int(T_MAT2) + size - 2)
}

type_array :: proc(c: ^Compiler, elem: Type_Index, length: int) -> Type_Index {
	for i in int(T_FIRST_USER)..<len(c.types) {
		t := c.types[i]

		if t.kind == .Array && t.elem == elem && int(t.len) == length {
			return Type_Index(i)
		}
	}

	append(&c.types, Type { kind = .Array, elem = elem, len = i32(length) })
	return Type_Index(len(c.types) - 1)
}

type_is_numeric :: proc(c: ^Compiler, t: Type_Index) -> bool {
	ty := c.types[t]

	if ty.kind != .Scalar && ty.kind != .Vector && ty.kind != .Matrix {
		return false
	}

	return ty.scalar != .Bool
}

type_is_scalar_or_vector :: proc(c: ^Compiler, t: Type_Index) -> bool {
	k := c.types[t].kind
	return k == .Scalar || k == .Vector
}

type_contains_sampler :: proc(c: ^Compiler, t: Type_Index) -> bool {
	ty := c.types[t]

	switch ty.kind {
	case .Sampler_2D:
		return true

	case .Array:
		return type_contains_sampler(c, ty.elem)

	case .Struct:
		for f in ty.fields {
			if type_contains_sampler(c, f.type) {
				return true
			}
		}

	case .None, .Void, .Scalar, .Vector, .Matrix:
	}

	return false
}

type_contains_bool :: proc(c: ^Compiler, t: Type_Index) -> bool {
	ty := c.types[t]

	#partial switch ty.kind {
	case .Scalar, .Vector:
		return ty.scalar == .Bool

	case .Array:
		return type_contains_bool(c, ty.elem)

	case .Struct:
		for f in ty.fields {
			if type_contains_bool(c, f.type) {
				return true
			}
		}
	}

	return false
}

type_component_count :: proc(c: ^Compiler, t: Type_Index) -> int {
	ty := c.types[t]

	#partial switch ty.kind {
	case .Scalar, .Vector:
		return int(ty.size)

	case .Matrix:
		return int(ty.size) * int(ty.size)
	}

	return 0
}

type_std140_layout :: proc(c: ^Compiler, t: Type_Index) -> (size: int, align: int) {
	ty := c.types[t]

	switch ty.kind {
	case .Scalar:
		return 4, 4

	case .Vector:
		switch ty.size {
		case 2: return 8, 8
		case 3: return 12, 16
		case 4: return 16, 16
		}

	case .Matrix:
		return 16 * int(ty.size), 16

	case .Array:
		elem_size, elem_align := type_std140_layout(c, ty.elem)
		elem_align = max(elem_align, 16)
		stride := (elem_size + elem_align - 1) / elem_align * elem_align
		return stride * int(ty.len), elem_align

	case .Struct:
		offset := 0
		struct_align := 16

		for f in ty.fields {
			field_size, field_align := type_std140_layout(c, f.type)
			offset = (offset + field_align - 1) / field_align * field_align
			offset += field_size
			struct_align = max(struct_align, field_align)
		}

		return (offset + struct_align - 1) / struct_align * struct_align, struct_align

	case .None, .Void, .Sampler_2D:
	}

	return 0, 1
}

type_name :: proc(c: ^Compiler, t: Type_Index) -> string {
	ty := c.types[t]

	if ty.kind == .Array {
		return "array"
	}

	return ty.name
}
