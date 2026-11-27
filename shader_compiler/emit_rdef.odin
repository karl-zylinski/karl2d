package karl2d_shader_compiler

rdef_string :: proc(buf: ^[dynamic]u8, str: string) -> u32 {
	offset := u32(len(buf))
	put_string(buf, str)
	pad_to_4(buf)
	return offset
}

rdef_type :: proc(c: ^Compiler, buf: ^[dynamic]u8, t: Type_Index) -> u32 {
	ty := c.types[t]
	elements := 0

	if ty.kind == .Array {
		elements = int(ty.len)
		ty = c.types[ty.elem]
	}

	class: u16
	base: u16
	rows := u16(1)
	columns := u16(ty.size)
	members_offset: u32

	switch ty.scalar {
	case .Bool: base = 1
	case .Int: base = 2
	case .Float: base = 3
	case .Uint: base = 19
	case .None:
	}

	#partial switch ty.kind {
	case .Vector:
		class = 1

	case .Matrix:
		class = 3
		rows = u16(ty.size)
		base = 3

	case .Struct:
		class = 5
		base = 0
		rows = 0
		columns = 0
		entries := make([][3]u32, len(ty.fields), c.allocator)

		for f, f_idx in ty.fields {
			entries[f_idx] = { rdef_string(buf, f.name), rdef_type(c, buf, f.type), u32(f.offset) }
		}

		members_offset = u32(len(buf))

		for e in entries {
			put_u32(buf, e[0])
			put_u32(buf, e[1])
			put_u32(buf, e[2])
		}
	}

	offset := u32(len(buf))
	put_u16(buf, class)
	put_u16(buf, base)
	put_u16(buf, rows)
	put_u16(buf, columns)
	put_u16(buf, u16(elements))
	put_u16(buf, ty.kind == .Struct ? u16(len(ty.fields)) : 0)
	put_u32(buf, members_offset)
	return offset
}

emit_rdef :: proc(c: ^Compiler, stage: Stage, constants_used: bool, textures_used: bit_set[0..<32]) -> []u8 {
	buf := make([dynamic]u8, 0, 512, c.allocator)
	resize(&buf, 28)
	binding_count := constants_used ? 1 : 0

	for t in 0..<len(c.textures) {
		if t in textures_used {
			binding_count += 2
		}
	}

	bindings_at := len(buf)
	resize(&buf, len(buf) + binding_count * 32)
	at := bindings_at

	for t in 0..<len(c.textures) {
		if t not_in textures_used {
			continue
		}

		sampler_name := rdef_string(&buf, c.vars[c.textures[t]].name)
		set_u32(buf[:], at, sampler_name)
		set_u32(buf[:], at + 4, 3)
		set_u32(buf[:], at + 20, u32(t))
		set_u32(buf[:], at + 24, 1)
		set_u32(buf[:], at + 28, 1)
		at += 32
	}

	for t in 0..<len(c.textures) {
		if t not_in textures_used {
			continue
		}

		texture_name := rdef_string(&buf, c.vars[c.textures[t]].name)
		set_u32(buf[:], at, texture_name)
		set_u32(buf[:], at + 4, 2)
		set_u32(buf[:], at + 8, 5)
		set_u32(buf[:], at + 12, 4)
		set_u32(buf[:], at + 16, 0xffffffff)
		set_u32(buf[:], at + 20, u32(t))
		set_u32(buf[:], at + 24, 1)
		set_u32(buf[:], at + 28, 0xd)
		at += 32
	}

	buffer_at := 0

	if constants_used {
		binding_name := rdef_string(&buf, CONSTANTS_BLOCK_NAME)
		set_u32(buf[:], at, binding_name)
		set_u32(buf[:], at + 24, 1)
		set_u32(buf[:], at + 28, 1)
		variables_at := len(buf)
		resize(&buf, len(buf) + len(c.uniforms) * 24)

		for u, u_idx in c.uniforms {
			v := c.vars[u]
			size, _ := type_std140_layout(c, v.type)
			var_at := variables_at + u_idx * 24
			variable_name := rdef_string(&buf, v.name)
			set_u32(buf[:], var_at, variable_name)
			set_u32(buf[:], var_at + 4, u32(v.offset))
			set_u32(buf[:], var_at + 8, u32(size))
			set_u32(buf[:], var_at + 12, stage in v.used ? 2 : 0)
			variable_type := rdef_type(c, &buf, v.type)
			set_u32(buf[:], var_at + 16, variable_type)
		}

		block_name := rdef_string(&buf, CONSTANTS_BLOCK_NAME)
		put_u32(&buf, block_name)
		put_u32(&buf, u32(len(c.uniforms)))
		put_u32(&buf, u32(variables_at))
		put_u32(&buf, u32(c.constants_size))
		put_u32(&buf, 0)
		put_u32(&buf, 0)
		buffer_at = len(buf) - 24
	}

	creator := rdef_string(&buf, "Karl2D Shader Compiler")
	set_u32(buf[:], 0, constants_used ? 1 : 0)
	set_u32(buf[:], 4, u32(buffer_at))
	set_u32(buf[:], 8, u32(binding_count))
	set_u32(buf[:], 12, u32(bindings_at))
	set_u32(buf[:], 16, stage == .Vertex ? 0xfffe0400 : 0xffff0400)
	set_u32(buf[:], 20, 0x100)
	set_u32(buf[:], 24, creator)
	return buf[:]
}
